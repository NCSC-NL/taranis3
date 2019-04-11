# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Damagedescription;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use strict;

sub new {
	my ( $class, $config ) = @_;  
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

sub getDamageDescription {
  my $self = shift;
	undef $self->{errmsg};
	my @dd_data; 
	 
  if ( @_ % 2 ) {
    $self->{errmsg} = "Default options must be 'name => value' pairs (odd number supplied)";
    return;
  }
	my %where = @_;
	
	$where{deleted} = { '!=', 1 };
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "damage_description", "*", \%where, "description" );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		 $self->{errmsg} = $self->{dbh}->{db_error_msg};
		 return 0;
	} else {
		while ( $self->nextObject ) {
			push ( @dd_data, $self->getObject );
		}	
		wantarray ? @dd_data : $dd_data[0];
	}
}

sub setDamageDescription {
  my $self = shift;
	undef $self->{errmsg};
  
  if ( @_ % 2 ) {
    $self->{errmsg} = "Default options must be 'name => value' pairs (odd number supplied)";
    return 0;
  }
  my %updates = @_;
  
  my %where = ( id => $updates{id} ); 
  delete $updates{id};
  
	my ( $stmnt, @bind ) = $self->{sql}->update( "damage_description", \%updates, \%where );
	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined($result) && ($result !~ m/(0E0)/i ) ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Update failed, corresponding id not found in database.";
		return 0;
	}
}

sub addDamageDescription {
    my ( $self, %inserts ) = @_;
    undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->insert( "damage_description", \%inserts );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteDamageDescription {
  my ( $self, $id ) = @_;
  return $self->setDamageDescription( id => $id, deleted => 1 );
}

=head1 NAME 

Taranis::Damagedescription - add, edit, delete and get damage descriptions 

=head1 SYNOPSIS

  use Taranis::Damagedescription;

  my $obj = Taranis::Damagedescription->new( $oTaranisConfig );

  $obj->addDamageDescription( description => $my_description );

  $obj->getDamageDescription( id => $id_nr, deleted => $is_deleted );

  $obj->setDamageDescription( id => $id_nr, description => $my_description, deleted => $is_deleted );

  $obj->deleteDamageDescription( $id_nr );

=head1 METHODS

=head2 new( )

Constructor for the C<Taranis::Damagedescription> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Damagedescription->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:
   
    $obj->{errmsg};	  	  

Returns the blessed object.

=head2 addDamageDescription( description => $my_description )

Method for adding new damage descriptions.
Expects arguments to be supplied in C<< key => value >> pairs:

    $obj->addDamageDescription( description = "my description", deleted => 0 );

Argument C<deleted> can be left out, because default setting on database level is set to FALSE.

Returns TRUE if database insertion is successful. Returns FALSE if database execution fails and sets C<< $obj->{errmsg} >> to C<< Taranis::Databas->{db_error_msg} >>.

=head2 getDamageDescription( id => $id_nr, deleted => $is_deleted )

Method for retrieval of one, several or all damage descriptions. 
Arguments have to be supplied as C<< key => value >> pairs.

To retrieve one damage description use an id number:  

    $obj->getDamageDescription( id => 1 );

To retrieve all damage descriptions call method without arguments:

    $obj->getDamageDescription();

To retrieve all non-deleted damage descriptions call method with argument deleted set to 0 (FALSE):

    $obj->getDamageDescription( deleted => 0 );

For retrieving all deleted descriptions set deleted value to 1 (TRUE).

Returns all found damage descriptions. If none is found returns an empty HASH. Sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
  
=head2 setDamageDescription( id => $id_nr, description => $my_description, deleted => $is_deleted )

Method for editing damage descriptions. 
It's mandatory to supply an id! Arguments C<description> and C<deleted> are optional but at least one of these two have to be supplied.

Expects arguments to be supplied in C<< key => value >> pairs:

    $obj->setDamageDescriptions( id => 1, description => "my new description", deleted => 1 );

Returns TRUE if database update is successful. Returns FALSE if database update fails and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>. 

=head2 deleteDamageDescription( $id_nr )

Method for 'deleting' damage descriptions. It actually sets column C<deleted> to 1 (TRUE).

It's mandatory to supply an id: 

    $obj->deleteDamageDescription( 1 );

Returns TRUE if database update ('deletion' of damage description) is successful. Returns FALSE if database update fails and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

Default options must be 'name => value' pairs (odd number supplied)

When a HASH is expected as argument, but not given a method will set this message. You should check argument input of methods. 

=item *

I<Update failed, corresponding id not found in database.>

This can be caused when setDamageDescription() wants to update a record that does not exist. 
You should check if argument C<id> has been specified. The method uses this in its WHERE clause.

=back

=cut

1;
