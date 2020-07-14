# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Constituent::Group;

use strict;
use warnings;

use Taranis qw(val_int val_string);
use Taranis::Constituent::Individual  ();
use Taranis::ImportPhoto              ();
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);

=head1 NAME

Taranis::Constituent::Group - administration of constituent groups

=head1 SYNOPSIS

=head1 DESCRIPTION

"Constituent Individuals" (contacts) of "Constituent Groups" (organizations)
will receive a selection of publication types.

=head1 METHODS

=head2 Constructors

=over 4

=cut

use constant {
	GROUP_STATUS_ACTIVE   => 0,
	GROUP_STATUS_DELETED  => 1,
	GROUP_STATUS_DISABLED => 2,
};


=item my $groups = Taranis::Constituent::Group->new($config)

Create a new groups administration object, which is a singleton object.
Each group should have been a separate object as well, but that's not
the case for historical mistakes.
=cut

sub new {
	my ($class, $config) = @_;

	bless {
		config      => $config,
		TCG_individuals => Taranis::Constituent::Individual->new($config),
		TCG_photos      => Taranis::ImportPhoto->new($config),
	}, $class;
}

# Internal accessors
sub individuals() { shift->{TCG_individuals} }
sub photos()      { shift->{TCG_photos} }

=back

=head2 The collection of groups

=over 4

=item @results = $groups->searchGroups(%search, %options)

As options, you may use C<inspect_photo> to merge-in some info about
unresolved photo import issues.
=cut

sub searchGroups(%) {
	my ($self, %args) = @_;
	my (@where, @bind);

	if(my $typeId = $args{group_type_id}) {
		push @where, "ct.id = $typeId";
	}

	if(defined(my $status = $args{status})) {
		push @where, "cg.status = $status";
	} else {
		push @where, 'cg.status != '.GROUP_STATUS_DELETED;
	}

	if(defined(my $name = $args{name})) {
		push @where, 'cg.name ILIKE ?';
		push @bind, "%$name%";
	}

	my $where  = @where ? 'WHERE '.join(' AND ', @where) : '';

	my @groups = Database->simple->query(<<__SEARCH_GROUPS, @bind)->hashes;
SELECT cg.*, ct.type_description
  FROM constituent_group     AS cg
       JOIN constituent_type AS ct  ON ct.id = cg.constituent_type
 $where
 ORDER BY cg.name
__SEARCH_GROUPS

	foreach my $group (@groups) {
		$self->mergePhoto($group) if $args{inspect_photo};
	}

	@groups;
}


=item $groupId = $groups->addGroup(%details)

Create a new constituent group.  Returned is its unique identifier.  The C<%details>
contains the columns of table C<constituent_group>, but also C<member_ids> (an
ARRAY of individuals to add to this group) and C<swhw_ids> (an ARRAY with software
and hardware ids, the contents of a photo).
=cut

sub addGroup(%) {
	my ($self, %details) = @_;
	my $memberIds = delete $details{member_ids};
	my $swhwIds   = delete $details{swhw_ids};

	my $db        = Database->simple;
	my $guard     = $db->beginWork;

	my $groupId   = $db->addRecord(constituent_group => \%details);
	$db->setList(membership => constituent_id => $memberIds, group_id => $groupId);
	$db->setList(soft_hard_usage => soft_hard_id => $swhwIds, group_id => $groupId);

	$db->commit($guard);
	$groupId;
}


=item $groups->updateGroup($groupId, %details)

Change the details of some existing group.  Missing columns are not changed.  When
C<member_ids> or C<swhw_ids> are missing (or undef), those relations will not be
modified either.
=cut

sub updateGroup($%) {
	my ($self, $groupId, %details) = @_;
	my $memberIds = delete $details{member_ids};
	my $swhwIds   = delete $details{swhw_ids};

	my $db    = Database->simple;
	my $guard = $db->beginWork;

	$db->setRecord(constituent_group => $groupId, \%details);
	$db->updateList(membership => constituent_id => $memberIds, group_id => $groupId);
	$db->updateList(soft_hard_usage => soft_hard_id => $swhwIds, group_id => $groupId);

	$db->commit($guard);
	$groupId;
}


