# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Phish;

use warnings;
use strict;

use Carp           qw(confess);
use Digest::MD5    qw(md5_base64);
use Encode;
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

	my $db     = Database->{simple};
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

		$db->query(<<'__DELETE', $oid);
 DELETE FROM phish_image WHERE object_id = ?
__DELETE

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

	my $shooter    = Taranis::Screenshot->new(
		screenshot_module => Config->{screenshot_module},
		proxy_host  => (uc Config->{proxy} eq 'ON' ? Config->{proxy_host} : undef),
	);

	my $phishdownkeysfile = find_config(Config->{phishdownkeysfile});
	open my $fh, "<:encoding(utf8)", $phishdownkeysfile
		or die "I Can't read $phishdownkeysfile, $!\n";
	my @downkeys = <$fh>;
	close $fh;

	my $index_total   = -1;
	my $db            = Database->{simple};
	my $phish_results = $db->select('phish');

	while(my $record = $phish_results->hash) {
		my $url = trim $record->{url};

		$logger->info("checking phish site at $url");
		$collector->{no_db} = 1;

		my $status = $collector->{http_status_line} || 'no response';
		my $result = encode_entities($collector->getSourceData($url), $record)
			or $logger->warning("empty with $status");

		$result =~ s /\n/<newline>/gi;
		my $md5_now = md5_base64 Encode::encode_utf8($result);

		$index_total = -1;
		foreach my $downkey ( @downkeys ) {
			$downkey  =~ s/\n//g;
			my $is_in = index(uc $result, uc $downkey);
			$index_total += $is_in if $is_in > -1;
		}

		### Check current status of phishing website
		my $counter_down        = $record->{counter_down};
		my $counter_hash_change = $record->{counter_hash_change};

		my $status_before = "online";
		if($counter_down >= 2) {
			$status_before = "down";
		} elsif($counter_hash_change >= 2 && $counter_down < 2) {
			$status_before = "hash changed";
		}

		my ($datetime_down, $datetime_hash_change);

		#XXX The current implementatin of the collector returns '0' when it
		#    means 'undef'.  Valid returns are non-numeric strings.
		if($index_total > -1 || $result eq 0) {
			$counter_down = $record->{counter_down};
			$counter_down++;
			if($counter_down >= 2) {
				$datetime_down = $record->{datetime_down} || nowstring(2);
			}
		} else {
			$counter_down  = 0;
			$datetime_down = 0;
		}

		my $md5_orig = $record->{hash} ||= '';
		my $screenshot;

		if($md5_now eq $md5_orig) {
			$counter_hash_change  = 0;
			$datetime_hash_change = 0;
		} elsif($result) {
			if($screenshot = $shooter->takeScreenshot(siteAddress => $url)) {
				 my $blobDetails = Database->addFileAsBlob(binary => $screenshot)
					or next;

				$db->query( <<'__INSERT', $record->{id}, $blobDetails->{oid}, $blobDetails->{fileSize});
 INSERT INTO phish_image
    (phish_id, object_id, file_size)
 VALUES (?, ?, ?)
__INSERT
			}
		}
		
		if( $md5_orig eq "" ) {
			$counter_hash_change  = 0;
			$datetime_hash_change = 0;
			$db->query( <<'__UPDATE', $md5_now, $url);
 UPDATE phish  SET hash = ?  WHERE url  = ?
__UPDATE
		} else {
			$counter_hash_change = $record->{counter_hash_change};
			$counter_hash_change++;
			$datetime_hash_change = $record->{datetime_hash_change} || nowstring(2)
				if $counter_hash_change >= 2;
		}

		$db->query( <<'__UPDATE',
 UPDATE phish
    SET datetime_down        = ?,
        datetime_hash_change = ?,
        counter_down         = ?,
        counter_hash_change  = ?
  WHERE id = ?
__UPDATE
			$datetime_down, $datetime_hash_change, $counter_down,
			$counter_hash_change, $record->{id},
		);

		my $status_change;
		if ($counter_down == 2) {
			$status_change = "The status for $url changed from '$status_before' to 'down'\n\n";
		} elsif ($counter_hash_change == 2 && $counter_down < 2) {
			$status_change = "The status for $url changed from '$status_before' to 'hash changed'\n\n";
		} elsif ($counter_down == 0 && $status_before eq "down") {
			$status_change = "The status for $url changed from 'offline' to 'online'\n\n";
		}

		$status_change
			or next;

		my $plain   = $status_change; 
		$plain     .= "\n=== CONTENTS ===\n$result\n================\n"
			if !$screenshot;
		$plain      = decode_entities $plain;

		my $subject = "[Taranis] Status change for phish $url";
		$subject   .= " #$record->{reference}" if $record->{reference};

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
