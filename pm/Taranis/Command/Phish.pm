# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Phish;

use warnings;
use strict;

use Carp           qw(confess);
use Digest::MD5    qw(md5_base64);
use Encode         qw(encode_utf8);
use HTML::Entities qw(encode_entities decode_entities);

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Config);
use Taranis::Collector;
use Taranis::Screenshot;
use Taranis::Log      ();
use Taranis           qw(find_config trim nowstring);
use Taranis::Mail     ();

my %handlers = (
	'cleanup-images' => \&phish_cleanup_images,
	'check-down'     => \&phish_check_down,
);

Taranis::Commands->plugin(phish => {
	handler       => \&phish_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l=s'
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  cleanup-images          remove all but last image per source
  check-down [-l]         check which known phishing sites changed status

OPTIONS:
	-l --log FILENAME     redirect log
__HELP
} );

sub phish_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub phish_cleanup_images($) {
	my $args   = shift;

	my $db     = Database->simple;
	my $logger = Taranis::Log->new('phish-cleanup-images', $args->{log});

	my %seen;
	my @delete = grep $seen{$_->{phish_id}}++,
		$db->query(<<'__IMAGES')->hashes;
 SELECT * FROM phish_image
  ORDER BY phish_id, timestamp DESC
__IMAGES

	$logger->info('deleting '.@delete.' images, keeping '.keys(%seen));

	foreach my $victim (@delete) {
		my $pid  = $victim->{phish_id};
		my $oid  = $victim->{object_id};
		my $size = sprintf "%d", $victim->{file_size}/1024;
		$logger->info("deleting phish_id=$pid oid=$oid, $size Kb");

		$db->deleteRecord(phish_image => $oid, 'object_id');
		my $still_present = $db->query(<<'__CHECK_REMOVED', $oid)->list;
 SELECT 1 FROM pg_largeobject WHERE loid => ?
__CHECK_REMOVED

		$logger->error("loid $oid still exists!")
			if $still_present;
	}

	$logger->info("deleted ".@delete." phishing images");
	$logger->close;
}

# originally script backend_scripts/checkphish.pl
sub phish_check_down($) {
	my $args = shift;

	my $logger     = Taranis::Log->new('phishing-sites-down', $args->{log});
	my $collector  = Taranis::Collector->new(Config);
	my $proxy_host = Config->isEnabled('proxy') ? Config->{proxy_host} : undef;

	my $shooter    = Taranis::Screenshot->new(
		screenshot_module => Config->{screenshot_module},
		proxy_host => $proxy_host,
	);

	my $phishdownkeysfile = find_config(Config->{phishdownkeysfile});
	open my $fh, "<:encoding(utf8)", $phishdownkeysfile
		or die "I Can't read $phishdownkeysfile, $!\n";
	my @downkeys = map decode_entities($_), <$fh>;   # one regex per line
	chomp @downkeys;
	my $downkeys;
	{ local $" = '|'; $downkeys = qr/(@downkeys)/i; }  # "
	close $fh;

	my $db         = Database->simple;
	my $phishers   = $db->select('phish');

  PHISHER:
	while(my $phisher = $phishers->hash) {
		my $url      = trim $phisher->{url};
		my $phish_id = $phisher->{id};

		$logger->info("checking phish site at $url");
		my $result   = $collector->getSourceData($url, $phisher);

		my $contains;
		if(!defined $result || $result eq '0') {
			#XXX Some implementations of the collector return '0' when they
			#    mean 'undef'.  Valid returns are non-numeric strings.
			$result    = '';
			my $status = $collector->{http_status_line} || 'no response';
			$logger->info("phishing response from $url empty with '$status'");
		} else {
			$contains  = $result =~ $downkeys;
		}

		# Check current status of phishing website
		# 'counter_down' means 'nr of checks which could not reach the webpage'
		# 'counter_hash_change' means 'nr of changes to the webpage'
		my $counter_down        = $phisher->{counter_down};
		my $counter_hash_change = $phisher->{counter_hash_change};

		my $status_before
		  = $counter_down >= 2 ? 'down'
		  : $counter_hash_change >= 2 && $counter_down < 2 ? 'hash changed'
		  :                      'online';

		my $datetime_down;
		if($contains || ! length $result) {
			$counter_down  = $phisher->{counter_down} + 1;
			$datetime_down = $phisher->{datetime_down} || nowstring(2)
				if $counter_down >= 2;
		} else {
			$counter_down  = 0;
			$datetime_down = 0;
		}

		my $guard = $db->beginWork;
		my ($screenshot, $datetime_hash_change);
		my $md5_now  = md5_base64 encode_utf8 $result;
		my $md5_orig = $phisher->{hash} || '';

		if($md5_now eq $md5_orig) {
			$counter_hash_change  = 0;
			$datetime_hash_change = 0;
		} elsif($result) {
			if($screenshot = $shooter->takeScreenshot(siteAddress => $url)) {
				my ($oid, $size) = $db->addBlob($screenshot);
				$db->addRecord(phish_image => {
					phish_id  => $phish_id,
					object_id => $oid,
					file_size => $size,
				});
			}
		}

		if($md5_orig eq "") {
			$counter_hash_change  = 0;
			$datetime_hash_change = 0;
		} else {
			$counter_hash_change  = $phisher->{counter_hash_change} + 1;
			$datetime_hash_change = $phisher->{datetime_hash_change} || nowstring(2)
				if $counter_hash_change >= 2;
		}

		$db->setRecord(phish => $phisher->{id}, {
			datetime_down        => $datetime_down,
			datetime_hash_change => $datetime_hash_change,
			counter_down         => $counter_down,
			counter_hash_change  => $counter_hash_change,
			hash                 => $md5_now,
		});
		$db->commit($guard);

		my $status_new
		  = $counter_down==2                             ? 'down'
		  : $counter_hash_change==2 && $counter_down < 2 ? 'hash changed'
		  : $counter_down==0 && $status_before eq 'down' ? 'online'
		  : next PHISHER;

		#XXX How far should we clean-up the collected webpage?  Should we strip HTML
		#    markup?  Is it HTML?
		my $plain    = <<__MSG_BODY;
The status for $url changed from '$status_before' to '$status_new'.

=== CONTENTS ===
$result

__MSG_BODY

		my $subject = "[Taranis] Status change for phish $url";
		$subject   .= " #$phisher->{reference}" if $phisher->{reference};

		my $attachment = Taranis::Mail->attachment(
			filename    => 'screenshot.png',
            mime_type   => 'image/png',
			data        => $screenshot,
		) if $screenshot;

		my $msg       = Taranis::Mail->build(
			Subject     => $subject,
			config_from => 'phishfrom',
			config_to   => 'phishto',
			plain_text  => $plain,
			attach      => $attachment,
		);

 		$msg->send;
	}
}

1;
