# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Configuration::CVE;

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

sub addCVE {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->addObject( 'identifier_description', \%inserts ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setCVE {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{identifier} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $identifier = delete( $settings{identifier} );
	if ( $self->{dbh}->setObject( 'identifier_description', { identifier => $identifier }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getCVE {
	my ( $self, %where ) = @_;

	my $offset = ( defined( $where{offset} ) ) ? delete $where{offset} : undef;
	my $limit  = ( $where{limit} ) ? delete $where{limit} : undef;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'identifier_description', "identifier, description, custom_description, TO_CHAR(published_date, 'DD-MM-YYYY') AS published_date, TO_CHAR(modified_date, 'DD-MM-YYYY') AS modified_date", \%where, 'identifier ASC' );

	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	$stmnt .= ( defined( $offset ) && defined( $limit ) ) ? ' OFFSET ' . $offset  : '';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @cveList;
	while ( $self->{dbh}->nextRecord() ) {
		push @cveList, $self->{dbh}->getRecord();
	}
	
	return \@cveList;
}

sub getCVECount {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'identifier_description', 'COUNT(*) AS cnt', \%where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	return $self->{dbh}->fetchRow()->{cnt};
}
1;

=head1 NAME

Taranis::Configuration::CVE

=head1 SYNOPSIS

  use Taranis::Configuration::CVE;

  my $obj = Taranis::Configuration::CVE->new( $oTaranisConfig );

  $obj->getCVE( %where );

  $obj->addCVE( %cve );

  $obj->setCVE( %cve );

  $obj->getCVECount( %where );

=head1 DESCRIPTION

CRUD functionality for CVE (description).

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Configuration::CVE> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Configuration::CVE->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 getCVE( %where )

Retrieves a list of CVEs. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

identifier: string

=item *

description: string

=item *

published_date: date string

=item *

modified_date: date string

=item *

custom_description: string

=back

    $obj->getCVE( identifier => 'CVE-2014-0001' );

Returns an ARRAY reference.

=head2 addCVE( %cve )

Adds an CVE.

    $obj->addCVE( description => 'CVE description...', published_date => '20141104', modified_date => '20141104', identifier => 'CVE-2014-0001' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setCVE( %cve )

Updates an CVE. Key C<identifier> is mandatory.

    $obj->setCVE( identifier => 'CVE-2014-0001', custom_description => 'Comments or translations are welcome...' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getCVECount( %where )

Retrieves a CVE count. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

identifier: string

=item *

description: string

=item *

published_date: date string

=item *

modified_date: date string

=item *

custom_description: string

=back

If successful returns the number of CVEs found. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setCVE() when C<identifier> is not set.
You should check C<identifier> settings. They cannot be 0 or undef!

=item *

I<Database error, please check log for info> or I<Database error. (Error cannot be logged because logging is turned off or is not configured correctly)>

Is caused by a database syntax or input error. 
If syslog has been setup correctly the exact SQL statement and bindings should be visible in the configured syslog.

=back

=cut
