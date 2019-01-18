# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Send;

use warnings;
use strict;

use Carp           qw(confess);
use List::Util     qw(first);
use HTML::Entities qw(decode_entities);
use POSIX          qw(strftime);

use Taranis        qw(tmp_path val_int val_date);
use Taranis::Log   ();
use Taranis::Config;
use Taranis::Database;
use Taranis::Report::SpecialInterest;
use Taranis::FunctionalWrapper qw(Config Database ReportSpecialInterest);
use Taranis::Mail  ();

my $db;

my %handlers = (
	'specint-reminders' => \&send_specint_reminders,
	'advisory-counts'   => \&send_advisory_counts,
);

my %osgroups = (
	windows => [ qw/windows/ ],
	bsd     => [ qw/bsd/ ],
	unix	=> [ qw/unix aix hp-ux irix solaris sunos tru64/ ],
	linux   => [ qw/linux centos fedora opensuse redhat/ ],
	apple   => [ qw/iphone/, 'mac os' ],
);

Taranis::Commands->plugin(send => {
	handler       => \&send_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'begin|b=s',
		'log|l=s',
		'to|t=s',
		'until|u=s',
		'year|y=i',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  specint-reminders [-l]     send 3 days special interest reminders
  advisory-counts [-bltuy]   overview on created advisories

OPTIONS:
  -l --log FILENAME       alternative logging (maybe '-' for stdout)
  -y --year 2018          year of interest (default this year)
  -b --begin 2018-09-01   start date (dashes optional)
  -t --to EMAIL           who gets the email
  -u --until 2018-12-31   end date (dashes optional)
__HELP
} );

sub send_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

# was half of backend_tools/report.pl

sub send_specint_reminders($) {
	my $args   = shift;
	$db      ||= Database->simple;

	my $logger = Taranis::Log->new('specint-reminders', $args->{log});

	my @reminders = $db->query( <<'__REMINDERS' )->hashes;
 SELECT *, to_char(date_end, 'DD-MM-YYYY') AS date_end_str
   FROM report_special_interest
  WHERE ( date_end - '3 days'::INTERVAL ) < NOW()
    AND timestamp_reminder_sent IS NULL
__REMINDERS

	@reminders
		or return;

	$logger->info("Got ".@reminders." special interest reminders to send.");

  REMINDER:
	foreach my $reminder (@reminders) {
		my $requestor = decode_entities $reminder->{requestor};
		my $topic     = decode_entities $reminder->{topic};

		my $msg       = Taranis::Mail->build(
			To          => $requestor,
			Subject     => "[Taranis] Reminder for $topic",
			plain_text  => <<__BODY,
This is an automated message for $requestor.

Monitoring of topic $topic will end after $reminder->{date_end_str}.
__BODY
		);
		$msg->send;

		$logger->info("reminder to $requestor sent");

		ReportSpecialInterest->setSpecialInterest(
			id => $reminder->{id},
			timestamp_reminder_sent => \'NOW()',
		);
	}

	$logger->close;
	$db->disconnect;
}

####### was ncsc private yearstats.pl

my ($datestart, $datestop, $timestart, $timestop, %count_advs);

## Attachement

sub _advisory_full_list($) {
	my ($fn) = @_;
	open FILE, '>', $fn or die "ERROR: Cannot write $fn: $!";

	my $records = $db->query(<<__ADV);
 SELECT a.damage, a.probability, a.title, a.version, p.published_on, a.govcertid
   FROM publication_advisory a,
        publication p
  WHERE p.id = a.publication_id
	AND NOT a.deleted
	AND p.published_on BETWEEN '$timestart' AND '$timestop'
  ORDER BY p.published_on;
__ADV

	while (my $record = $records->hash) {
		my $probab  = $record->{probability};
		my $damage  = $record->{damage};
		my $version = $record->{version};
		my $is_update = $version eq '1.00' ? 0 : 1;

		my $probab_level = $probab==1 ? 'H' : $probab==2 ? 'M' : 'L';
		my $damage_level = $damage==1 ? 'H' : $damage==2 ? 'M' : 'L';
		$count_advs{$probab_level}{$damage_level}{$is_update}++;

		my $timestamp = $record->{published_on};
		$timestamp    =~ s/\+.*//;

		print FILE join(' | ',
			$timestamp,
			"$record->{govcertid} [$version]",
			$probab_level,
			$damage_level,
			$record->{title},
		), "\n";
	}

	close FILE;
}

## I

sub _advisories_by_classification() {

	my $mail = <<__I_HEAD;
I. Advisories by classification

$datestart until $datestop
      +-------+-------+-------+
      |  1.00 | >1.00 | Total |
+-----+-------+-------+-------+
__I_HEAD

	my $originals = 0;
	my $updates   = 0;
	foreach my $p ('H', 'M', 'L') {
		foreach my $d ('H', 'M', 'L') {
			my $o = $count_advs{$p}{$d}{0} || 0;
			my $u = $count_advs{$p}{$d}{1} || 0;

			$mail .= sprintf "| $p/$d | %5d | %5d | %5d |\n", $o, $u, $o+$u;

			$originals += $o;
			$updates   += $u;
		}
	}

	my $sum = sprintf "|     | %5d | %5d | %5d |",
		$originals, $updates, $originals+$updates;

	$mail . <<__I_FOOT;
+-----+-------+-------+-------+
$sum
+-----+-------+-------+-------+
__I_FOOT
}


