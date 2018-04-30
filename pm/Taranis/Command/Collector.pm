# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Collector;

use warnings;
use strict;

use Carp qw(confess);
use XML::FeedPP;
use HTML::Entities qw(decode_entities);
use Date::Parse qw(str2time);

use Taranis::Install::Config   qw(config_generic config_release
	taranis_sources);
use Taranis qw(:all);
use Taranis::Collector;
use Taranis::Config;
use Taranis::Database;
use Taranis::Log       ();
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Collector::Statistics;
use Taranis::Collector::Administration;
use Taranis::Mail ();

my %handlers = (
	'download-stats' => \&collector_download_stats,
	'make-stats'     => \&collector_make_stats,
	'send-digests'   => \&collector_send_digests,
	'scan-sources'   => \&collector_scan_sources,
	'alerter'        => \&collector_alerter,
);

Taranis::Commands->plugin(collector => {
	handler       => \&collector_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'debug=s',
		'grid!',
		'clustering!',
		'mtbc!',
		'stats!',
		'shuffle!',
		'threads=i',
		'log|l=s',
		'verbose|v!',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  alerter [-l]        alert maintainers for failing collectors
  download-stats      download malware statistics from external sources
  make-stats [-l]     create collector statistics images
  scan-sources [...]  scan all configured sources for changes
  send-digests [-l]   mail feed digests

GENERIC OPTIONS:
  -l --log FILENAME   alternative log destination ('-' means stdout)

SCAN-SOURCES OPTIONS:
  --debug <source>    only process source, with debug info
  --grid              show visual grid display of source collection
  --no-clustering     do not start clustering script
  --no-mtbc           do not check for MTBC, for testing purposes only!
  --shuffle           process sources in random order, instead of by alphabet
  --threads <number>  the max number of parallel processes; 0=sequential
  -v --verbose        trace the scanning
__HELP
} );

sub collector_control(%) {
    my %args = @_;

    my $subcmd = $args{sub_command}
        or confess;

    my $handler = $handlers{$subcmd}
        or confess $subcmd;

    $handler->(\%args);
}

# was collector/collect.pl, now calls bin/collect.pl
#XXX Still to be rewritten into a module

sub collector_scan_sources($) {
	my $args = shift;

	my @runopts;
	push @runopts, '--debug', $args->{debug}
		if defined $args->{debug};

	push @runopts, map "--$_", grep $args->{$_},
			qw/grid shuffle/;

	push @runopts, map "--no$_",
		grep defined $args->{$_} && !$args->{$_},
			qw/clustering mtbc stats/;

	push @runopts, '--threads', $args->{threads}
		if defined $args->{threads};

	push @runopts, '--verbose'
		if $args->{verbose};

	my @cmd  = ('collector.pl' => @runopts);
	system @cmd
		and die "ERROR: @cmd: $!/$?\n";
}

# was backend_tools/feeddigest_mailings.pl

