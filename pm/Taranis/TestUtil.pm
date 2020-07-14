# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::TestUtil;

## Taranis::TestUtil: various utilities for the tests in t/.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Test::PostgreSQL;
use File::Basename;
use CGI::Simple;
use JSON;
use Test::Builder qw();
use Test::Most;
use Text::Diff;
use Data::Dumper;

use Taranis qw(fileToString nowstring);
use Taranis::Config;
use Taranis::Database qw(withRollback);
use Taranis::Session qw(spawnSession sessionIsActive sessionCsrfToken sessionGet sessionSet);
use Taranis::FunctionalWrapper qw(CGI Config Database);

use constant {
	ADVISORY_NORMAL => 1,
	ADVISORY_FORWARD => 2,
};

use constant ADVISORY_TYPES => {
	&ADVISORY_NORMAL => {
		table => 'publication_advisory',
		action_create => '/load/write/advisory/saveNewAdvisory',
		action_update => '/load/write/advisory/saveUpdateAdvisory',
		action_publish => '/load/publish/publish_advisory/publishAdvisory',
		# Giving the advisory its number ("finalizing" it) happens in openDialogPublishAdvisory.
		action_finalize => '/load/publish/publish_advisory/openDialogPublishAdvisory',
	},
	&ADVISORY_FORWARD => {
		table => 'publication_advisory_forward',
		action_create => '/load/write/forward/saveNewForward',
		action_update => '/load/write/forward/saveUpdateForward',
		action_publish => '/load/publish/publish_forward/publishForward',
		# Giving the advisory its number ("finalizing" it) happens in openDialogPublishForward.
		action_finalize => '/load/publish/publish_forward/openDialogPublishForward',
	},
};


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	cmp_deeply_or_diff subtestWithRollback withFakeTime withDistConfig
	doJsonRequest withAdminSession
	withEphemeralDatabase psql tableIds lastTableId
	requireFixture %fixtures
	createAdvisory publishAdvisory
	ADVISORY_NORMAL ADVISORY_FORWARD
);


our %fixtures;
our %active_fixtures;

# Like Test::Deep::cmp_deeply, but show diff if no match.
sub cmp_deeply_or_diff ($$;$) {
	my ($got, $expected, $name) = @_;

	local $Test::Builder::Level = $Test::Builder::Level + 1;

	unless (cmp_deeply($got, $expected, $name)) {
		my ($gotDumped, $expectedDumped) = map
			[ split /^/, Data::Dumper->new([$_])->Indent(1)->Terse(1)->Deepcopy(1)->Quotekeys(0)->Sortkeys(1)->Dump ],
			($got, $expected);
		explain(
			diff($gotDumped, $expectedDumped, {
				CONTEXT =>    2**31,
				STYLE   =>    'Table',
				FILENAME_A => 'Got',
				FILENAME_B => 'Expected',
			})
		);
	}
}


# Like Test::More::subtest, but wrapped in &withRollback.
sub subtestWithRollback {
	my @args = @_;

	local $Test::Builder::Level = $Test::Builder::Level + 3;

	return withRollback {
		Test::Builder->new->subtest(@args);
	};
}


