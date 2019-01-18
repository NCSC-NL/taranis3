#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;

use File::Basename qw(dirname);

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Collector;
use Taranis::Collector::Administration;
use Taranis::Collector::HTMLFeed;
use Taranis::Collector::IMAPMail;
use Taranis::Collector::POP3Mail;
use Taranis::Collector::Twitter;
use Taranis::Collector::XMLFeed;
use Taranis::Sources;
use Taranis::Wordlist;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::Lock;

use Capture::Tiny qw(:all);
use Data::Dumper;
use File::Basename;
use Getopt::Long;
use JSON;
use Thread::Queue;
use Time::localtime;
use URI::Escape;
use List::Util qw(shuffle);
use HTML::Entities qw(decode_entities);

use Term::ReadKey   qw(GetTerminalSize);
use Term::ANSIColor qw(colored);
use Time::HiRes     qw(usleep);
use POSIX			qw(waitpid :sys_wait_h);

sub run_script($);

my @nice_colors     = qw(red green yellow blue magenta cyan white);
my $gridline_sleep  = 0.2;   # seconds
my $source_deadline = 120;   # seconds

# We spawn multiple threads that all print to the same STDOUT. This gets
# messy either way, but with output buffering it gets even more messy, so
# disable output buffering.
$| = 1;

my ($configFile, $debugSource, $useGrid, $help, $noMtbc,
	$numberOfThreads, $shuffle, $verbose);

my $usage = <<"EOL";
Usage:
$0 --debug <name> --nomtbc etc...

--config <path to config file>
--debug <sourcename> (turn on extra debugging output, and only run this source; implies --nomtbc and --threads=1)
--grid (show visual grid display of source collection)
--help (show this help text)
--nomtbc (do not check for MTBC, for testing purposes only!)
--shuffle (process sources in random order, instead of by alphabet)
--threads <number> (set the maximum number of parallel processes; 0 means no forks and process sequentially)
-v --verbose (trace the processing)
EOL

GetOptions(
	"config=s" => \$configFile,
	"debug=s" => sub { $debugSource = pop; $noMtbc = 1; $numberOfThreads = 1; $verbose = 1},
	"grid" => \$useGrid,
	"help" => \$help,
	"nomtbc" => \$noMtbc,
	"threads=s" => \$numberOfThreads,
	"shuffle" => \$shuffle,
	"verbose|v!" => \$verbose,
) or exit 1;

if ( $help ) {
  print  "$usage\n" ;
  exit;
}

sub trace($) { print "$_[0]\n" if $verbose }

if ( @ARGV ) {
	print "Does not compute...\n\n";
	print  "$usage\n";
	exit;
}

if ( $configFile ) {
	if ( ! -e $configFile ) {
		die "Can't find configuration file $configFile\n";
		exit;
	} else {
		trace "Using $configFile";
		$Taranis::Config::mainconfig = $configFile;
	}
}

my $configObj = Taranis::Config->new();
my %config = %$configObj;
my $config = \%config;

$config{collector_secret}
	or die "Collector secret missing in configuration.\n";

$numberOfThreads //= $config{collector_threads};
$numberOfThreads =~ /^\s*\d+\s*$/
	or die "Invalid number of threads: $numberOfThreads\n";

!$useGrid || $numberOfThreads
	or die "Number of threads must be greater than 0 when using --grid.\n";

my $dbhost         = $config{dbhost};
my $collectorAdministration = Taranis::Collector::Administration->new(\%config);

my @collectors = $collectorAdministration->getCollectors(secret => $config{collector_secret} );
my $collectorSettings;
if ( @collectors == 1  && $collectors[0] ) {
	$collectorSettings = $collectors[0];
} elsif ( @collectors > 1 ) {
	die "Too many matching collectors found, please check configuration!\n";
} else {
	die "No matching collector found, please check configuration!\n";
}

### Don't run collector after and before configured hours
if (defined $config{notafter} || defined $config{notbefore}) {
	warn "DEPRECATION WARNING: <notbefore> and <notafter> are deprecated and will be removed in a future version.\n";
	if (
		defined $config{notafter} && localtime->hour() >= $config{notafter}
		or defined $config{notbefore} && localtime->hour() <= $config{notbefore}
	) {
		trace "Running outside configured time window, exit!\n";
		exit;
	}
}

my $collector = Taranis::Collector->new( \%config );

