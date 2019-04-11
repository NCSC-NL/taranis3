# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Cluster;

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
	return $self->{dbh}->nextRecord();
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord();		
}

sub getCluster {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
	my @clusters; 
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "cluster cl", "cl.*, ca.name", \%where, "ca.name, cl.language" );
	
	my %join = ( 'JOIN category ca' => { 'ca.id' => 'cl.category_id ' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		 $self->{errmsg} = $self->{dbh}->{db_error_msg};
		 return ();
	}

	while ( $self->nextObject ) {
		push ( @clusters, $self->getObject );
	}	

	wantarray ? @clusters : $clusters[0];
}

sub setCluster {
  my ( $self, %updates ) = @_;
	undef $self->{errmsg};
  
  my %where = ( id => $updates{id} ); 
  delete $updates{id};
  
	my ( $stmnt, @bind ) = $self->{sql}->update( "cluster", \%updates, \%where );
	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {		
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

sub addCluster {
  my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "cluster", \%inserts );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteCluster {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	my ( $stmnt, @bind ) = $self->{sql}->delete( 'cluster', { id => $id } );
	$self->{dbh}->prepare( $stmnt );
	
	if ( $self->{dbh}->executeWithBinds( @bind) > 0 ) {
		return 1;
	} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		$self->{errmsg} = "Delete failed, corresponding id not found in database.";
		return 0;
	}		
}

1;

=head1 NAME

Taranis::Cluster

=head1 SYNOPSIS

  use Taranis::Cluster;

  my $obj = Taranis::Cluster->new( $objTaranisConfig );

  $obj->addCluster( %cluster );

  $obj->setCluster( %cluster );

  $obj->getCluster( %where );

  $obj->deleteCluster( $clusterID );

  $obj->nextObject();

  $obj->getObject();

=head1 DESCRIPTION

Assess items can be clustered. This module offers CRUD functionality for clusters.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Cluster> module.  An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Cluster->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Returns the blessed object.

=head2 addCluster( %where )

Method for adding a cluster.

    $obj->addCluster( language => 'NL', category_id => 2, threshold => 2.3,	timeframe_hours => 24, recluster => 1 ); 

If successful returns TRUE . If unsuccessful it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setCluster( %cluster )

Method for editing a cluster. Takase C<id> as mandatory argument.

    $obj->setCluster( id => 68, language => 'NL', category_id => 2, threshold => 2.3,	timeframe_hours => 24, recluster => 1 );

Returns TRUE if update is successful. If unsuccessful it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 $obj->getCluster( %where )

Method for retrieval of one or more clusters. 
If no arguments are supplied a list of all clusters will be returned.

    $obj->getCluster( id => 78 );
    
OR

    $obj->getCluster( language => 'NL', category_id => 2 );

OR

    $obj->getCluster();

If only one cluster is found it will return a HASH reference with keys C<id>, C<name> and C<is_enabled>.

If more than one cluster is found it will return an ARRAY of HASHES with mentioned keys.

If a database error occurs it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteCluster( $clusterID )

Method used for deleting a cluster. Parameter C<id> is mandatory.

    $obj->deleteCluster( 67 );

If successful returns TRUE. If unsuccessful returns FALSE and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method like getCluster().

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->getCluster( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Update failed, corresponding id not found in database.> & I<Delete failed, corresponding id not found in database.>

Caused by setCluster() & deleteCluster() when there is no cluster that has the specified cluster id. 
You should check the input parameters. 

=back

=cut
