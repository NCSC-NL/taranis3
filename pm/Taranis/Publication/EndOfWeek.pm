# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication::EndOfWeek;

use strict;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Publication;

use SQL::Abstract::More;

sub new {
	my ( $class, %args ) = @_;

	my $oTaranisConfig = ( exists( $args{config} ) ) ? $args{config} : Taranis::Config->new();
	my $oTaranisPublication = Taranis::Publication->new();
	my $typeName = Taranis::Config->new( $oTaranisConfig->{publication_templates} )->{eow}->{email};
	my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};

	my $self = {
		dbh => Database,
		sql => Sql,
		config => $oTaranisConfig,
		typeId => $typeId
	};
	
	return( bless( $self, $class ) );
}

sub deletePublication {
	my ( $self, $id, $oTaranisPublication ) = @_;
	
	my $oTaranisTagging = Taranis::Tagging->new();

	withTransaction {
		$oTaranisTagging->removeItemTag( $id, "publication_endofweek" );

		my ( $stmnt, @bind ) = $self->{sql}->delete( "publication_endofweek", { id => $id } );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	};

	return 1;
}
1;

=head1 NAME

Taranis::Publication::EndOfWeek

=head1 SYNOPSIS

  use Taranis::Publication::EndOfWeek;

  my $obj = Taranis::Publication::EndOfWeek->new( config => $oTaranisConfig );

  $obj->deletePublication( $id, $oTaranisPublication );

=head1 DESCRIPTION

Several End-of-Week specific functions.

=head1 METHODS

=head2 new( config => $oTaranisConfig )

Constructor of the C<Taranis::Publication::EndOfWeek> module. An object instance of C<Taranis::Config>, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Publication::EndOfWeek->new( config => $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Stores the type ID of eod email:

    $obj->{typeId}

Returns the blessed object.

=head2 deletePublication( $id, $oTaranisPublication )

Will delete an End-of-Week and remove the associated tags.

If successful returns TRUE.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
