# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::CPE;

use warnings;
use strict;

use Carp           qw(confess);
use XML::LibXML    ();
use File::Basename qw(basename);
use File::Copy     qw(move);

use Taranis                    qw(simplified_cpe);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::HttpUtil          qw(lwpRequest);
use Taranis::Install::Config   qw(config_generic);

my $nist_url = 'http://static.nvd.nist.gov/feeds/xml/cpe/dictionary';
my $dict_url = "$nist_url/official-cpe-dictionary_v2.3.xml.gz";
my $dict_ns  = 'http://cpe.mitre.org/dictionary/2.0';

my %handlers = (
	'dictionary'  => \&cpe_dictionary
);

Taranis::Commands->plugin(cpe => {
	handler       => \&cpe_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l=s',
		'deprecated|d!',
		'reset|r!',
		'versions!',
	],
	help          => <<__HELP,
SUB-COMMANDS:
  dictionary [-ldrv][<file>]  update the full software/hardware cpe list

OPTIONS:
  -l --log FILENAME    alternative log-file location (maybe '-' or /dev/null)
  -d --deprecated      include deprecated cpe's      (default no)
     --versions        do not ignore version numbers (default --no-versions)
  -r --reset           clean the cpe-administration first

If you do not specify a <file>, the latest will get downloaded from
$dict_url
__HELP
} );

sub cpe_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub cpe_dictionary($) {
	my $args   = shift;
	my $take_deprecated = $args->{deprecated};
	my $ignore_versions = exists $args->{versions} ? $args->{versions} : 1;

	my $logger = Taranis::Log->new('cpe-dictionary', $args->{log});
	$logger->info("----START----");

	my ($generic, $file);
	if(my @files = @{$args->{files} || []}) {
		$file  = shift @files;
		-f $file
			or $logger->error("missing file $file");
	} else {
		$generic ||= config_generic;
		$file    = "$generic->{var}/cpe-dictionary/".basename $dict_url;
		my $part = "$file.part";
		$logger->info("collecting latest from $dict_url");

		my $resp = lwpRequest get => $dict_url, ':content_file' => $part;
		unless($resp->is_success) {
			unlink $part;
			$logger->error("cannot get $dict_url: ".$resp->status_line);
			exit 1;
		}

		unless(move $part, $file) {
			$logger->error("cannot enable $file: $!");
			exit 1;
		}

		$logger->info(sprintf 'compressed dictonary size is %d kB',
			(-s $file)/1024);
	}

	$logger->info("parsing file $file");
	my $doc    = XML::LibXML->load_xml(location => $file);
	my $xp     = XML::LibXML::XPathContext->new($doc->documentElement);
	$xp->registerNs(dict => $dict_ns);

	my @cpes   = $xp->findnodes('//dict:cpe-item');

	my $all_cpes = @cpes;
	$logger->info(qq{processing $all_cpes cpe's});

 	my $db       = Database->{simple};

	if($args->{reset}) {
		# only throw away the table if we are reasonably sure we have new data.
		$logger->info("resetting the cpe dictionary");
		$db->query('DELETE FROM software_hardware');
	}

	my ($added, $changed, $unchanged) = (0, 0, 0);
	my ($all_deprecated, $skip_deprecated) = (0, 0);

  CPE:
	foreach my $cpe (@cpes) {
	    my $cpe_name = $xp->find('@name', $cpe)->string_value;
	    my ($prefix, $part, $vendor, $product, $version) =   # there are more
			split /\:/, $cpe_name;
	    $part      =~ s!^/!!;
		$version ||= '-';

		my $is_depr_attr  = $xp->find('@deprecated',$cpe)->string_value || 'false';
		my $is_deprecated = $is_depr_attr eq '1' || $is_depr_attr eq 'true';
		$all_deprecated++ if $is_deprecated;

	    my $title = $xp->find('dict:title[@xml:lang="en-US"]',$cpe)->string_value;
	    $title =~ s/^$vendor\s+//i;
	    $title =~ s/\s+$version$//i;	

		s/\%([0-9A-Za-z]{2})/chr hex $1/ge
			for $title, $vendor, $version;

	    undef $version
			if !length $version || $version eq '-';

		if($ignore_versions) {
			# make the CPE version neutral
			$version  = '-';
			$cpe_name = simplified_cpe $cpe_name;
		}

		my $has = $db->query(<<'__EXISTS', $cpe_name)->hash;
 SELECT * FROM software_hardware WHERE cpe_id = ?
__EXISTS

		if(!$has && $is_deprecated && !$take_deprecated) {
			$skip_deprecated++;
			next CPE;
		}

		my $action;
		if(!$has) {
			$action = 'insert';
			$added++;

			$logger->info("+++ $cpe_name = $title");

			$db->query(<<'__INSERT', $cpe_name, $title, $vendor,$part,$version);
 INSERT INTO software_hardware
        (cpe_id, name, producer, type, version, deleted, monitored)
 VALUES (?, ?, ?, ?, ?, 'f', 'f');
__INSERT
			next CPE;
		}

		if(   $has->{name}     ne $title
           || $has->{producer} ne $vendor
		   || $has->{type}     ne $part
		   || ($has->{version}||'') ne ($version||'')
          ) {
			$action = 'update';
	        $changed++;

			{ no warnings;
			  $logger->info(">>> $title,$vendor,$part,$version,$cpe_name");
			  my @fields = qw/name producer type version/;
			  $logger->info('<<< '.join(',',@{$has}{@fields}));
			}

			$db->query(<<'__UPDATE',$title,$vendor,$part,$version,$cpe_name);
 UPDATE software_hardware
    SET name = ?, producer = ?, type = ?, version = ?
  WHERE cpe_id = ?
__UPDATE
			next CPE;
		}

	    ++$unchanged;
	}

	my $final_thought = <<__SUMMARY;
 full cpe list: $all_cpes
  new inserted: $added
       updated: $changed
    deprecated: $skip_deprecated (ignored)
__SUMMARY

	$logger->info("Summary:\n$final_thought");
	$logger->info("----END----");
	$logger->close;

	$db->disconnect;
}
