# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::ImportCpe;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::SoftwareHardware;
use Tie::IxHash;
use SQL::Abstract::More;
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg 	=> undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub addCpeImportEntry {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "software_hardware_cpe_import", \%inserts );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub isLinked {
	my ( $self, $cpe_id ) = @_;
	undef $self->{errmsg};
	my $stmnt = "SELECT 
	( 
		SELECT COUNT(*) FROM platform_in_publication pl
		JOIN software_hardware sh ON sh.id = pl.softhard_id
		WHERE sh.cpe_id = ? 
	) 
	+
	( 
		SELECT COUNT(*) FROM product_in_publication pr 
		JOIN software_hardware sh ON sh.id = pr.softhard_id
		WHERE sh.cpe_id = ?
	) 
	+
	( 
		SELECT COUNT(*) FROM soft_hard_usage shu
		JOIN software_hardware sh ON sh.id = shu.soft_hard_id
		WHERE sh.cpe_id = ?
	) 
	AS cnt";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( $cpe_id, $cpe_id, $cpe_id );
	
	my $count = $self->{dbh}->fetchRow();
	
	return ( $count ) ? 1 : 0;
}

sub loadCollection {
	my ( $self, %settings ) = @_;
	
	my $limit = delete( $settings{limit} ) if ( exists( $settings{limit} ) );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'software_hardware_cpe_import', '*', \%settings, 'producer, name, version' );
	
	$stmnt .= " LIMIT " . $limit if ( $limit );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @softwareHardware;
	while ( $self->nextObject() ) {
		push @softwareHardware, $self->getObject();
	}
	
	return \@softwareHardware;
}

sub importCpeEntry {
	my ( $self, %import ) = @_;
	
	$import{monitored} = 'f';
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( 'software_hardware', \%import );
	
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}	
}

sub getUniqueProducts {
	my ( $self ) = @_;
	
	my $stmnt = 
"SELECT producer, name, type FROM software_hardware_cpe_import
GROUP BY producer, name, type 
ORDER BY producer, name, type";	

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	my @products;
	
	while ( $self->nextObject() ) {
		push @products, $self->getObject();
	}
	
	return \@products;
}

sub deleteImportEntry {
	my ( $self, %delete ) = @_;
	undef $self->{errmsg};
	
	my $table = ( $delete{table} ) ? delete( $delete{table} ) : 'software_hardware_cpe_import';
	
	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, \%delete );
	
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

sub deleteAllImportEntries {
	my ( $self ) = @_;
	
	my $stmnt = "DELETE FROM software_hardware_cpe_import";
	
	$self->{dbh}->prepare( $stmnt );
	
	if ( $self->{dbh}->executeWithBinds() > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} 	
}

sub nextObject {
    my ($self) = @_;
    return $self->{dbh}->nextRecord;
}

sub getObject {
    my ($self) = @_;
    return $self->{dbh}->getRecord;
}

1;

=head1 NAME

Taranis::ImportCpe

=head1 SYNOPSIS

  use Taranis::ImportCpe;

  my $obj = Taranis::ImportCpe->new( $oTaranisConfig );

  $obj->addCpeImportEntry( %cpeEntry );

  $obj->deleteAllImportEntries();

  $obj->deleteImportEntry( %delete );

  $obj->getUniqueProducts();

  $obj->importCpeEntry( %softwareHardware );

  $obj->isLinked( $cpeID );

  $obj->loadCollection( %searchSettings );

=head1 DESCRIPTION

Support for importing CPE list. Currently only supports CPE version 2.2. 
Please see http://nvd.nist.gov/cpe.cfm for more information on CPE. 

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::ImportCpe> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::ImportCpe->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addCpeImportEntry( %cpeEntry )

Adds an CPE item to the import list, table C<software_hardware_cpe_import>.

    $obj->addCpeImportEntry( name => 'Taranis', producer => 'NCSC', version => '3.2',	type => 'a', cpe_id => 'cpe:/a:ncsc:taranis:3.2', ok_to_import => 1 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteAllImportEntries()

Deletes all import entries so a new import can be done.

    $obj->deleteAllImportEntries();

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteImportEntry( %delete )

Deletes a single CPE import item.

    $obj->deleteImportEntry( id => 98 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getUniqueProducts()

Retrieves a list of unique products from CPE import. Uniqueness is determined by the combination of producer, product name and product type.

    $obj->getUniqueProducts();

Returns an ARRAY reference.

=head2 importCpeEntry( %softwareHardware )

Adds a CPE item to the table C<software_hardware>.

    $obj->importCpeEntry( name => 'Taranis', producer => 'NCSC', version => '3.2',	type => 'a', cpe_id => 'cpe:/a:ncsc:taranis:3.2', deleted => 0); 

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 isLinked( $cpeID )

Checks if C<$cpeID> is linked to a publication or constituent.

    $obj->isLinked( 'cpe:/a:ncsc:taranis:3.2' );

Returns TRUE if the product is linked. Returns FALSE if product is not linked.

=head2 loadCollection( %searchSettings )

Retrieves a list of CPE items from import list. The parameter C<limit> can be used to limit the amount of results.

    $obj->loadCollection( producer => 'ncsc', name => 'Taranis', limit => 10 );

Returns an ARRAY reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Delete failed, corresponding id not found in database.!>

Caused by deleteImportEntry() when no record is found that matches the input parameter criteria.
You should check the input parameter criteria.

=back

=cut
