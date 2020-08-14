# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Constituent::Individual;

use strict;
use warnings;

use List::MoreUtils qw(part);

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);

=head1 NAME

Taranis::Constituent::Individual - administration of constituent individuals (contacts)

=head1 SYNOPSIS

=head1 DESCRIPTION

"Constituent Individuals" are the contacts (people) responsible in
"Constituent Groups" (organizations).  Individuals have roles and
receive publications.

=head1 METHODS

=head2 Constructors

=over 4

=cut

use constant {
	INDIV_STATUS_ACTIVE   => 0,
	INDIV_STATUS_DELETED  => 1,
	INDIV_STATUS_DISABLED => 2,
};


=item my $indivs = Taranis::Constituent::Individual->new

Create a new individuals administration object, which is a singleton
object.  Each individual should have been a separate object as well,
but that's not the case for historical mistakes.

=cut

sub new {
	my ($class, $config) = @_;   #XXX config unused
	bless {}, $class;
}

=back

=head2 The collection of individuals

=over 4

=item @results = $indivs->searchIndividuals(%search, %options)

Returns a LIST of HASHes, each describing an individuals which matches
the C<%search>.

Search fields C<firstname>, C<lastname>, C<role_id>, C<group_id> speak for
themselves.  The C<status> may be 0,1,2 with as special value 99 to filter
only locally managed individuals (people without external reference code)

The C<%options> named C<include_roles> and C<include_groups> (booleans) will
invoke C<mergeRoles()> respectively C<mergeGroups()> to add some information
to each of the individuals.

=cut

sub searchIndividuals(%) {
	my ($self, %args) = @_;
	my (@where, @bind, @join);

	my $status = $args{status};
	if(! defined $status) {
		push @where, 'ci.status != '.INDIV_STATUS_DELETED;
	} elsif($status==99) {   # locally managed
		push @where, "(ci.external_ref IS NULL OR ci.external_ref = '')";
	} elsif($status==INDIV_STATUS_ACTIVE || $status==INDIV_STATUS_DISABLED) {
		push @where, "ci.status = $status";
	}

	if(defined (my $first = $args{firstname})) {
		push @where, 'ci.firstname ILIKE ?';
		push @bind, $first;
	}

	if(defined (my $last = $args{lastname})) {
		push @where, 'ci.lastname ILIKE ?';
		push @bind, $last;
	}

	if(my $groupId = $args{group_id}) {
		push @where, "cg.id = $groupId";
		push @join,
			'LEFT JOIN membership        AS  m  ON m.constituent_id = ci.id',
			'LEFT JOIN constituent_group AS cg  ON cg.id = m.group_id';
	}

	if(my $roleId = $args{role_id}) {
		push @where, "cr.id = $roleId";
		push @join,
			'JOIN constituent_role       AS cr  ON cr.id = ci.role';
	}

	my $where = @where ? 'WHERE '.join("\n        AND ", @where) : '';
	my $join  = join "\n       ", @join;

	my @individuals = Database->simple->query(<<__SEARCH, @bind)->hashes;
SELECT ci.*
  FROM constituent_individual AS ci
       @join
       $where
 ORDER BY lastname, firstname
__SEARCH

	foreach my $individual (@individuals) {
		$self->mergeGroups($individual) if $args{include_groups};
		$self->mergeRoles($individual)  if $args{include_roles};
	}

	@individuals;
}


=item $indiv = $indivs->getIndividualById($indivId)

Returns a single HASH representing an individual.
=cut

sub getIndividualById($) {
	my ($self, $indivId) = @_;

	Database->simple->query(<<'__INDIV', $indivId)->hash;
SELECT * FROM constituent_individual WHERE id = ?
__INDIV
}


=item $indivId = $indivs->addIndividual(%details)

Create a new individual, returned is its ID.

The C<%details> contain columns of the C<constituent_individual>.  Besides,
it may also contain
C<group_ids> (ARRAY of existing constituent group references),
C<publication_ids> (ARRAY of existings publication type references), and
C<role_ids> (ARRAY of constituent role references).
=cut

