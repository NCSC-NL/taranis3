# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Entitlement;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		dbh => Database,
		sql => Sql,
	};

	return( bless( $self, $class ) );
}

sub getEntitlement {
	my ( $self, %where ) = @_;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'entitlement', "*", \%where, 'name' );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}


=head1 NAME

Taranis::Entitlement -  mainly for retrieving entitlements.

=head1 SYNOPSIS

  use Taranis::Entitlement

  my $obj = Taranis::Entitlement->new( $oTaranisConfig );

  $obj->getEntitlement( %where );

  $obj->nextObject();

  $obj->getObject();

=head1 DESCRIPTION

This module is used for retrieving entitlements using the getEntitlement() method and helper methods getObject() and nextObject(). 

=head1 METHODS

=head2 new( $oTaranisConfig )

Constructor of the C<Taranis::Entitlement> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Entitlement->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 getEntitlement( %where ), nextObject( ) & getObject( )

Method for retrieving all entitlements. Should be used with helper methods getObject() and nextObject() . 

Example:

    $obj->getEntitlement();

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=cut

1;
