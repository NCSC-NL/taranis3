#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Test::Most;

use Taranis qw(nowstring);
use Taranis::TestUtil qw(
	cmp_deeply_or_diff requireFixture withAdminSession withEphemeralDatabase withDistConfig tableIds
);
use Taranis::Config;
use Taranis::Database;
use Taranis::Publish;
use Taranis::SoftwareHardware;
use Taranis::FunctionalWrapper qw(Config Database Publish SoftwareHardware);


withDistConfig {
	withEphemeralDatabase {
		requireFixture 'types_and_roles';
		requireFixture 'software_hardware';

		# Create 3 constituent groups, give two of them some soft_hard_usage.
		{
			my @group_ids;
			push @group_ids, scalar Database->{simple}->insert(
				-into => 'constituent_group',
				-values => {
					name => "group $_",
					use_sh => 0,
					status => 0,
					constituent_type => 1,
				},
				-returning => 'id',
			)->list for 1 .. 3;

			Database->{simple}->insert(
				-into => 'soft_hard_usage',
				-values => {
					group_id => $group_ids[0],
					soft_hard_id => $_,
				},
			) for (tableIds 'software_hardware')[1 .. 9];

			Database->{simple}->insert(
				-into => 'soft_hard_usage',
				-values => {
					group_id => $group_ids[1],
					soft_hard_id => $_,
				},
			) for (tableIds 'software_hardware')[6 .. 15];
		}

		# Test getList and getListCount.
		{
			# If `id` is specified, &getList returns the matching row (if any). Otherwise, it returns nothing but places the
			# results in Database->{sth} for fetching.
			# reallyGetList is a workaround to return the actual results in the latter case.
			sub reallyGetList {
				my %args = @_;

				if (defined $args{id}) {
					return SoftwareHardware->getList(%args);
				} else {
					SoftwareHardware->getList(%args);
					my @result;
					push @result, SoftwareHardware->getObject while SoftwareHardware->nextObject;
					return \@result;
				}
			}

			# Fetch id of the <shift>'th software/hardware item in the sample (software_hardware_sample.sql). 0-based.
			sub wareId ($) {
				return [ tableIds 'software_hardware' ]->[shift];
			}

			is SoftwareHardware->getListCount(id => wareId 6), 1, "getListCount - by id, 2 constituents using";
			cmp_deeply_or_diff
				reallyGetList(id => wareId 6),
				{
				  'cpe_id' => undef,
				  'description' => 'Application',
				  'id' => wareId 6,
				  'in_use' => '2',
				  'monitored' => 0,
				  'name' => '2.3 alpha14',
				  'producer' => 'OrangeHRM',
				  'type' => 'a',
				  'version' => undef
				},
				"getList - by id, 2 constituents using";

			is SoftwareHardware->getListCount(id => wareId 7), 0, "getListCount - by id, disabled=true";
			is
				reallyGetList(id => wareId 7),
				undef,
				"getList - by id, disabled=true";

			is SoftwareHardware->getListCount(producer => 'nonexistent producer'), 0, "getListCount - search, disabled=true";
			cmp_deeply_or_diff
				reallyGetList(producer => 'nonexistent producer'),
				[],
				"getList - search, disabled=true";

			is SoftwareHardware->getListCount(id => wareId 17), 1, "getListCount - by id, 0 constituents using";
			cmp_deeply_or_diff
				reallyGetList(id => wareId 17),
				{
				  'cpe_id' => undef,
				  'description' => 'Application',
				  'id' => wareId 17,
				  'in_use' => '0',
				  'monitored' => 0,
				  'name' => 'Application Service Dashboard',
				  'producer' => 'Symantec',
				  'type' => 'a',
				  'version' => undef
				},
				"getList - by id, 0 constituents using";

			# limit/offset are only applicable to getList, not to getListCount.
			cmp_deeply_or_diff
				reallyGetList(limit => 2, offset => 4),
				bag(
					reallyGetList(id => wareId 1),
					reallyGetList(id => wareId 2),
				),
				"getList - limit+offset";

			is SoftwareHardware->getListCount( producer => 'HP', in_use => 1,), 2, "getListCount - search";
			cmp_deeply_or_diff
				reallyGetList(
					producer => 'HP',
					in_use => 1,
					limit => 2,
					offset => 0,
				),
				bag(
					reallyGetList(id => wareId 1),
					reallyGetList(id => wareId 2),
				),
				"getList - search + limit";
		}
	};
};

done_testing;