sub addIndividual(%) {
	my ($self, %details) = @_;

	my $groupIds   = delete $details{group_ids};
	my $pubTypeIds = delete $details{publication_ids};
	my $roleIds    = delete $details{role_ids};

	my $db    = Database->simple;
	my $guard = $db->beginWork;

	my $indivId = $db->addRecord(constituent_individual => \%details);
	$db->setList(membership => group_id => $groupIds, constituent_id => $indivId);
	$db->setList(constituent_publication => type_id => $pubTypeIds, constituent_id => $indivId);
	$db->setList(individual_roles => individual_role_id => $roleIds, individual_id => $indivId);

	$db->commit($guard);
	$indivId;
}


=item $indivs->updateIndividual($indivId, %details)

Update the data for the C<$individual> with C<%details>.  Fields which are
not mentioned will not be changed.  References to C<group_ids>,
C<publication_ids>, and C<role_ids> will only get updated when they pass an
ARRAY.
=cut

sub updateIndividual($%) {
	my ($self, $indivId, %details) = @_;

	my $wantGroupIds = delete $details{group_ids};
	my $wantPubIds   = delete $details{publication_ids};
	my $wantRoleIds  = delete $details{role_ids};

	my $db  = Database->simple;
	my $guard = $db->beginWork;

	$db->setRecord(constituent_individual => $indivId, \%details);
	$db->updateList(membership => group_id => $wantGroupIds, constituent_id => $indivId);
	$db->updateList(constituent_publication => type_id => $wantPubIds, constituent_id => $indivId);
	$db->updateList(individual_roles => individual_role_id => $wantRoleIds, individual_id => $indivId);

	$db->commit($guard);
	$self;
}


=item $indivs->deleteIndividual($indivId)

Delete a contact, well actuall this only sets the status of the individual
to '1' (deleted);

This implies the deletion of all the memberships (table C<membership>)
of this individual and deletion of all settings for receiving publications
(table C<constituent_publication>).
=cut

sub deleteIndividual($) {
	my ($self, $indivId) = @_;

	my $db    = Database->simple;
	my $guard = $db->beginWork;

	$db->setRecord(constituent_individual => $indivId, { status => INDIV_STATUS_DELETED });
	$db->deleteRecord(membership => $indivId, 'constituent_id');
	$db->deleteRecord(constituent_publication => $indivId, 'constituent_id');

	$db->commit($guard);
	$self;
}

=back

=head2 Single individual

=over 4

=item @groups = $indivs->getGroupsForIndividual($individual)

=item @groups = $indivs->getGroupsForIndividual($indivId)

Returns a LIST of HASHes, which each contains extended group information
for groups where the individual belongs to.  You may pass an individual
HASH or ID.  The result is ordered by group name.
=cut

sub getGroupsForIndividual($) {
	my ($self, $indiv) = @_;
	my $indivId = ref $indiv ? $indiv->{id} : $indiv;

	Database->simple->query( <<'__GET_GROUPS', $indivId)->hashes;
SELECT cg.*, ct.type_description
  FROM constituent_group           AS cg
       JOIN membership             AS m   ON m.group_id = cg.id
       JOIN constituent_individual AS ci  ON ci.id = m.constituent_id
       JOIN constituent_type       AS ct  ON ct.id = cg.constituent_type
 WHERE ci.id = ?
 ORDER BY name
__GET_GROUPS
}


=item @ids = $indivs->getGroupIDs($individual)

=item @ids = $indivs->getGroupIDs($indivId)

Returns a LIST of IDs of the groups the individual belongs to.  This is
less effort than C<getGroupsForIndividual()>.
=cut

sub getGroupIDs($) {
	my ($self, $indiv) = @_;
	my $indivId = ref $indiv ? $indiv->{id} : $indiv;

	Database->simple->query( <<'__GET_GROUP_IDS', $indivId)->flat;
SELECT cg.id
  FROM constituent_individual AS ci
       JOIN membership        AS m   ON m.constituent_id = ci.id
       JOIN constituent_group AS cg  ON cg.id = m.group_id
 WHERE ci.id = ?
__GET_GROUP_IDS
}


=item $indivs->mergeGroups($individual)

Merge-in group information into the C<$individual> HASH, for the purpose
of the display of the individual's data.
=cut

