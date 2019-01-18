# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::CVE;

use warnings;
use strict;

use Carp qw(confess);
use XML::LibXML::XPathContext;
use XML::LibXML;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Configuration::CVE;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::HttpUtil          qw(lwpRequest);
use Taranis::Install::Config   qw(config_generic);
use Taranis::Lock ();
use Taranis::Log  ();

sub cve_control(%);
sub cve_descriptions($);
sub related_cpes($$);
sub cpe_update_file($$$$$);
sub collect_cpes($$$$);

my $cve_ns      = 'http://scap.nist.gov/schema/feed/vulnerability/2.0';
my $cve_vuln_ns = 'http://scap.nist.gov/schema/vulnerability/0.4';
my $cpe_lang_ns = 'http://cpe.mitre.org/language/2.0';

my %handlers = (
	descriptions   => \&cve_descriptions,
	'related-cpes' => \&cve_related_cpes,
);

Taranis::Commands->plugin(cve => {
	handler       => \&cve_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l=s',
		'versions|v!',
		'reset|r!',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  descriptions [-l]   update the cve descriptions from remote resources
  related-cpes [-lrv] collect cpe's linked to cve's from remote resources

OPTIONS:
  -l --log FILE       alternative log-file location (may be '-' or '/dev/null')
  -v --versions       do not ignore versions in cpe (default --no-versions)
  -r --reset          reset the collected data
__HELP
} );

sub cve_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

    $handler->(\%args);
}

sub cve_descriptions($) {
	my $args       = shift;

	@{$args->{files}}==0
		or die "ERROR: no filenames expected.\n";

	my $config  = Taranis::Config->new();
	my $db      = Database->simple;
	my $cve_config = Taranis::Configuration::CVE->new( $config );

	my $generic = config_generic;
	my $logger  = Taranis::Log->new('cve-descriptions', $args->{log});
	my $lock    = Taranis::Lock->lockProcess('cve-descriptions');

	# We do not need to keep the processed files, but it improves the
	# tracebility, to resolve issues.
	my $savedir = "$generic->{var}/cve-descriptions";

	my @cvedefs = $db->query( <<'__CVEDEF_FILES' )->hashes;
 SELECT *
   FROM download_files
  WHERE name = 'cve_description'
  ORDER BY filename
__CVEDEF_FILES

	foreach my $cvedef (@cvedefs) {
		my $file_url = $cvedef->{file_url};

		$logger->info("[START  ] $file_url");
		my $head_resp = lwpRequest(head => $file_url);
		$head_resp->is_success
			or next;   #XXX no error?

		my $last_modified = $head_resp->headers->{"last-modified"} || 'unknown';
		my $last_change   = $cvedef->{last_change} || 'never';

		if($last_modified eq $last_change) {
			$logger->info("[DONE   ] $file_url is unchanged, no action needed");
			next;
		}

		$logger->info("[LOAD   ] $file_url");

		my $resp = lwpRequest(get => $file_url);
		unless($resp->is_success) {
			$logger->info("[ERROR  ] " . $resp->status_line);
			next;
		}

		my $logfn     = "$savedir/$cvedef->{filename}";
	 	my $content   = $resp->decoded_content || $resp->content;

		# Just for debugging/tracing/development
		open OUT, '>:encoding(utf8)', $logfn
			or die "ERROR: cannot write $logfn: $!\n";
		print OUT $content;
		close OUT;

		my $xmlParser = XML::LibXML->new;
		my $doc       = $xmlParser->load_xml(string => $content);
		my $xpc       = XML::LibXML::XPathContext->new($doc->documentElement);
		$xpc->registerNs(cvrf   => 'http://www.icasi.org/CVRF/schema/cvrf/1.1');
		$xpc->registerNs(nsVuln => 'http://www.icasi.org/CVRF/schema/vuln/1.1');

		my @cves      = $xpc->findnodes('//cvrf:cvrfdoc/nsVuln:Vulnerability');
		my $records   = @cves;
		$logger->info("[PROCESS] $records records to process");

		foreach my $cve (@cves) {
			my $cveID_node = $xpc->findnodes('.//nsVuln:CVE', $cve)->shift;
			my $cveID      = $cveID_node ? $cveID_node->textContent : undef;

			my $descr_node = $xpc->findnodes("nsVuln:Notes/nsVuln:Note[\@Type='Description']", $cve)->shift;
			my $description= $descr_node ? $descr_node->textContent : undef;

			my $publ_node  = $xpc->findnodes("nsVuln:Notes/nsVuln:Note[\@Title='Published']", $cve)->shift;
			my $published  = $publ_node  ? $publ_node->textContent : undef;

			my $modif_node = $xpc->findnodes("nsVuln:Notes/nsVuln:Note[\@Title='Modified']", $cve)->shift;
			my $modified   = $modif_node ? $modif_node->textContent : undef;

			if(my $has = $db->query(<<'__EXISTS', $cveID)->hash) {
SELECT * FROM identifier_description WHERE identifier = ?
__EXISTS

				my $has_modif = $has->{modified_date} || 'never';
				$cve_config->setCVE(
					description    => $description,
					published_date => $published,
					modified_date  => $modified,
					identifier     => $cveID,
				) if $has_modif ne ($modified || 'never');

			} else {
				$cve_config->addCVE(
					description    => $description,
					published_date => $published,
					modified_date  => $modified,
					identifier     => $cveID,
				);
			}
		}

		# Update DB date stamp
		$db->query( <<'__UPDATED', $last_modified, $file_url);
 UPDATE download_files SET last_change = ?  WHERE file_url = ?
__UPDATED

		$logger->info("[DONE   ] $file_url processed");
	}

	$logger->close;
	$lock->unlock;
	$db->disconnect;
}