my $start     = 'Begin @ ' . nowstring(7) . " with pid $$";
trace $start;
my $collectorRunId = $collector->setCollectorStarted(collectorId => $collectorSettings->{id}, status => "$start\n");

### Check if a taranis collector process is already running and, if so, kill it!

if(my $other_pid = Taranis::Lock->processIsRunning('collector')) {
	kill 'KILL', $other_pid;

	my $killed = "Previous collector was still running (pid $other_pid). I killed it.";
	trace $killed;
	$collector->setCollectorStatus(
		collectorRunId => $collectorRunId,
		status => "$killed\n",
	);
}

my $lock = Taranis::Lock->lockProcess('collector');

###############################################################################
### 1. COLLECTING NEWS ITEMS FROM IMAP, POP3, HTML, XML AND TWITTER SOURCES ###
###############################################################################

# This global is a dirty work-around to be able to return the status without
# changing too much of the core (full module rewrite in v4)
my $last_collector_status;

sub updateCollectorStatus {
	my ($statusUpdate, $collectorRunId, $collectorObject ) = @_;
	$last_collector_status = nowstring(1). " $statusUpdate";
	$collectorObject->setCollectorStatus(collectorRunId => $collectorRunId, status => "$last_collector_status\n");
}

# collect_source: collect source $source
sub collect_source {
	my ($source) = @_;

	my $source_name = $source->{sourcename};

	# debug output of source
	if ( $debugSource ) {
		trace "DEBUGGING: $source_name\n";
		trace "-------------------------------------------------------------------------";
		trace "processing $source_name $source->{fullurl}";
		local $Data::Dumper::Indent    = 1;
		local $Data::Dumper::Quotekeys = 0;
		local $Data::Dumper::Sortkeys  = 1;
		trace Dumper $source;
	}

	my $plugin;
	if(my $additional = $source->{additional_config}) {
		my $extra = eval { from_json $additional };
		warn "\n\n$@\n\n" if $@;

		if($plugin = $extra->{collector_module}) {
			eval "require $plugin";
			if($@) {
				warn nowstring(1) . " [ERROR] $source_name: Could not find or create collector module $plugin\n";
				return;
			}
		}

		while(my ($key, $val) = each %$extra) {
			$source->{$key} ||= decode_entities $val;
		}
	}

	if ( $source->{protocol} =~ /^(imap|pop3)/i ) {
		### MAIL SOURCES IMAP & POP3 ###
		my $feeder = $source->{protocol} =~ /^pop3s?$/i
			? 'Taranis::Collector::POP3Mail' : 'Taranis::Collector::IMAPMail';

		my $mailFeed  = $feeder->new($configObj, $debugSource);
		my $collector = $mailFeed->{collector};

		updateCollectorStatus("[START] $source_name", $collectorRunId, $collector);

		trace "Coll: process incoming mail source" if $debugSource;

		my $sourceStatus;
		my $mailFeedSTDOUT = capture_stdout {

			if($mailFeed->collect($source, $debugSource)) {
				trace "Coll: done processing mail source" if $debugSource;
				$sourceStatus = 'OK';
				updateCollectorStatus("[DONE] $source_name", $collectorRunId, $collector);
			} else {
				$collector->writeError(
					source     => $source,
					error      => $mailFeed->{errmsg},
					error_code => '010',
				);

				trace "Mail proces error: $mailFeed->{errmsg}" if $debugSource;
				$sourceStatus = 'ERROR';
				updateCollectorStatus("[ERROR] $source_name", $collectorRunId, $collector);
			}

			$mailFeed->{collector}->writeSourceCheck(
				source  => $source->{digest},
				comment => '(' . nowstring(2) . ') ' . $sourceStatus
			);
		};

		updateCollectorStatus($mailFeedSTDOUT, $collectorRunId, $collector)
			if $mailFeedSTDOUT =~ /\S/;
	} else {
		### HTTP SOURCES XML, HTML & CUSTOMIZED ###

		my $feeder = $plugin ||
			( $source->{parser} eq 'xml'
			? 'Taranis::Collector::XMLFeed'
			: 'Taranis::Collector::HTMLFeed'
			);

		my $httpFeed  = $feeder->new($configObj, $debugSource);
		my $collector = $httpFeed->{collector};

		updateCollectorStatus("[START] $source_name", $collectorRunId, $collector);

		my $sourceData = ($httpFeed->can('getSourceData') ? $httpFeed : $collector)
			->getSourceData(undef, $source, $debugSource);

		unless($sourceData) {
			updateCollectorStatus("[ERROR] $source_name: Error, no data", $collectorRunId, $collector);

			$collector->writeSourceCheck(
				source  => $source->{digest},
				comment => '(' . nowstring(2) . ') ERROR'
			);
			return;
		}

		$collector->writeSourceCheck(
			source  => $source->{digest},
			comment => '(' . nowstring(2) . ') OK'
		);

		my $raw_feed = $httpFeed->collect($sourceData, $source, $debugSource);
		unless($raw_feed) {
			updateCollectorStatus("[ERROR] $source_name: no items found, writing error 099", $collectorRunId, $collector);

			$collector->writeError(
				source     => $source,
				error      => $httpFeed->{errmsg},
				error_code => 204,
				content    => $sourceData,
			);
			return;
		}

		# It rarely happens that the same item is repeated.  Remove doubles
		my %feed;
		my @feed = grep !$feed{$_->{itemDigest}}++, @$raw_feed;

		updateCollectorStatus("[DONE] $source_name: " .@feed. " new items", $collectorRunId, $collector);

		my $collect_certids = $source->{checkid};
		trace "Check CVE ID in feed_links: ".($collect_certids ? 'YES' : 'NO') if $debugSource;

	ITEM:
		foreach my $item (@feed) {

			next ITEM
				if $collector->{no_db};

			my $screenshotDetails = $source->{take_screenshot}
			  ? $collector->processScreenshot($item, $source, $debugSource)
			  : { oid => undef, fileSize => undef };

			my $keywords = $item->{matching_keywords} || [];
			my $keywords_json = @$keywords ? to_json($keywords) : undef;

			my $digest   = $item->{itemDigest};
			my $enc_link = sanatizeLink($item->{link});
			my $link     = uri_unescape $enc_link;

			my %insert   = (
				digest      => $digest,
				title       => $item->{title},
				description => $item->{description},
				status      => $item->{status},
				link        => $enc_link,
				source_id   => $source->{id},
				source      => $source_name,
				category    => $source->{categoryid},
				screenshot_object_id => $screenshotDetails->{oid},
				screenshot_file_size => $screenshotDetails->{fileSize},
				matching_keywords_json => $keywords_json,
			);

			my ($stmnt, @bind) = $collector->{sql}->insert(item => \%insert);
			$stmnt .= ' ON CONFLICT DO NOTHING';   # issue 260

			$collector->{dbh}->prepare( $stmnt );
			$collector->{dbh}->executeWithBinds(@bind);

			$collect_certids
				or next ITEM;

			# CHECK XML AND HTML CONTENT FOR IDENTIFIERS (LIKE CVE)

			trace "CheckId, getting SourceData $enc_link" if $debugSource;
			trace "unescaped feed link: $link" if $debugSource;

			my $follow_link   = $collector->getSourceData($link);
			my $stripped_page = $collector->stripsData($follow_link, $configFile);
			my @certids       = $collector->parseIdentifierPatterns($stripped_page, $configFile);

			foreach my $identifier (@certids) {
				$collector->writeCVE(identifier => $identifier, digest => $digest)
					and next;

				$collector->writeError(
					source     => $source,
					error      => "Identifier Parse Error: $collector->{cve_error}",
					error_code => '014',
					content    => $follow_link,
				);
			}
		}

		undef $collector->{cve_error};
	}

	$last_collector_status;
}

