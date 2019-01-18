# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Configuration::CVEFile;

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

sub addCVEFile {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	$inserts{name} = 'cve_description';
	
	if ( $self->{dbh}->addObject( 'download_files', \%inserts ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setCVEFile {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{file_url} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $url = delete( $settings{file_url} );
	if ( $self->{dbh}->setObject( 'download_files', { file_url => $url }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getCVEFile {
	my ( $self, %where ) = @_;
	
	$where{name} = 'cve_description';
	my ( $stmnt, @binds ) = $self->{sql}->select( 'download_files', "*", \%where, 'file_url' );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @cveFileList;
	while ( $self->{dbh}->nextRecord() ) {
		push @cveFileList, $self->{dbh}->getRecord();
	}
	
	return \@cveFileList;
}

sub deleteCVEFile {
	my ( $self, $url ) = @_;
	undef $self->{errmsg};
	
	if ( $self->{dbh}->deleteObject( 'download_files', { file_url => $url } ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

1;

=head1 NAME

Taranis::Configuration::CVEFile

=head1 SYNOPSIS

  use Taranis::Configuration::CVEFile;

  my $obj = Taranis::Configuration::CVEFile->new( $oTaranisConfig );

  $obj->getCVEFile( %where );

  $obj->addCVEFile( %cveFile );

  $obj->setCVEFile( %cveFile );

  $obj->deleteCVEFile( $url );

=head1 DESCRIPTION

CRUD functionality for CVE download file.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Configuration::CVEFile> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Configuration::CVEFile->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 getCVEFile( %where )

Retrieves a list of CVE download files. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

file_url: string

=item *

last_change: string

=item *

name: string (='cve_description')

=item *

filename: string

=back

    $obj->getCVEFile( name => 'cve_description' );

Returns an ARRAY reference.

=head2 addCVEFile( %cveFile )

Adds an CVE download file.

    $obj->addCVEFile( file_url => 'http://cve.mitre.org/data/downloads/allitems-cvrf-year-2014.xml', filename => 'allitems-cvrf-year-2014.xml' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setCVEFile( %cveFile )

Updates an CVE download file. Key C<file_url> is mandatory.

    $obj->setCVE( file_url => 'http://cve.mitre.org/data/downloads/allitems-cvrf-year-2014.xml');

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteCVEFile( $url )

Deletes an CVE download file.

    $obj->deleteCVEFile( 'http://cve.mitre.org/data/downloads/allitems-cvrf-year-2014.xml' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setCVEFile() when C<file_url> is not set.
You should check C<file_url> setting. They cannot be 0 or undef!

=back

=cut
