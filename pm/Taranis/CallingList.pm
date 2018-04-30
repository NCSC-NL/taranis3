# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::CallingList;

=head1 NAME

Taranis::CallingList - callinglists in case of a High/High advisory

=head1 DESCRIPTION

In case an advisory has both damage and probability set to 'high',
a callinglist is generated when the advisory has been published. Such
callingslist contains individuals which need to be informed of the
High/High advisory.

After publishing the advisory, the callinglist can be administrated
per constituent group.

=cut

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Time::localtime;
use Array::Utils qw(intersect);

use Taranis::Constituent_Group;
use Taranis::Database;
use Taranis::Publication;
use Taranis::FunctionalWrapper qw(Constituent_Group Database Publication);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	getCallingList getPublicationLists createCallingList
);


# getCallingList: retrieve an array of hashes consisting of constituent groups. Each group has the following keys:
#
# * individuals, is also an ARRAY of HASES which has the C<firstname>, C<lastname>, C<role_name>, C<tel_regular> and
# C<tel_mobile> per individual.
# * comments, concerning the call
# * group_id and constituent_group_id, internal id of constituent group
# * is_called, flag to be set when constituent has been informed
# * groupname, name of constituent group
# * locked_by, can be set to user. Only existing user id's or NULL/undef are allowed.
# * fullname, the descriptive name of the user who has been set at C<locked_by>
# * publication_id, internal id of publication
# * id, internal id of callinglist
# * group_notes, notes which are set for the constituent.
#
# An optional argument is <time_of_day> which only takes values <night> and
# <day>. When <day> is set, the list of the individuals will be made by
# searching for individuals which can 'call_hh' or 'any_hh'.
#     $obj->getCallingList( 78, 'day' );

sub getCallingList($;$) {
	my ($publication_id, $time_of_day) = @_;

	my $hour = localtime->hour;
	$time_of_day ||= $hour >= 9 && $hour <= 17 ? 'day' : 'night';

	croak "invalid time_of_day: $time_of_day"
		if $time_of_day ne 'day' && $time_of_day ne 'night';

	my @groups = Database->{simple}->select(
		-from => [-join => qw/
			calling_list|cl
				group_id=id                  constituent_group|cg
				=>{cl.locked_by=username}    users|u
		/],
		-columns => [qw/cl.*  cg.name|groupname  cg.notes|group_notes  cg.id|constituent_group_id  u.fullname/],
		-where => {
			publication_id => $publication_id,
		},
		-order_by => 'groupname',
	)->hashes;

	my @list;
	foreach my $group ( @groups ) {
		my @indiv = Database->{simple}->select(
			-from => [-join => qw/
				constituent_individual|ci
					id=constituent_id    membership|m
					ci.role=id           constituent_role|cr
			/],
			-columns => 'ci.firstname, ci.lastname, ci.tel_mobile, ci.tel_regular, cr.role_name, ci.call247',
			-where => {
				'm.group_id' => $group->{constituent_group_id},
				'ci.status'  => 0,
				'ci.call_hh' => 1,
			},
			-order_by => 'ci.lastname, ci.firstname'
		)->hashes;

		@indiv or next;

		$group->{individuals} =
			[ (grep $_->{call_hh}, @indiv), (grep !$_->{call_hh}, @indiv) ];

		push @list, $group;
	}

	return \@list;

}

# getPublicationLists: retrieve a callinglist as getCallingList() does, but without the argument <time_of_day> and with
# less details per group.
# Only <is_called>, <group_id>, <locked_by>, <fullname>, <publication_id>, <id> and <comments> are retrieved per group.
#
#     $obj->getPublicationLists( 78 );
sub getPublicationLists {
	my ($publication_id) = @_;

	return [ Database->{simple}->select(
		-from => [-join => qw/
			calling_list|c
				=>{locked_by=username}   users|u
		/],
		-columns => 'c.*, u.fullname',
		-where => {'c.publication_id' => $publication_id},
	)->hashes ];
}

# createCallingList: create calling list for a (presumably high/high) advisory.
# Takes publicationId (to fetch corresponding soft/hardware ids) and a list of groups that were selected to receive the
# advisory; picks out the groups that should also get a call, and inserts those into table `calling_list`.
sub createCallingList {
	my ($publicationId, $group_ids_ref) = @_;
	my @group_ids = @$group_ids_ref;

	my @publication_wares = Database->{simple}->select(
		-from => 'platform_in_publication',
		-union => [-from => 'product_in_publication'],
		-columns => 'softhard_id',
		-where => {
			'publication_id' => $publicationId,
		},
	)->flat;

	#XXX MO: I think this can/should be done in one single query.
	for my $groupId (@group_ids) {
		my $do_call = 0;
		if (Constituent_Group->callForHighHighAny($groupId)) {
			$do_call = 1;
		}
		elsif (Constituent_Group->callForHighHighPhoto($groupId)) {
			my @group_wares = Constituent_Group->getSoftwareHardwareIds($groupId);
			$do_call = intersect(@group_wares, @publication_wares);
		}

		$do_call
			or next;

		Database->{simple}->insert('calling_list', {
			publication_id => $publicationId,
			group_id => $groupId,
		});
	}
}

1;