sub collect_sources_seq($) {
	my ($sources) = @_;

	# Don't use threads, just run the sources one after the other. Keep order
	my $checker = Taranis::Collector->new($config, $debugSource);

	foreach my $source (@$sources) {
		if($noMtbc || $checker->sourceMtbcPassed($source, $debugSource)) {
			my $status = collect_source($source);
			trace $status;
		} else {
			trace "It's not time to check $source->{host}" if $debugSource;
		}
	}
}

sub collect_sources_forked($$) {
	my ($sources, $max_procs) = @_;

	my @sources;
	if($noMtbc) {
		# time limitation on source overruled
		@sources = @$sources;
	} else {
		# strip unneeded sources immediately
		my $checker = Taranis::Collector->new($config, $debugSource);
		@sources = grep $checker->sourceMtbcPassed($_, $debugSource),
			@$sources;
	}

	my $line_width = (-t STDOUT ? (GetTerminalSize)[0] : undef) || 80;
	my $col_width  = int($line_width/$max_procs -1 +0.01);

	# Could be implemented much easier without the grid display.  Now, we
	# have to maintain position based @proc slots

	my @procs;   # each element administers one forked process in a HASH

	while(@sources || grep defined, @procs) {
		my @show_cols;
		my $now = time;

		foreach(my $colnr = 0; $colnr < $max_procs; $colnr++) {
			my $text;

			if(my $proc = $procs[$colnr]) {
				### check active process

				my $pid = $proc->{pid};
				if(waitpid($pid, WNOHANG)) {  # process completed
					$text = "$pid " . (
					    WIFEXITED($?)   ? "done, rc=".WEXITSTATUS($?)
					  : WIFSIGNALED($?) ? "failed, sig=".WTERMSIG($?)
					  :                   "failed, wait=$?");

					trace "$proc->{source}{sourcename} $text\n"
						unless $useGrid && $text =~ /failed/;
					undef $procs[$colnr];

				} elsif($now >= $proc->{deadline}) {
					kill TERM => $pid;    # will show TERM on next grid line
					$text = "$pid timeout after ${source_deadline}s";
				} else {
					$text = '-';          # task still working
				}

			} elsif(@sources) {
				### fill an empty slot with the next @source

				my $source = shift @sources;
				my $pid    = fork();
				unless($pid) {
					### Child process to process the source.
					# child must not close parents database connection
					Database->{dbh}->{InactiveDestroy} = 1;

					# for DBD::Pg, the database connections cannot be shared
					Database->connect;

					my $status = collect_source($source);

					# there is no clean exception mechanism
					exit $status =~ /\[ERROR\]/ ? 1 : 0;
				}

				$procs[$colnr] = {
					pid      => $pid,
					deadline => time + $source_deadline,
					source   => $source,
				};
				$text = "$pid $source->{sourcename}";

			} else {
				### Waiting for the last tasks to finish.
				$text = 'free';
			}

			# Fit $text in grid
			my $cell  = substr $text, 0, $col_width;
			$cell    .= ' ' while length($cell) < $col_width;
			my $color = $nice_colors[$colnr % @nice_colors];
			push @show_cols, colored($cell, $color);
		}

		local $" = ' ';
		print "@show_cols\n" if $useGrid;
		usleep $gridline_sleep * 1_000_000;
	}
}

