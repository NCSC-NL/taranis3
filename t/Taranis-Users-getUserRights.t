#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use SQL::Abstract::More;
use Test::PostgreSQL;
use Test::Most;

use Taranis::Database;
use Taranis::Role;
use Taranis::TestUtil qw(cmp_deeply_or_diff withEphemeralDatabase withDistConfig);
use Taranis::Users qw(getUserRights);
use Taranis::FunctionalWrapper qw(Database Role Sql Users);


withDistConfig {
	withEphemeralDatabase {
		# Test gazillion role right combinations.
		{
			testRoles(
				[
					[1, 0, 1, ''],
				],
				[1, 0, 1, ''],
				"basic rights retrieval"
			);

			testRoles(
				[
					[1, 0, 1, 'foo,bar'],
				],
				[1, 0, 1, ['foo', 'bar']],
				'basic rights retrieval with particularization'
			);

			testRoles(
				[
					[1, 0, 0, ''],
					[0, 1, 0, ''],
				],
				[1, 1, 0, ''],
				'simple addition of r/w/x rights'
			);

			testRoles(
				[
					[0, 1, 1, 'foo,bar'],
				],
				[0, 1, 1, ''],
				'particularization without read right ignored'
			);

			testRoles(
				[
					[0, 1, 1, ''],
					[1, 0, 0, 'foo'],
				],
				[1, 1, 1, ['foo']],
				'empty particularization without read right ignored when combining'
			);

			testRoles(
				[
					[1, 0, 0, ''],
					[0, 1, 1, 'baz'],
				],
				[1, 1, 1, ''],
				'empty particularization with read but without write/execute prevails'
			);

			testRoles(
				[
					[0, 0, 0, ''],
					[0, 0, 0, 'foo,bar'],
				],
				[0, 0, 0, ''],
				'empty particularization prevails without r/w/x rights'
			);

			testRoles(
				[
					[1, 1, 1, ''],
					[1, 1, 1, 'foo,bar'],
				],
				[1, 1, 1, ''],
				'empty particularization prevails with r/w/x rights'
			);

			testRoles(
				[
					[1, 0, 1, 'foo,bar'],
					[1, 0, 1, 'baz'],
				],
				[1, 0, 1, ['foo', 'bar', 'baz']],
				'addition of particularizations'
			);

			testRoles(
				[
					[1, 0, 1, 'foo,bar'],
					[1, 0, 1, 'baz,bar'],
				],
				[1, 0, 1, ['foo', 'bar', 'baz']],
				'deduplication of particularizations'
			);

			testRoles(
				[],
				[0, 0, 0, ''],
				'no rights defined is same as no rights'
			);
		}

		# Verify that we can pass entitlement as a string instead of an array ref.
		{
			my $user_name = uniqueName();
			my $role_name = uniqueName();

			# Relevant entitlement.
			Role->addRole(name => $role_name, description => "role $role_name, for testing");
			Role->addRoleRight(
				entitlement_id => entIdByName('cve'), role_id => roleIdByName($role_name),
				read_right => 1, write_right => 0, execute_right => 1, particularization => 'foo,bar,baz',
			);
			Users->addUser(username => $user_name, fullname => 'John Doe', disabled => 'f');
			Users->setRoleToUser(username => $user_name, role_id => roleIdByName($role_name));

			cmp_deeply_or_diff(
				getUserRights(username => $user_name, entitlement => 'cve'),
				{
					cve => {
						read_right => 1,
						write_right => 0,
						execute_right => 1,
						particularization => bag(qw/foo bar baz/),
					},
				},
				'Can pass entitlement as a string'
			);

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => ['nonexistent entitlement']),
				{
					'nonexistent entitlement' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					},
				},
				'Can pass nonexistent entitlement as a string'
			);
		}

		# A few tests with multiple entitlements.
		{
			my $user_name = uniqueName();
			my $role_name = uniqueName();

			# Relevant entitlement.
			Role->addRole(name => $role_name, description => "role $role_name, for testing");
			Role->addRoleRight(
				entitlement_id => entIdByName('cve'), role_id => roleIdByName($role_name),
				read_right => 0, write_right => 0, execute_right => 0, particularization => '',
			);
			# Irrelevant entitlement with particularization.
			Role->addRoleRight(
				entitlement_id => entIdByName('tools'), role_id => roleIdByName($role_name),
				read_right => 1, write_right => 1, execute_right => 1, particularization => 'foo,bar',
			);
			# Irrelevant entitlement without particularization.
			Role->addRoleRight(
				entitlement_id => entIdByName('analysis'), role_id => roleIdByName($role_name),
				read_right => 1, write_right => 1, execute_right => 1, particularization => '',
			);

			Users->addUser(username => $user_name, fullname => 'John Doe', disabled => 'f');
			Users->setRoleToUser(username => $user_name, role_id => roleIdByName($role_name));

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => ['cve']),
				{
					cve => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					}
				},
				'Other entitlements are properly ignored'
			);

			cmp_deeply(
				getUserRights(username => $user_name, entitlement => ['cve', 'tools', 'analysis']),
				{
					cve => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					},
					tools => {
						read_right => 1,
						write_right => 1,
						execute_right => 1,
						particularization => bag('foo', 'bar'),
					},
					analysis => {
						read_right => 1,
						write_right => 1,
						execute_right => 1,
						particularization => '',
					},
				},
				'Can request multiple entitlements'
			);

			cmp_deeply(
				getUserRights(username => $user_name, entitlement => ['tools', 'nonexistent entitlement']),
				{
					tools => {
						read_right => 1,
						write_right => 1,
						execute_right => 1,
						particularization => bag('foo', 'bar'),
					},
					'nonexistent entitlement' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					},
				},
				'Can request existent and nonexistent entitlement together'
			);
		}

		# Verify handling of entitlements that are nonexistent, or that the user has no rights rows for.
		{
			my $user_name = uniqueName();
			Users->addUser(username => $user_name, fullname => 'John Doe', disabled => 'f');

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => ['nonexistent entitlement']),
				{
					'nonexistent entitlement' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					}
				},
				'No rights to nonexistent entitlement'
			);

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => 'nonexistent entitlement'),
				{
					'nonexistent entitlement' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					}
				},
				'No rights to nonexistent entitlement requested as string'
			);

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => ['generic']),
				{
					'generic' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					}
				},
				'No rights to existing entitlement with no rights rows'
			);

			eq_or_diff(
				getUserRights(username => $user_name, entitlement => 'generic'),
				{
					'generic' => {
						read_right => 0,
						write_right => 0,
						execute_right => 0,
						particularization => '',
					}
				},
				'No rights to existing entitlement with no rights rows, passed as string'
			);
		}
	};
};