=item $groups->deleteGroup($groupId) or die $self->{errmsg}

Remove the group, which is only possible when it has no members.  Actually, the
group is only flagged as being deleted.  The photo is cleared.
=cut

sub deleteGroup($) {
	my ($self, $groupId) = @_;

	my $db = Database->simple;
	if($db->recordExists(membership => { group_id => $groupId })) {
		$self->{errmsg} = "Cannot delete group, because this group still has members.";
		return 0;
	}

	$db->deleteRecord(soft_hard_usage => { group_id => $groupId });
	$db->setRecord(constituent_group => $groupId, {status => GROUP_STATUS_DELETED});
	1;
}


=item $group = $groups->getGroupById($groupId)

Returns a HASH with simple information about the group.
=cut

sub getGroupById {
	my ($self, $groupId) = @_;

	Database->simple->query( <<'__GROUP_BY_ID', $groupId)->hash;
SELECT * FROM constituent_group WHERE id = ?
__GROUP_BY_ID
}


=item @photos = $groups->photosForGroups

Return a LIST of HASHes, each reflecting the last imported photo for each
of the enabled groups.
=cut

sub photosForGroups() {
	my ($self) = @_;

	Database->simple->query( <<'__PHOTOS' )->hashes;
SELECT cg.id, cg.external_ref, MAX(photo.imported_on) AS last_update
  FROM constituent_group cg
       JOIN import_photo photo ON cg.id = photo.group_id
 WHERE cg.status = 0
 GROUP BY cg.id, cg.external_ref
__PHOTOS
}

=back

=head2 Single group

=over 4

=item $groups->mergePhoto($group)

Merge information about the photo manage into the group structure, to simplify
displaying the group.
=cut

sub mergePhoto($) {
	my ($self, $group) = @_;
	$group->{issueList} = $self->photos->groupIssues($group->{id}) || [];
	$self;
}


=item @indivIds = $groups->getMemberIds($group)

=item @indivIds = $groups->getMemberIds($groupId)

Returns a LIST with all individual ids which relate to the provided group.
=cut

sub getMemberIds {
	my ($self, $group) = @_;
	my $groupId = ref $group ? $group->{id} : $group;

	Database->simple->query( <<'__GET_MEMBER_IDS', $groupId)->flat;
SELECT m.constituent_id
  FROM constituent_group AS cg
       JOIN membership   AS m   ON m.group_id = cg.id
 WHERE cg.id = ?
__GET_MEMBER_IDS
}


=item @indivs = $groups->getActiveMembers($group);

Returns a LIST of HASHes, each representing one individual.  This HASH
is extended with role and publication type information to simplify the
display of these contacts.
=cut

sub getActiveMembers($%) {
	my ($self, $group, %options) = @_;
	my $groupId = ref $group ? $group->{id} : $group;

	my $db      = Database->simple;
	my @members = $db->query( <<'__GET_MEMBERS', $groupId)->hashes;
SELECT ci.*
  FROM constituent_group AS cg
       JOIN membership   AS m            ON m.group_id = cg.id
       JOIN constituent_individual AS ci ON ci.id      = m.constituent_id
 WHERE cg.id = ?  AND  ci.status = 0
__GET_MEMBERS

	my $indivs = $self->individuals;
	$indivs->mergeRoles($_)->mergePublicationTypes($_)
		for @members;

	@members;
}


=back

=head2 Constituent types

=over 4

=item @types = $groups->allConstituentTypes

Returns a LIST of HASHes describing all constituent types, ordered by
description.
=cut

sub allConstituentTypes() {
	Database->simple->query( <<'__GET_TYPES' )->hashes;
SELECT * FROM constituent_type ORDER BY type_description
__GET_TYPES
}


=item $type = $groups->getConstituentTypeByID($typeId)

Returns a HASH with constituent type information.
=cut

