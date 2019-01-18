# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::Administration;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};

	return( bless( $self, $class ) );
}

sub addCollector {
	my ( $self, %collectorSettings ) = @_;
	undef $self->{errmsg};

	$collectorSettings{secret} = $self->createSecret();
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "collector", \%collectorSettings );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return $collectorSettings{secret};
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getCollectors {
	my ( $self, %where) = @_;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'collector', '*', \%where, 'description' );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my @collectors;
	while ( $self->{dbh}->nextRecord() ) {
		push @collectors, $self->{dbh}->getRecord();
	}

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		 $self->{errmsg} = $self->{dbh}->{db_error_msg};
		 return 0;
	} else {
		return @collectors;
	}
}

sub setCollector {
	my ( $self, %update ) = @_;
	undef $self->{errmsg};

	return 0 if ( $update{id} !~ /^\d+$/ );
	
	my %where = ( id => $update{id} ); 
	delete $update{id};

	my ( $stmnt, @bind ) = $self->{sql}->update( "collector", \%update, \%where );
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

sub deleteCollector {
	my ( $self, $col_id ) = @_;
	my $dbh = $self->{dbh};

	if($dbh->checkIfExists( { collector_id => $col_id }, "sources")) {
		$self->{errmsg} = 'Cannot delete collector: still used by sources.';
		return 0;
	}

	my ($stmnt1, @bind1) = $dbh->{sql}->delete(statistics_collector =>
		{collector_id => $col_id} );
    $dbh->prepare($stmnt1);
	$dbh->executeWithBinds(@bind1);

	my ($stmnt2, @bind2) = $dbh->{sql}->delete(collector => {id => $col_id});
    $dbh->prepare($stmnt2);
	$dbh->executeWithBinds(@bind2);
	1;
}

sub createSecret {
	my ( $self ) = @_;
	my $secret = '';
	my @chars = ("A".."Z", "a".."z", 0..9);
	$secret .= $chars[rand @chars] for 1..20;	
	
	return $secret;
}

1;

=head1 NAME

Taranis::Collector::Administration - CRUD functionality for collector

=head1 SYNOPSIS

  use Taranis::Collector::Aministration;

  my $obj = Taranis::Collector::Aministration->new( $oTaranisConfig );

  $obj->addCollector( description => $collector_description, ip => $ip_address );

  $obj->setCollector( id => $collector_id, description => $collector_description, ip => $ip_address, secret => $collector_sectret );

  $obj->getCollectors( id => $collector_id, description => $collector_description, ip => $ip_address, secret => $collector_sectret );

  $obj->deleteCollector( $collector_id );

  $obj->createSecret();

=head1 DESCRIPTION

A collector (/opt/taranis/collector.pl) only works when it has been added to the main Taranis installation.
Adding a collector can be done on the 'configuration' page. 
When adding a collector, a secret is created which needs to be added to the configuration file of that particular collector. 
This module can be used to add, edit, retrieve and delete collectors.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Collector::Administration> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Collector::Administration->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Returns the blessed object.

=head2 addCollector( description => $collector_description, ip => $ip_address );

Adds a collector to the main Taranis installation. It will create and return the collector secret which needs to be set in the collector configuration file.

    $obj->addCollector( description => 'Main Collector', ip => '127.0.0.1' );

Returns the collector secret if successful. If unsuccessful it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setCollector( id => $collector_id, description => $collector_description, ip => $ip_address, secret => $collector_sectret )

Changes collector settings. C<id> is mandatory argument.

    $obj->setCollector( id => 34, description => 'Main Collector', ip => '127.0.0.1', secret => 'w2h9rrRsvpKrJkjIrrJU' );

Returns TRUE if successful. If unsuccessful it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 $obj->getCollectors( id => $collector_id, description => $collector_description, ip => $ip_address, secret => $collector_sectret )

Retrieves a list of collectors, which can be filtered by setting one or more arguments.
If no arguments are supplied a list of all collectors will be returned.

    $obj->getCollectors( id => 34 );
    
OR

    $obj->getCollectors( ip => '127.0.0.1' );

OR

    $obj->getCollectors();

If on or more than collectors are found it will return an ARRAY of HASHES.

If a database error occurs it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteCollector( $collector_id )

Deletes a collector. An collector ID is mandatory.

    $obj->deleteCollector( 67 );

Before deleting the specified collector it will check if the collector is referenced in table C<sources>. 

If the collector is referenced it will return FALSE. 
It will also return FALSE if a database error occurs, which will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
If successful it will return TRUE. 

=head2 createSecret()

Creates a new collector secret and returns it

    $obj->createSecret();

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Update failed, corresponding id not found in database.> & I<Delete failed, corresponding id not found in database.>

Caused by setCollector() & deleteCollector() when there is no collector that has the specified collector id.
You should check why an non-existent collector id is supplied. 

=item * 

I<Cannot delete collector, because collector is in use by one or more sources.>

Caused by deleteCollector() when you're trying to delete a collector which is still referenced in the table C<sources>.
This is not possible because the collector id is a foreign key in table C<sources>.

=back

=cut