sub mergeGroups($) {
	my ($self, $individual) = @_;
	my $groups = $individual->{groups} ||= $self->getGroupsForIndividual($individual->{id});

	my ($enabled, $disabled) = part { $_->{status}==0 ? 0 : 1 } @$groups;
	$individual->{groups_enabled}  = join ', ', map $_->{name}, @$enabled;
	$individual->{groups_disabled} = join ', ', map $_->{name}, @$disabled;
	$self;
}


=item $indivs->mergeRoles($individual)

Merge-in individual role information into the C<$individual> HASH, for
the purpose of the display of the individual's facts.
=cut

sub mergeRoles($) {
	my ($self, $individual) = @_;
	my $roles = $individual->{roles} ||= [ $self->getRolesForIndividual($individual) ];
	$individual->{role_names} = join ', ', sort map $_->{role_name}, @$roles;
	$self;
}


=item $indivs->mergePublicationTypes($individual)

Merge-in information about which publications an C<$individual> will receive, for
the purpose of displaying the individual's data.
=cut

sub mergePublicationTypes($) {
	my ($self, $individual) = @_;
	$individual->{publication_types} ||=
		[ $self->getPublicationTypesForIndividual($individual) ];
	$self;
}


=back

=head2 Individual roles

=over 4

=item my $role = $indivs->getRoleByID($roleId)

Returns a HASH which defines an individual role.
=cut

sub getRoleByID($) {
	my ($self, $roleId) = @_;
	Database->simple->getRecord(constituent_role => $roleId);
}


=item @roles = $indivs->allConstituentRoles()

Returns HASHes for all existing roles (including those flagged with
disabled or deleted)  They are sorted by name.
=cut

sub allConstituentRoles() {
	my $self = shift;
	Database->simple->query( <<'__CONST_ROLES' )->hashes;
SELECT * FROM constituent_role ORDER BY role_name
__CONST_ROLES
}


=item $indivs->deleteRole($roleId) or die

Delete an individual role.  When some individual still uses this role,
deletion is refused and FALSE returned.
=cut

sub deleteRole($) {
	my ($self, $roleId) = @_;

	my $db = Database->simple;
	if($db->recordExists(individual_roles => {individual_role_id => $roleId} )) {
		$self->{errmsg} = "Cannot delete role, because there are individuals with this role.";
		return 0;
	}

	$db->deleteRecord(constituent_role => $roleId);
	1;
}


=item $name = $indivs->getRoleName($roleId)

Convenience method to only return the name of a C<$roleId>.
=cut

sub getRoleName($) {
	my ($self, $roleId) = @_;
	my $role = $self->getRoleByID($roleId);
	$role ? $role->{role_name} : undef;
}


=item @roles = $indivs->getRolesForIndividual($individual)

=item @roles = $indivs->getRolesForIndividual($indivId)

Returns a LIST of HASHes, which each describe a constituent role this individual
plays.

=cut

sub getRolesForIndividual($) {
	my ($self, $indiv) = @_;
	my $indivId = ref $indiv ? $indiv->{id} : $indiv;

	Database->simple->query(<<'__ROLES', $indivId)->hashes;
SELECT role.*
  FROM individual_roles       AS ir
       JOIN constituent_role  AS role  ON ir.individual_role_id = role.id
 WHERE ir.individual_id = ?
__ROLES
}


=back

=head2 Publication types

=over 4

=item @types = $indivs->getPublicationTypesForIndividual($individual)

=item @types = $indivs->getPublicationTypesForIndividual($indivId)

Returns HASHes which contain publication information for each of the
publications the individual is configured to receive.
=cut

sub getPublicationTypesForIndividual($) {
	my ($self, $individual) = @_;
	my $indivId = ref $individual ? $individual->{id} : $individual;

	my @types = Database->simple->query( <<'__PUBTYPES', $indivId )->hashes;
SELECT pt.*
  FROM publication_type AS pt
       JOIN constituent_publication AS cp  ON cp.type_id = pt.id
       JOIN constituent_individual  AS ci  ON ci.id      = cp.constituent_id
 WHERE ci.id = ?
__PUBTYPES

    @types;
}

=back

=cut

1;