sub getConstituentTypeByID($) {
	my ($self, $typeId) = @_;

	Database->simple->query( <<'__GET_TYPE', $typeId)->hash;
SELECT * FROM constituent_type WHERE id = ?
__GET_TYPE
}


=item $groups->deleteConstituentType or die $self->{errmsg}

Remove a constituent type, which is only permitted when it is not in use by
any group.  The related publication type list gets cleaned-up.
=cut

sub deleteConstituentType($) {
	my ($self, $typeId) = @_;
	my $db = Database->simple;

	if($db->recordExists(constituent_group => { constituent_type => $typeId} )) {
		$self->{errmsg} = "Cannot delete type. A constituent group with this type exists.";
		return 0;
	}

	$db->deleteRecord(type_publication_constituent => $typeId, 'constituent_type_id');
	$db->deleteRecord(constituent_type => $typeId);
	1;
}

=back

=head2 Photo details for a group

=over 4

=item @swhw_ids = $groups->getSoftwareHardwareIds($groupId)

Returns a list of IDs to software and hardware items which are in use by
the group.
=cut

sub getSoftwareHardwareIds($) {
	my ($self, $groupId) = @_;

    Database->simple->query( <<'__GROUPS_SWHW_IDS', $groupId)->flat;
SELECT soft_hard_id FROM soft_hard_usage WHERE group_id = ?
__GROUPS_SWHW_IDS
}


=item $swhw = $groups->getSoftwareHardware($groupid)

Returns an ARRAY of HASHes which each describe a SW/HW item which is used
by the group.
=cut

sub getSoftwareHardware($) {
	my ($self, $groupId) = @_;

	my @swhw = Database->simple->query( <<'__GROUPS_SWHW', $groupId)->hashes;
SELECT sh.*, sht.description
  FROM software_hardware      AS sh
       JOIN soft_hard_usage   AS shu ON sh.id    = shu.soft_hard_id
       JOIN constituent_group AS cg  ON cg.id    = shu.group_id
       JOIN soft_hard_type    AS sht ON sht.base = sh.type
 WHERE cg.id = ?
 ORDER BY sh.name
__GROUPS_SWHW

	\@swhw;
}


=item $groups->callForHighHighPhoto($groupId) or next
=cut

sub callForHighHighPhoto {
	my ($self, $groupId) = @_;
	Database->simple->query(<<'__PHOTO_HH', $groupId)->list;
 SELECT 1 FROM constituent_group
  WHERE id = ?  AND use_sh  AND call_hh
__PHOTO_HH
}


=item $groups->callForHighHighAny($groupId) or next
=cut

sub callForHighHighAny {
	my ($self, $groupId) = @_;
	Database->simple->query(<<'__ANY_HH', $groupId)->list;
 SELECT 1 FROM constituent_group
  WHERE id = ?  AND NOT use_sh  AND any_hh
__ANY_HH
}


=back

=head2 Constituent types

=over 4

=item $typeId = $groups->addConstituentType(%details)

Create a new constituent group type.
=cut

sub addConstituentType(%) {
	my ($self, %details) = @_;

	my $wantPubIds  = delete $details{pubtype_ids};
	my $description = delete $details{description};

	my $db    = Database->simple;
	my $guard = $db->beginWork;

	my $typeId = $db->addRecord(constituent_type => { type_description => $description });
	$db->setList(type_publication_constituent => publication_type_id => $wantPubIds,
		constituent_type_id => $typeId);

	$db->commit($guard);
	$typeId;
}


=item $groups->updateConstituentType($typeId, %details)

Update the configuration of the constituent group type, which is a descriptive
text and a list of related publications available to members of this group.
=cut

sub updateConstituentType($%) {
	my ($self, $typeId, %details) = @_;
	my $wantPubIds  = delete $details{pubtype_ids};
	my $description = delete $details{description};

	my $db    = Database->simple;
	my $guard = $db->beginWork;

	$db->setRecord(constituent_type => $typeId, { type_description => $description });
	$db->updateList(type_publication_constituent => publication_type_id => $wantPubIds,
		constituent_type_id => $typeId);

	$db->commit($guard);
	$self;
}

=back

=cut

1;