{
	$collector->setCollectorStatus( collectorRunId => $collectorRunId,
		status => "### COLLECTING NEWS ITEMS\n" );

	# get all sources
	my $oTaranisSources = Taranis::Sources->new( \%config );
	my $sources = $debugSource
		? $oTaranisSources->getSources( enabled => 1, sourcename => $debugSource, collector_id => $collectorSettings->{id} )
		: $oTaranisSources->getSources( enabled => 1, collector_id => $collectorSettings->{id} );
	$sources = [ shuffle @$sources ] if $shuffle;

	# get all wordlists
	my $oTaranisWordlist = Taranis::Wordlist->new( \%config );
	my $wordlists = $oTaranisWordlist->getWordlist || [];

	my %patterns;
	foreach my $wordlist (@$wordlists) {
		my $words = $wordlist->{words} || [];
		my @words = map decode_entities($_), @$words;

		local $"  = '|';
		$patterns{$wordlist->{id}} = qr/(@words)/i;
	}

	# get wordlists per source
	foreach my $source (@$sources) {
		$source->{use_keyword_matching} or next;

		my $lists = $oTaranisSources->getSourceWordlist(source_id => $source->{id});
		my @sets;
		foreach my $list (@$lists) {
			push @sets, {
				match     => $patterns{$list->{wordlist_id}},
				and_match => $patterns{$list->{and_wordlist_id}},
			};
		}
		$source->{wordlists} = \@sets;
	}

	if ($numberOfThreads == 0) {
		collect_sources_seq($sources);
	} else {
		collect_sources_forked($sources, $numberOfThreads);
	}

	trace "--------------------------------------------------------------------------";
}

######################################################################
### 							5. FINALIZE AND CLEAN UP		   ###
######################################################################
trace "### FINALIZING AND CLEAN UP ###";

$lock->unlock;

if (!$collector->setCollectorFinished( collectorRunId => $collectorRunId ) ) {
	warn "\n$collector->{errmsg}\n";
}

trace "--END-- @ " . nowstring(7) . "\n";

exit 0;
