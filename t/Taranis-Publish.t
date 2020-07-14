#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Test::Most;

use Taranis qw(nowstring);
use Taranis::Config;
use Taranis::Database;
use Taranis::Publish;
use Taranis::FunctionalWrapper qw(Config Database Publish);
use Taranis::TestUtil qw(
	cmp_deeply_or_diff requireFixture withAdminSession withEphemeralDatabase withDistConfig ADVISORY_NORMAL
);


withDistConfig {
	local Config->{advisory_prefix} = "TEST";
	local Config->{advisory_id_length} = 4;

	my $year = nowstring(6);


	# Test getUnpublishedCount.
	withEphemeralDatabase {
		# Create a few advisories.
		requireFixture 'advisory';

		cmp_deeply_or_diff
			Publish->getUnpublishedCount(),
			[],
			"getUnpublishedCount - no approved advisories";

		# Set advisories' status to "approved".
		Database->simple->update('publication', {status => 2});

		cmp_deeply_or_diff
			Publish->getUnpublishedCount(),
			[ {approved_count => '5', title => 'Advisory (email)'} ],
			"getUnpublishedCount - a few approved advisories";
	};


	# Test get(Next|Previous)AdvisoryId.
	withEphemeralDatabase {
		is Publish->getNextAdvisoryId, "TEST-$year-0001", 'getNextAdvisoryId - fresh db';

		requireFixture 'advisory';

		is Publish->getNextAdvisoryId, "TEST-$year-0004", 'getNextAdvisoryId - populated db';

		{
			local Config->{advisory_id_length} = 5;
			is Publish->getNextAdvisoryId, "TEST-$year-00004", 'getNextAdvisoryId - populated db, increased id length';
		}

		# Test with increased advisory_id_length.
		withAdminSession {
			local Config->{advisory_id_length} = 5;

			Taranis::TestUtil::publishAdvisory(
				ADVISORY_NORMAL,
				Taranis::TestUtil::createAdvisory(ADVISORY_NORMAL, "${year}0001", "advisory 4", "1.00")
			);
			Taranis::TestUtil::publishAdvisory(
				ADVISORY_NORMAL,
				Taranis::TestUtil::createAdvisory(ADVISORY_NORMAL, "${year}0001", "advisory 5", "1.00")
			);

			is Publish->getNextAdvisoryId, "TEST-$year-00006", 'getNextAdvisoryId - increased advisory_id_length';
		};

		# Test with decreased advisory_id_length.
		withAdminSession {
			local Config->{advisory_id_length} = 3;

			Taranis::TestUtil::publishAdvisory(
				ADVISORY_NORMAL,
				Taranis::TestUtil::createAdvisory(ADVISORY_NORMAL, "${year}0001", "advisory 6", "1.00")
			);
			Taranis::TestUtil::publishAdvisory(
				ADVISORY_NORMAL,
				Taranis::TestUtil::createAdvisory(ADVISORY_NORMAL, "${year}0001", "advisory 7", "1.00")
			);

			is Publish->getNextAdvisoryId, "TEST-$year-008", 'getNextAdvisoryId - decreased advisory_id_length';
		};
	};
};

done_testing;
