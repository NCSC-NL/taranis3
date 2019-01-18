#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Test::Most;
use JSON;

use Taranis qw(nowstring);
use Taranis::Config;
use Taranis::Database;
use Taranis::Publication;
use Taranis::FunctionalWrapper qw(Config Database Publication);
use Taranis::TestUtil qw(cmp_deeply_or_diff withEphemeralDatabase withDistConfig requireFixture lastTableId);


withDistConfig {
	local Config->{advisory_prefix} = "TEST";

	my ($got, $exp, @analysis_ids);
	my $year = nowstring(6);

	# Run tests once for normal advisories, and once for 'advisory forward's.
	for my $type (
		{
			# Normal advisory.
			name_short => 'advisory',
			name_long => 'Advisory (email)',
			table => 'publication_advisory',
			fixture => 'advisory',
		},
		{
			# 'Advisory forward'.
			name_short => 'forward',
			name_long => 'Advisory (forward)',
			table => 'publication_advisory_forward',
			fixture => 'advisory_forward',
		},
	) {
		subtest $type->{name_long} => sub {
			withEphemeralDatabase {
				# Create a few advisories.
				requireFixture $type->{fixture};

				# Set advisories' status to "published".
				my $db = Database->simple;
				$db->update('publication', {status => 3});

				# Test setPublication.
				{
					my $publication_type = $db->select(
						'publication_type', 'id', {title => $type->{name_long}}
					)->list;

					Publication->setPublication(id => lastTableId('publication'), status => 2);
					is $db->select('publication', ['status'], {id => lastTableId('publication')})->list,
						2,
						"setPublication status";
					Publication->setPublication(id => lastTableId('publication'), status => 3);
					is $db->select('publication', ['status'], {id => lastTableId('publication')})->list,
						3,
						"setPublication status back";

					dies_ok {
						Publication->setPublication(id => lastTableId('publication') + 1, status => 2)
					} "death on invalid id";

					Publication->setPublication(
						status => 2,
						where => {
							type => $publication_type,
							title => {-like => 'advisory 2.%'},
						}
					);
					cmp_deeply_or_diff [ $db->select(
						-from => 'publication',
						-columns => ['status'],
						-where  => {type => $publication_type},
						-order_by => ['id']
					)->flat ],
						[3, 3, 2, 2, 3],
						"setPublication status with where";

					Publication->setPublication(
						status => 3,
						where => {
							type => $publication_type,
							title => {-like => 'advisory 2.%'},
						}
					);
					cmp_deeply_or_diff [ $db->select(
						-from => 'publication',
						-columns => ['status'],
						-where  => {type => $publication_type},
					)->flat ],
						[3, 3, 3, 3, 3],
						"setPublication status back with where";
				}

				# Test getPublishedPublicationsByAnalysisId.
				{
					always_show $got, $exp unless cmp_bag(
						$got = [
							map { $_->{title} } @{
								Publication->getPublishedPublicationsByAnalysisId(
									table => $type->{table},
									analysis_id => "${year}0001",
								)
							}
						],
						$exp = ["advisory 1"],
						"getPublishedPublicationsByAnalysisId - 1 match"
					);

					always_show $got, $exp unless cmp_bag(
						$got = [
							map { $_->{title} } @{
								Publication->getPublishedPublicationsByAnalysisId(
									table => $type->{table},
									analysis_id => "${year}0002",
								)
							}
						],
						$exp = ["advisory 2", "advisory 2.1", "advisory 2.2", "advisory 3"],
						"getPublishedPublicationsByAnalysisId - 2 matches"
					);

					always_show $got, $exp unless cmp_bag(
						$got = [
							map { $_->{title} } @{
								Publication->getPublishedPublicationsByAnalysisId(
									table => $type->{table},
									analysis_id => "${year}0003",
								)
							}
						],
						$exp = [],
						"getPublishedPublicationsByAnalysisId - no matches"
					);

					always_show $got, $exp unless cmp_bag(
						$got = [
							map { $_->{title} } @{
								Publication->getPublishedPublicationsByAnalysisId(
									table => $type->{table},
									analysis_id => "${year}0002",
									hyperlinks => "https://www.ncsc.nl/advisory-3-link",
								)
							}
						],
						$exp = ["advisory 3"],
						"getPublishedPublicationsByAnalysisId - extra condition"
					);
				}

				# Test getLatestAdvisoryVersion.
				{
					always_show $got, $exp unless cmp_deeply(
						$got = Publication->getLatestAdvisoryVersion(govcertId => "TEST-$year-0001"),
						$exp = superhashof({
							govcertid => "TEST-$year-0001",
							version => "1.00",
						}),
						"getLatestAdvisoryVersion - v1.00"
					);

					always_show $got, $exp unless cmp_deeply(
						$got = Publication->getLatestAdvisoryVersion(govcertId => "TEST-$year-0002"),
						$exp = superhashof({
							govcertid => "TEST-$year-0002",
							version => "1.02",
						}),
						"getLatestAdvisoryVersion - v1.02"
					);

					always_show $got, $exp unless cmp_deeply(
						$got = Publication->getLatestAdvisoryVersion(govcertId => "TEST-$year-0005"),
						$exp = undef,
						"getLatestAdvisoryVersion - nonexistent advisory"
					);
				}

				# Test searchPublishedPublications.
				{
					always_show $got, $exp unless cmp_bag(
						$got = Publication->searchPublishedPublications('you cannot find anything', $type->{name_short}),
						$exp = [],
						"searchPublishedPublications - no matches"
					);

					always_show $got, $exp unless cmp_bag(
						$got = Publication->searchPublishedPublications('', $type->{name_short}),
						$exp = [
							superhashof({named_id => "TEST-$year-0001", version => "1.00"}),
							superhashof({named_id => "TEST-$year-0002", version => "1.02"}),
							superhashof({named_id => "TEST-$year-0003", version => "1.00"}),
						],
						"searchPublishedPublications - empty search string, match everything"
					);

					always_show $got, $exp unless cmp_bag(
						$got = Publication->searchPublishedPublications('advisory 1', $type->{name_short}),
						$exp = [
							superhashof({named_id => "TEST-$year-0001", version => "1.00"}),
						],
						"searchPublishedPublications - match one advisory"
					);

					always_show $got, $exp unless cmp_bag(
						$got = Publication->searchPublishedPublications('advisory 2', $type->{name_short}),
						$exp = [
							superhashof({named_id => "TEST-$year-0002", version => "1.02"}),
						],
						"searchPublishedPublications - match one updated advisory"
					);
				}
			};
		};
	}
};

done_testing;