sub collector_send_digests($) {
	my $args   = shift;
	my $logger = Taranis::Log->new('send-feeddigest', $args->{log});

	my $collector = Taranis::Collector->new( Config );
	$collector->{no_db} = 1;  # do not log errors there

	my $db     = Database->{simple};

	my @feeds  = $db->query(<<'__GET_FEED_DIGESTS')->hashes;
 SELECT * FROM feeddigest
  WHERE ((   to_char(NOW(), 'YYYY') > to_char(last_sent_timestamp, 'YYYY')
	      OR to_char(NOW(), 'MM')   > to_char(last_sent_timestamp, 'MM')
	      OR to_char(NOW(), 'DD')   > to_char(last_sent_timestamp, 'DD')
         ) AND to_char(NOW(), 'HH24')::int >= sending_hour
        )
     OR last_sent_timestamp IS NULL
  ORDER BY sending_hour
__GET_FEED_DIGESTS

	$logger->info("got ".@feeds." feeds to process");

  FEED:
	foreach my $feedSettings (@feeds) {
		my $url = $feedSettings->{url};

		my $content = $collector->getSourceData($url);
		unless($content) {
			$logger->warning("$url: $collector->{http_status_line}");
			next FEED;
		}

		my $feed    = eval { XML::FeedPP->new( $content, ignore_error => 1 ) };
		if($@) {
			(my $error = $@) =~ s!\bat /.*!!;
			$logger->warning("XML parsing error: $error");
			next FEED;
		}

		my @feedItems = $feed->get_item;
		unless(@feedItems) {
			$logger->info("no items found in XML feed $url");
			next FEED;

			#XXX In the processing of @feedItems, we check for pubDate.  We may
			#XXX end-up with an empty report later.  Should that filter move here?
		}

		### Construct message

		# apply header template
		my $mailContent  = decode_entities( $feedSettings->{template_header} );
		foreach my $find (qw(title description pubDate copyright link language)) {
			my $replace  = $feed->$find() || '';
			$replace     = $collector->prepareTextForSaving($replace) if $replace;
			$mailContent =~ s/__${find}__/$replace/gi;
		}

		my $itemCount = 0;

		# apply feed items template
  	ITEM:
		foreach my $item ( @feedItems ) {
			my $pubTime = str2time($item->pubDate);
			!$pubTime || $pubTime > time - 86400
				or next ITEM;

			$mailContent .= decode_entities( $feedSettings->{template_feed_item} );
			foreach my $find (qw(title description pubDate link category author)) {
				my $replace  = $item->$find() || '';
				$replace     = "@$replace" if ref $replace eq 'ARRAY';
				$replace     = $collector->prepareTextForSaving($replace) if $replace;
				$mailContent =~ s/__${find}__/$replace/gi;
			}
			$itemCount++;
		}

		# apply footer template
		$mailContent .= decode_entities( $feedSettings->{template_footer} );
		foreach my $find (qw(title description pubDate copyright link language)) {
			my $replace  = $feed->$find() || '';
			$replace     = $collector->prepareTextForSaving($replace) if $replace;
			$mailContent =~ s/__${find}__/$replace/gi;
		}

		$mailContent     =~ s/__itemcount__/$itemCount/gi;
		$mailContent     = 'No new items...' if !$itemCount;

		# remove HTML
		my $mailContentHTML = $mailContent;
		$mailContent     =~ s/<.*?>//g;

		my $send_to      = $feedSettings->{to_address};
		my $msg          = Taranis::Mail->build(
			config_from  => 'mail_from_address',
			To           => $send_to,
			Subject      => "[Taranis] Digest for $url " . nowstring(5),
			plain_text   => $mailContent,
			html_text    =>	($feedSettings->{strip_html} ? undef : $mailContentHTML),
		);
		$msg->send;

		$logger->info("$url: digest send to $send_to");

		$collector->{dbh}->setObject( 'feeddigest',
			 { id => $feedSettings->{id} }, { last_sent_timestamp => \'NOW()' } );
	}
}

#XXX Traditionally, the downloading is connected to the connector, but there
#XXX is no good reason to keep it that way.

sub collector_download_stats($) {
	my $args   = shift;

	my $logger = Taranis::Log->new('download-stats', $args->{log});
	$::db      = Database->{simple};    # T4 style

	my $config       = Taranis::Config->new;
	my $stats_config = $config->{statsconfig};

	Taranis::Collector::Statistics->new
		->downloadStats($stats_config, $logger);
}

sub collector_make_stats($) {
	my $args   = shift;

	my $logger = Taranis::Log->new('generate-stats', $args->{log});
	$::db      = Database->{simple};    # T4 style

	Taranis::Collector::Statistics->new
		->createGraphs($logger);
}


# was collector/alerter.pl

sub mail_it($$$$);

sub collector_alerter($) {
	my $args       = shift;

	#my @collectors = $::taranis->collectors->getCollectors;  # T4
	$::db          = Database->{simple};    # T4 style

	my $logger     = Taranis::Log->new('collector-alerter', $args->{log});

	my $mainconfig = Taranis::Config->new;
	my $col_admin  = Taranis::Collector::Administration->new($mainconfig);
	my @collectors = $col_admin->getCollectors;

	foreach my $collector (@collectors) {

		my @last_runs = $::db->query( <<_STATS, $collector->{id} )->hashes;
  SELECT *
    FROM statistics_collector
   WHERE collector_id = ?
   ORDER BY started DESC
   LIMIT 4
_STATS

		my @failed_runs = grep ! $_->{finished}, @last_runs;

		# Only warn at the second failure.
		next if @failed_runs < 2;

		mail_it($collector, \@failed_runs, $logger, $mainconfig);
	}
}

sub mail_it($$$$) {
	my ($collector, $failed, $logger, $config) = @_;

	my $send_to  = $config->{collector_alerter_to_address};

	my $coldescr = $collector->{description};
	my $subject  = decode_entities
		"[Taranis] collector '$coldescr' FAILED a couple of times!";

	my $message  = decode_entities(<<_MESSAGE);
If this happens too often, something is probably wrong!
Collector '$coldescr' did not finish several times.

If runs keep on failing, please contact your system administrator.

Collector output:

_MESSAGE
	
	foreach my $failed (@$failed) {
		$message .= decode_entities("$failed->{status}\n\n");
	}

	my $msg = Taranis::Mail->build(
		To          => $send_to,
		Subject     => $subject,
		plain_text  => $message,
	);
	$logger->info("failure of collector was sent to $send_to");
}

1;
