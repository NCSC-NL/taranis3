# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publicationtype;

use strict;
use warnings;

use Taranis qw(:util);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Data::Validate qw(is_integer);
use SQL::Abstract::More;
use Tie::IxHash;

sub new {
	my ($class, $config) = @_;
	bless {}, $class;
}

sub getPublicationTypeIds($) {
	my ($self, $indivId) = @_;

	Database->simple->query( <<'__TYPE_IDS', $indivId)->flat;
SELECT DISTINCT(pt.id)
  FROM publication_type AS pt
       JOIN constituent_publication AS cp  ON cp.type_id = pt.id
       JOIN constituent_individual  AS ci  ON ci.id      = cp.constituent_id
 WHERE ci.id = ?
__TYPE_IDS
}

sub getPublicationTypesIndividual($) {  # ci.id cg.status=[0.2]
	my ($self, $indivId) = @_;

	Database->simple->query( <<'__TYPE_BY_INDIV', $indivId)->hashes;
SELECT pt.*, min(cg.status) AS group_status
  FROM publication_type AS pt
       JOIN type_publication_constituent AS tpc ON tpc.publication_type_id = pt.id
       JOIN constituent_group      AS cg ON cg.constituent_type = tpc.constituent_type_id
       JOIN membership             AS m  ON m.group_id = cg.id
       JOIN constituent_individual AS ci ON ci.id = m.constituent_id
 WHERE ci.id = ?     AND (cg.status = 0  OR  cg.status = 2)
 GROUP BY pt.id, pt.title, pt.description
 ORDER BY pt.title
__TYPE_BY_INDIV
}

sub getPublicationTypesGroups(@) {      # cg.id=\@groupIds cg.status=[0,2]
	my ($self, @groupIds) = @_;
	@groupIds or return ();

	Database->simple->query( <<'__TYPE_BY_GROUP', @groupIds)->hashes;
SELECT pt.*, min(cg.status) AS group_status
  FROM publication_type AS pt
       JOIN type_publication_constituent AS tpc ON tpc.publication_type_id = pt.id
       JOIN constituent_group AS cg  ON cg.constituent_type = tpc.constituent_type_id
 WHERE cg.id IN (??)   AND   (cg.status = 0  OR  cg.status = 2)
 GROUP BY pt.id, pt.title, pt.description
 ORDER BY pt.title
__TYPE_BY_GROUP
}

sub allPublicationTypes() {
	my $self = shift;

	Database->simple->query( <<'__ALL_TYPES')->hashes;
SELECT pt.*
  FROM publication_type AS pt
 ORDER BY pt.title
__ALL_TYPES
}

# Publications which each constituent group of a certain group type will receive.
sub getPublicationTypesForCT($) {
	my ($self, $typeId) = @_;

	Database->simple->query( <<'__TYPE', $typeId)->hashes;
SELECT pt.*
  FROM publication_type AS pt
       JOIN type_publication_constituent AS tpc ON tpc.publication_type_id = pt.id
       JOIN constituent_type             AS ct  ON ct.id = tpc.constituent_type_id
 WHERE ct.id = ?
 ORDER BY pt.title
__TYPE
}

1;

=head1 NAME

Taranis::Publicationtype

=head1 SYNOPSIS

  use Taranis::Publicationtype;

  my $obj = Taranis::Publicationtype->new($config);

  my @ids = $obj->getPublicationTypeIds($indivId);

  my @h   = $obj->getPublicationTypesIndividual($indivId);
  my @h   = $obj->getPublicationTypesGroups(@groupIds);
  my @h   = $obj->allPublicationTypes;
  my @h   = $obj->getPublicationTypesForCT($constituentTypeId);

=head1 DESCRIPTION

Module for retrieval of pubication types and retrieval of list of constituent individuals for a specific publication type.

=head1 METHODS

=head2 new( $oTaranisConfig )

Returns the blessed object.


=head2 getPublicationTypeIds($individual_id)

Returns a LIST of publication type ids for the individual.

    my @ids = $obj->getPublicationTypeIds(24);

=back

=cut