### taranis cve related-cpes

sub cve_related_cpes($) {
	my $args    = shift;

	$args->{versions} = 0 if !exists $args->{versions};
	@{$args->{files}} == 0
		or die "No filenames expected\n";

	my $db      = Database->simple;
	my $logger  = Taranis::Log->new('cve-related-cpes', $args->{log});
	my $lock    = Taranis::Lock->lockProcess('cve-related-cpes');

	if($args->{reset}) {
		$logger->info('restarting the cve_cpe table');
		$db->query("DELETE FROM cpe_cve");
	}

	my $generic = config_generic;
	my $download_path = "$generic->{var}/cve-details";

	my @file_defs = $db->query( <<'__FILE_DEFS' )->hashes;
 SELECT * FROM download_files WHERE name = 'cpe_download'
__FILE_DEFS

	foreach my $file_def (@file_defs) {
		my $modified = cpe_update_file $db, $logger, $download_path,
			$file_def, $args;

		$modified or next;

		$db->query( <<'__REMEMBER_UPDATE', $modified, $file_def->{filename});
 UPDATE download_files SET last_change = ? WHERE filename = ?
__REMEMBER_UPDATE
	}

	$logger->close;
	$lock->unlock;
	$db->disconnect;
}

sub cpe_update_file($$$$$) {
	my ($db, $logger, $download_path, $file_def, $args) = @_;

	my $filename = $file_def->{filename};
	my $url      = $file_def->{file_url};

	$logger->info("[START] $url");

	#XXX should use LWP differently: with one request containing
	#XXX If-Modified-Since

	my $res = lwpRequest(head => $url);
	unless($res->is_success) {
	 	$logger->error("HEAD request $url: " . $res->status_line);
		return undef;
	}

	my $last_modified = $res->headers->last_modified || '';
	my $last_change   = $file_def->{last_change} || 'never';
	if($last_modified eq $last_change) {
		$logger->info("no changes since last update for $filename");
#		return undef;
	}

	my $downloaded_fn = "$download_path/$filename";
	$logger->info("downloading $downloaded_fn");
	$res = lwpRequest(get => $url, ':content_file' => $downloaded_fn);

	unless($res->is_success ) {
		$logger->error("GET request $url: " . $res->status_line);
		return undef;
	}

	$logger->info("process $downloaded_fn");

	collect_cpes $db, $logger, $downloaded_fn, $args;
	$logger->info("saving to database done");

	$last_modified;
}

### collect_cpes
#   Find all cpe's mentioned per CVE, and update the database
#   accordingly.

sub collect_cpes($$$$) {
	my ($db, $logger, $fn, $args) = @_;
	my $take_versions = $args->{versions};

	my $doc    = XML::LibXML->load_xml(location => $fn);
	my $xp     = XML::LibXML::XPathContext->new($doc->documentElement);
	$xp->registerNs(cve  => $cve_ns);
	$xp->registerNs(vuln => $cve_vuln_ns);
	$xp->registerNs(lang => $cpe_lang_ns);

	my %cve_cpe_list;

  ENTRY:
	foreach my $entry ($xp->findnodes('//cve:entry')) {
		my $cve_id = $entry->find('./@id')->string_value;

		### Software / hardware references
		my @cpes   = map $_->string_value,
			$xp->findnodes('vuln:vulnerable-software-list/vuln:product',$entry);

		### Platforms as well
		#XX SWHW is found again.  Always double?
		# cpe-lang:logical-test may be nested, but at least 1 level
		my @tests = $xp->findnodes('vuln:vulnerable-configuration/lang:logical-test', $entry);
		foreach my $test (@tests) {
			push @cpes, map $_->string_value,
 				$xp->findnodes('.//lang:fact-ref/@name', $test);
		}

		my %cpes;
		if($take_versions) {
			$cpes{$_}++ for @cpes;
		} else {
			$cpes{simplified_cpe $_}++ for @cpes;
		}

		$cve_cpe_list{$cve_id} = [sort keys %cpes];
	}

	#XXX no removes?
	my ($total_relations, $added_relations) = (0, 0);
	while( my ($cve_id, $cpes) = each %cve_cpe_list ) {
		foreach my $cpe_id (@$cpes) {
			$total_relations++;
			next if $db->query( <<'__EXISTS', $cve_id, $cpe_id)->list;
 SELECT 1 FROM cpe_cve WHERE cve_id = ? AND cpe_id = ?
__EXISTS

			$logger->info("add CVE=$cve_id CPE=$cpe_id");
			$added_relations++;

			$db->query(<<'__ADD', $cve_id, $cpe_id);
 INSERT INTO cpe_cve (cve_id, cpe_id) VALUES (?,?)
__ADD
		}
	}

	$logger->info("found $total_relations relations, $added_relations new in $fn");
}

1;