# Fake a POST request to $path (e.g. '/load/session/logout/logoutUser'), by temporarily faking the right environment
# and running scripts/index.pl. Captures, JSON-decodes and returns the response string (excluding headers).
# $request_params_ref should be a hashref with POST parameters. The parameter values are expected to be strings
# (usually JSON-encoded data).
sub doJsonRequest {
	my ($path, $request_params_ref) = @_;
	my $output;

	spawnSession unless sessionIsActive;

	local $ENV{REQUEST_METHOD} = 'POST';
	local $ENV{REQUEST_URI} = Config->{scriptroot} . $path;
	local $ENV{HTTP_X_TARANIS_CSRF_TOKEN} = sessionCsrfToken;

	# Store original request parameters so we can restore them later.
	my %org_params = CGI->Vars;

	# Register the POST parameters for our fake request.
	CGI->delete_all;
	CGI->param(-name => $_, -value => $request_params_ref->{$_}) for keys %$request_params_ref;

	# Run the requested script. Do this inside a separate package, so that un-namespaced subroutines, variables etc
	# defined by the requested script won't polluate the Taranis::TestUtil namespace (but the
	# Taranis::TestUtil::ScratchPad namespace instead).
	{
		package Taranis::TestUtil::ScratchPad;
		use File::Basename;

		open(local *STDOUT, '>', \$output) or die $!;
		do(dirname(__FILE__) . "/../../scripts/index.pl") // die ($@ || $! || "mystery failure running index.pl");
	}

	# Restore request parameters to their original state.
	CGI->delete_all;
	CGI->param(-name => $_, -value => $org_params{$_}) for keys %org_params;

	my ($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	if ($headers !~ m{\bcontent-type: application/json\b}i) {
		croak "doJsonRequest: JSON content type not found in response.\n" .
			"Request was to $path with these POST parameters:\n" .
			join("\n", map {$_ . " => " . $request_params_ref->{$_}} keys(%$request_params_ref)) . "\n" .
			"Response:\n$output\n";
		return undef;
	}

	return from_json($body);
}


# Run code with a clean database, rollback afterwards. Allows tests to play around without worrying about touching the
# actual live database.
#
# If $ENV{TARANIS_TEST_DB} is set, it is expected to contain a "DSN" string ("DBI:Pg:etc..") pointing to a clean
# database on which (only) rss-schema.sql and Taranis_initiele_inserts.sql have been run.
# If $ENV{TARANIS_TEST_DB} is not set, Test::PostgreSQL is used to create (and destroy) a temporary database. This is
# slower (since it runs `initdb` and everything) than using TARANIS_TEST_DB, but requires no setup.
#
# withEphemeralDatabase {
#   do things involving database;
#   ...;
# };
our $ephemeralDatabase;
sub withEphemeralDatabase (&) {
	my ($coderef) = @_;

	my ($error, $coderef_return, $clientPids);
	local $ephemeralDatabase;

	unless ($ENV{TARANIS_TEST_DB}) {
		$ephemeralDatabase = Test::PostgreSQL->new or die "Failed to create ephemeral database: " . ($@ || $!);
	}

	# Locally replace the Database singleton by a fresh one that uses our ephemeral db.
	local $Taranis::FunctionalWrapper::singletons{'Database'} = undef;
	local @Taranis::Database::dsn_override = ($ENV{TARANIS_TEST_DB} || $ephemeralDatabase->dsn, '', '');
	local %active_fixtures = ();

	Database->connect;

	withRollback {
		if ($ephemeralDatabase) {
			my $db_load = dirname(__FILE__) . '/../../install/db-load';
			Database->do('create extension lo');
			Database->do(fileToString("$db_load/taranis-schema.sql"));
			Database->do(fileToString("$db_load/initial_inserts.sql"));
		}

		# Run the supplied code block.
		$coderef_return = eval {
			$coderef->();
		};
		$error = $@;
	};

	$clientPids = Database->simple->query("select pid from pg_stat_activity")->flat
		if $ephemeralDatabase;

	# Before disconnecting, make sure Taranis::Database doesn't have an active sth remaining (e.g. a
	# not-fully-fetched query result). Some Taranis modules cause this to happen, and DBI understandably doesn't
	# want to disconnect while there's still active sth's around.
	Database->{sth}->finish if Database->{sth} && Database->{sth}->{Active};

	Database->disconnect;

	if ($ephemeralDatabase) {
		# Make sure no one's connected to the database (sledgehammer style), so it can quit cleanly.
		kill 15, @$clientPids;

		# Tear down database.
		$ephemeralDatabase->stop;
	}

	# Propagate the supplied code block's exceptions and return value.
	die $error if $error;
	return $coderef_return;
}

# Spawn psql to allow the user to inspect the ephemeral database.
sub psql {
	my $port = $ephemeralDatabase->port;
	say "Database created, running on port $port. Do your thing, I'll clean up when you quit psql.";
	system("psql -p$port -h0 -Upostgres test");
}


sub tableIds ($) {
	my ($table) = @_;
	Database->simple->select($table, 'id', {}, 'id')->flat;
}


sub lastTableId ($) {
	[ tableIds(shift) ]->[-1] // 0;
}


# Run some code with a simulated time of day.
# Argument $time should be something Fake::Time accepts, see the Fake::Time docs.
# Note: this requires that in the test script, Fake::Time is imported (with `use`) *before* any other modules, i.e.
# before perl compiles any code that uses &time and friends. See the Fake::Time docs for background.
sub withFakeTime ($$) {
	my ($time, $coderef) = @_;

	local $Test::Builder::Level = $Test::Builder::Level + 3;

	Time::Fake->offset($time);

	my $coderef_return = eval {
		$coderef->();
	};
	my $error = $@;

	Time::Fake->reset;

	# Propagate the supplied code block's exceptions and return value.
	die $error if $error;
	return $coderef_return;
}


# Run some code with a fake admin session.
# withAdminSession {
#   doFakeRequest(...);
# };
sub withAdminSession (&) {
	my ($coderef) = @_;

	spawnSession unless sessionIsActive;
	my $orgUserid = sessionGet 'userid';
	sessionSet 'userid' => 'admin';

	my $coderef_return = eval {
		$coderef->()
	};
	my $error = $@;

	sessionSet 'userid' => $orgUserid;

	# Propagate the supplied code block's exceptions and return value.
	die $error if $error;
	return $coderef_return;
}


# Run some code with taranis.conf.xml-dist instead of conf/taranis.conf.xml.
sub withDistConfig (&) {
	my ($coderef) = @_;

	# Locally replace the Config singleton by a fresh one that uses our test config.
	local $Taranis::FunctionalWrapper::singletons{'Config'} = undef;
	local $Taranis::Config::mainconfig = dirname(__FILE__) . '/../../conf/taranis.conf.xml-dist';

	my $coderef_return = eval {
		$coderef->();
	};
	my $error = $@;

	# Propagate the supplied code block's exceptions and return value.
	die $error if $error;
	return $coderef_return;
}


# Some arbitrary advisory settings that don't matter for our tests, just to be a bit more realistic.
sub _boring_advisory_settings {
	return (
		cve_id => "",
		probability => "2",
		pro_standard => "1", pro_exploit => "1", pro_details => "3", pro_access => "6",
		pro_credent => "4", pro_complexity => "1", pro_userint => "1", pro_exploited => "1",
		pro_expect => "1", pro_solution => "1", pro_deviation => "",
		damage => "2",
		dmg_dos => "0", dmg_codeexec => "0", dmg_remrights => "1",
		dmg_privesc => "0", dmg_infoleak => "0", dmg_deviation => "",
		platforms_txt => "",
		products_txt => "",
		versions_txt => "",
		tab_summary_txt => "", tab_consequences_txt => "", tab_description_txt => "",
		tab_solution_txt => "", tab_tlpamber_txt => "",
		additional_links => "",
	);
}


# Create an advisory from an analysis.
# For example: createAdvisory(ADVISORY_NORMAL, "20150002", "some advisory title", "1.00", "optional hyperlink(s)")
sub createAdvisory {
	my ($type, $analysis_id, $advisory_title, $advisory_version, $other_settings_ref) = @_;
	$other_settings_ref //= {};

	return doJsonRequest(ADVISORY_TYPES->{$type}{action_create}, {params => to_json {
		_boring_advisory_settings(),
		analysisId => $analysis_id,
		advisory_version => $advisory_version,
		title => $advisory_title,
		advisory_links => "https://www.ncsc.nl/test",
		pub_id => "",
		adv_id => "",
		%$other_settings_ref,
	}})->{page}->{params}->{publicationId};
}


# Update an advisory based on a new analysis.
# For example: _updateAdvisory(ADVISORY_NORMAL, "20150003", "updated advisory title", "1.01", 123, "FOO-20XX-0002")
sub _updateAdvisory {
	my ($type, $analysis_id, $advisory_title, $advisory_version, $publication_id, $advisory_id) = @_;

	return doJsonRequest(ADVISORY_TYPES->{$type}{action_update}, {params => to_json {
		_boring_advisory_settings(),
		analysisId => $analysis_id,
		advisory_version => $advisory_version,
		title => $advisory_title,
		advisory_links => "https://www.ncsc.nl/test",
		pub_id => $publication_id,
		adv_id =>
			scalar Database->simple->select(ADVISORY_TYPES->{$type}{table}, 'id', {govcertid => $advisory_id})->flat,
		advisory_id => $advisory_id,
	}})->{page}->{params}->{publicationId};
}


# Give a new advisory its final number (FOO-2025-XXXX => FOO-2025-0002). Return the number.
sub _finalizeNewAdvisory {
	my ($type, $publication_id) = @_;

	return doJsonRequest(ADVISORY_TYPES->{$type}{action_finalize}, {params => to_json {
		id => $publication_id,
	}})->{page}->{params}->{advisoryId};
}


# Publish advisory to constituents. Return advisory id.
sub publishAdvisory {
	my ($type, $publication_id) = @_;

	# Finalize advisory (give it a number) first if it doesn't have a number yet.
	my $analysis_id = Database->simple->select(
		ADVISORY_TYPES->{$type}{table}, 'govcertid', {publication_id => $publication_id}
	)->list;
	$analysis_id = _finalizeNewAdvisory($type, $publication_id) if $analysis_id =~ /X$/;

	doJsonRequest ADVISORY_TYPES->{$type}{action_publish}, {params => to_json {
		id => $publication_id,
		# Body text of the advisory.
		advisory_preview => scalar Database->simple->select(
			'publication',
			['contents'],
			{id => $publication_id}
		)->list,
		# Constituent groups that should receive the advisory. Must be supplied, but our action_publish doesn't
		# actually check if they exist, so just provide a nonsense group id.
		groups => [-1],
	}};

	return $analysis_id;
}


# Run fixture, if it hasn't already been run. Return whether we ran it (true/false).
sub requireFixture {
	my ($fixture_name) = @_;

	croak "cowardly refusing to run fixtures on live database" unless @Taranis::Database::dsn_override;

	if ($active_fixtures{$fixture_name}) {
		# Has already been run.
		return 0;
	} else {
		# Hasn't been run yet. Run and mark as active.
		croak "$fixture_name? You're just making stuff up now, aren't you?"
			unless $fixtures{$fixture_name};
		$fixtures{$fixture_name}->();
		$active_fixtures{$fixture_name} = 1;
		return 1;
	}
}


# Bunch of available database testing fixtures.
%fixtures = (
	software_hardware => sub {
		# Insert some software_hardware rows.
		Database->do(fileToString(dirname(__FILE__) . "/../../t/data/software_hardware_sample.sql"));
	},

	collector => sub {
		Database->simple->insert('collector', {
			description => 'testcollector',
			ip => '::1',
			secret => 'testcollector secret',
		});
	},

	source => sub {
		requireFixture 'collector';

		# Create a source.
		Database->simple->insert('sources', {
			category => 1,
			digest => 'testsource digest',
			fullurl => 'https://www.ncsc.nl/test',
			host => 'www.ncsc.nl',
			mtbc => 999,
			parser => 'xml',
			protocol => 'https://',
			port => 443,
			sourcename => 'testsource',
			url => '/test',
			checkid => 1,
			language => 'en',
			collector_id => lastTableId 'collector',
			rating => 50,
		});
	},

	item => sub {
		requireFixture 'source';

		Database->simple->insert('item', {
			digest => 'testitem digest',
			category => 1,
			source => 'testsource',
			title => 'testitem title',
			'link' => 'https://www.ncsc.nl/test',
			description => 'testitem description',
			status => 1,  # Status 'read'.
			source_id => lastTableId 'sources',
		});
	},

	analysis => sub {
		my $year = nowstring(6);

		withAdminSession {
			# Create 3 analyses, which should get numbers <year>0001 through <year>0003.
			my @analysis_ids = map {
				doJsonRequest('/load/analyze/assess2analyze/createAssessAnalysis', {params => to_json {
					digest => 'testitem digest',
					title => "testanalysis title $_",
					description => "testanalysis description $_",
					status => 'pending',
					rating => 1,
				}})->{page}->{params}->{analysisId}
			} 1 .. 3;
			die "unexpected analysis ids" if grep !/^${year}000[123]$/, @analysis_ids;
		};
	},

	advisory => sub {
		requireFixture 'analysis';

		my $year = nowstring(6);

		withAdminSession {
			# Create a few advisories, with some variety:
			# - FOO-20XX-0001 from the first analysis...
			publishAdvisory(ADVISORY_NORMAL, createAdvisory(ADVISORY_NORMAL, "${year}0001", "advisory 1", "1.00"));
			# - FOO-20XX-0002 from the second analysis, with 2 updates, v1.01 and v1.02...
			my $publication_id_v100 = createAdvisory(ADVISORY_NORMAL, "${year}0002", "advisory 2", "1.00");
			my $advisory_id = publishAdvisory(ADVISORY_NORMAL, $publication_id_v100);
			my $publication_id_v101 = _updateAdvisory(
				ADVISORY_NORMAL, "${year}0002", "advisory 2.1", "1.01", $publication_id_v100, $advisory_id
			);
			publishAdvisory(ADVISORY_NORMAL, $publication_id_v101);
			my $publication_id_v102 = _updateAdvisory(
				ADVISORY_NORMAL, "${year}0002", "advisory 2.2", "1.02", $publication_id_v101, $advisory_id
			);
			publishAdvisory(ADVISORY_NORMAL, $publication_id_v102);
			# - and FOO-20XX-0003 also from the second analysis, with a differing hyperlink.
			publishAdvisory(ADVISORY_NORMAL, createAdvisory(ADVISORY_NORMAL, "${year}0002", "advisory 3", "1.00", {
				advisory_links => "https://www.ncsc.nl/advisory-3-link"
			}));
		};
	},

	advisory_forward => sub {
		requireFixture 'analysis';

		my $year = nowstring(6);

		withAdminSession {
			# Create a few advisories, with some variety:
			# - FOO-20XX-0001 from the first analysis...
			publishAdvisory(ADVISORY_FORWARD, createAdvisory(ADVISORY_FORWARD, "${year}0001", "advisory 1", "1.00"));
			# - FOO-20XX-0002 from the second analysis, with 2 updates, v1.01 and v1.02...
			my $publication_id_v100 = createAdvisory(ADVISORY_FORWARD, "${year}0002", "advisory 2", "1.00");
			my $advisory_id = publishAdvisory(ADVISORY_FORWARD, $publication_id_v100);
			my $publication_id_v101 = _updateAdvisory(
				ADVISORY_FORWARD, "${year}0002", "advisory 2.1", "1.01", $publication_id_v100, $advisory_id
			);
			publishAdvisory(ADVISORY_FORWARD, $publication_id_v101);
			my $publication_id_v102 = _updateAdvisory(
				ADVISORY_FORWARD, "${year}0002", "advisory 2.2", "1.02", $publication_id_v101, $advisory_id
			);
			publishAdvisory(ADVISORY_FORWARD, $publication_id_v102);
			# - and FOO-20XX-0003 also from the second analysis, with a differing hyperlink.
			publishAdvisory(ADVISORY_FORWARD, createAdvisory(ADVISORY_FORWARD, "${year}0002", "advisory 3", "1.00", {
				advisory_links => "https://www.ncsc.nl/advisory-3-link"
			}));
		};
	},

	# Various uninteresting, but required, types and roles that should probably just be included in the database by
	# default.
	types_and_roles => sub {
		Database->simple->insert(
			-into => 'constituent_type',
			-values => {
				id => 1,
				type_description => 'whatever',
			},
		);

		Database->simple->insert(
			-into => 'constituent_role',
			-values => {
				role_name => $_,
			},
			-returning => 'id',
		) for qw/DSC somerole/;
	},
);


1;