## II

sub _advisories_by_author() {

	my $records = $db->query(<<__II_Q);
 SELECT u.fullname, COUNT(u.fullname) AS cnt
   FROM publication_advisory a, publication p, users u
  WHERE p.id = a.publication_id
	AND NOT a.deleted
	AND p.published_on BETWEEN '$timestart' AND '$timestop'
	AND u.username = p.created_by
  GROUP BY u.fullname
  ORDER BY cnt DESC
__II_Q

	my $mail = <<__II_HEAD;

II. Advisories by author

$datestart until $datestop
+---------------------+-------+
| Author              |  #adv |
+---------------------+-------+
__II_HEAD

	while(my $record = $records->hash) {
		my $user = decode_entities $record->{fullname};
		$mail .= sprintf "| %-19s | %5d |\n", $user, $record->{cnt};
	}

	$mail . "+---------------------+-------+\n";
}


## III

sub _advisories_by_date() {

	my $mail = <<__III_HEAD;
III. Advisories by date

+---------------------+-------+
| Date                |  #adv |
+---------------------+-------+
__III_HEAD

	my $records = $db->query(<<__III_Q);
 SELECT SUBSTR(CAST(p.published_on AS text), 0, 11) AS date, COUNT(*) AS cnt
   FROM publication_advisory a, publication p
  WHERE p.id = a.publication_id
    AND NOT a.deleted
    AND p.published_on BETWEEN '$timestart' AND '$timestop'
  GROUP BY date
  ORDER BY date DESC;
__III_Q

	while(my $record = $records->hash) {
		$mail .= sprintf "| %-19s | %5d |\n", $record->{date}, $record->{cnt};
	}

	$mail . "+---------------------+-------+\n";
}


## IV

sub countos($) {
	my $os = shift;

	my $where = join ' OR ',
		map "s.name ILIKE '%$_%'",
			@{$osgroups{lc $os} || []};

	my $count = $db->query(<<__COUNT_ADV)->list;
 SELECT COUNT(DISTINCT(a.govcertid))
   FROM software_hardware s,
        platform_in_publication p,
        publication u,
        publication_advisory a
  WHERE s.id = p.softhard_id
    AND u.id = p.publication_id
    AND a.publication_id = p.publication_id
    AND ($where)
    AND a.version = '1.00'
    AND u.published_on BETWEEN '$timestart' AND '$timestop'
__COUNT_ADV

	$count;
}

sub _advisories_by_platform() {

	my $mail .= <<__IV_HEAD;
IV. Advisories (1.00) by platform

$datestart until $datestop
+---------------------+-------+
| Platform            |  #adv |
+---------------------+-------+
__IV_HEAD

	foreach my $platform ( qw/Windows Linux Apple UNIX BSD/ ) {
		$mail .= sprintf "| %-19s | %5d |\n", $platform, countos($platform);
	}

	$mail . "+---------------------+-------+\n";
}

## V

sub _sources_per_category() {

	my $today = strftime "%Y-%m-%d", localtime();

	my $mail = <<__V_HEAD;
V. Nr. of enabled sources per category

$today
+---------------------+---------+
| Category            | sources |
+---------------------+---------+
__V_HEAD

	my $records = $db->query(<<__V_Q);
SELECT COUNT(*) AS nrsources, c.name AS category
  FROM sources s, category c 
 WHERE NOT s.deleted
   AND c.id = s.category 
 GROUP BY c.name 
 ORDER BY c.name
__V_Q

	while(my $record = $records->hash) {
		my $cat = decode_entities $record->{category};
		$mail .= sprintf "| %-19s | %7d |\n", $cat, $record->{nrsources};
	}

	$mail . "+---------------------+---------+\n";
}

## VI

sub _analyses_done() {

	my $count = $db->query(<<__VI_Q)->list;
SELECT COUNT(*)
  FROM analysis
 WHERE orgdatetime BETWEEN '$timestart' AND '$timestop'
   AND status = 'done'
__VI_Q

	my $mail  = <<__VI;
VI. Analyses done

$datestart until $datestop
Done are $count analyses.

__VI

	$mail;
}

sub send_advisory_counts(@) {
    my $args   = shift;
    my $logger = Taranis::Log->new('advisory-counts', $args->{log});

	my $year      = val_int  $args->{year}  || (localtime)[5] + 1900;
	my $to        = $args->{to};
	my $file      = tmp_path 'advisory-counts.txt';

	# used everywhere... be lazy, therefore globals
	$db         ||= Database->simple;
	$datestart    = val_date $args->{begin} || "$year-01-01";
	$datestop     = val_date $args->{until} || "$year-12-31";
	$timestart    = "$datestart 00:00:00";
	$timestop     = "$datestop 23:59:59";

	$logger->info("Sending statistics from $datestart to $datestop");

	my $header = <<__HEADER;
-------------------------------
         STATISTICS
-------------------------------
__HEADER

	_advisory_full_list($file);

	my $mail = join "\n", $header,
		_advisories_by_classification(),
		_advisories_by_author(),
		_advisories_by_date(),
		_advisories_by_platform(),
		_sources_per_category(),
		_analyses_done();

	my $msg = Taranis::Mail->build(
		Subject => "Statistics from $datestart to $datestop",
		($to ? (To => $to) : (config_to => 'maillist')),
		config_from => 'mail_from_address',

		plain_text => $mail,
		file       => $file,
	);

	$msg->send;
}

1;