done_testing;


sub testRoles {
	my ($roles_ref, $expected_rights_ref, $test_name) = @_;
	_testRoles($roles_ref, $expected_rights_ref, $test_name);

	# Also test with roles in reverse order, to check that the role insertion order doesn't matter.
	if (@$roles_ref > 1) {
		_testRoles([reverse @$roles_ref], $expected_rights_ref, "$test_name (reverse role order)");
	}
}

# Create some roles with rights (defined in $roles_ref) on 'cve' (an arbitrary entitlement); assign a user to these
# roles; check that his rights equal @$expected_rights_ref according to &getUserRights.
# $roles_ref should be of the format: [ [read, write, execute, particularization], ... ]
# E.g.: [
#   [1, 0, 1, 'foo,bar'],  # Particularization is a comma separated string, to match how it's stored in the database.
#   [0, 0, 1, ''],
# ]
# $expected_rights_ref should be of an almost-but-not-quite identical format:
# [
#   1,
#   0,
#   1,
#   ['foo','bar']  # Particularization, here, is either an empty string or an arrayref, to match &getUserRights's
# ]                # output format.
sub _testRoles {
	my ($roles_ref, $expected_rights_ref, $test_name) = @_;

	# Create a fresh user ...
	my $user_name = uniqueName();
	Users->addUser(username => $user_name, fullname => "$user_name the guinea pig", disabled => 'f');

	# ... create fresh roles for him, with the rights defined in @$roles_ref ...
	for my $role_ref (@$roles_ref) {
		my $role_name = uniqueName();
		Role->addRole(name => $role_name, description => "role $role_name, for testing");
		Role->addRoleRight(
			role_id => roleIdByName($role_name),
			entitlement_id => entIdByName('cve'),
			read_right => $role_ref->[0],
			write_right => $role_ref->[1],
			execute_right => $role_ref->[2],
			particularization => $role_ref->[3],
		);
		Users->setRoleToUser(username => $user_name, role_id => roleIdByName($role_name));
	}

	# ... and check that his (combined) rights equal %$expected_rights_ref.
	my $user_rights = getUserRights(username => $user_name, entitlement => ['cve']);

	# We don't care about the order of particularizations, so sort them before comparing.
	$user_rights->{cve}->{particularization} = [sort @{ $user_rights->{cve}->{particularization} }]
		if ref $user_rights->{cve}->{particularization} eq 'ARRAY';
	$expected_rights_ref->[3] = [sort @{ $expected_rights_ref->[3] }]
		if ref $expected_rights_ref->[3] eq 'ARRAY';

	eq_or_diff(
		$user_rights,
		{
			cve => {
				read_right => $expected_rights_ref->[0],
				write_right => $expected_rights_ref->[1],
				execute_right => $expected_rights_ref->[2],
				particularization => $expected_rights_ref->[3],
			}
		},
		"Role permissions test - $test_name"
	);
}

sub uniqueName {
	state $num = 0;
	return "unique_" . $num++;
}

sub entIdByName {
	my $name = shift;
	my ($stmnt, @bind) = Sql->select('entitlement', "*", {name => $name});
	Database->prepare($stmnt);
	Database->executeWithBinds(@bind);
	Database->nextRecord;
	return Database->getRecord->{id};
};

sub roleIdByName {
	my $name = shift;
	my ($stmnt, @bind) = Sql->select('role', "*", {name => $name});
	Database->prepare($stmnt);
	Database->executeWithBinds(@bind);
	Database->nextRecord;
	return Database->getRecord->{id};
};
