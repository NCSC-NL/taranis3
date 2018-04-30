# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Configuration::CVETemplate;

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

sub addCVETemplate {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $cveTemplateID = $self->{dbh}->addObject( 'cve_template', \%inserts, 1 ) ) {
		return $cveTemplateID;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setCVETemplate {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	if ( $self->{dbh}->setObject( 'cve_template', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getCVETemplates {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'cve_template', "*", \%where, 'description DESC' );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @templates;
	while ( $self->{dbh}->nextRecord() ) {
		push @templates, $self->{dbh}->getRecord();
	}
	
	return \@templates;
}

sub deleteCVETemplate {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	if ( $self->{dbh}->deleteObject( 'cve_template', { id => $id } ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

1;

=head1 NAME

Taranis::Configuration::CVETemplate

=head1 SYNOPSIS

  use Taranis::Configuration::CVETemplate;

  my $obj = Taranis::Configuration::CVETemplate->new( $oTaranisConfig );

  $obj->getCVETemplate( %where );

  $obj->addCVETemplate( %cveTemplate );

  $obj->setCVETemplate( %cveTemplate );

  $obj->deleteCVETemplate( $id );

=head1 DESCRIPTION

CRUD functionality for CVE Template.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Configuration::CVETemplate> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Configuration::CVETemplate->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 getCVETemplate( %where )

Retrieves a list of CVE templates. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

description: string

=item *

template: string

=back

    $obj->getCVETemplate( description => 'my first cve template' );

Returns an ARRAY reference.

=head2 addCVETemplate( %cveTemplate )

Adds an CVE template.

    $obj->addCVETemplate( description => 'my first cve template', template => 'some template text' );

If successful returns the ID of the newly added CVE template. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setCVETemplate( %cveTemplate )

Updates an CVE template. Key C<id> is mandatory.

    $obj->setCVE( id => 3, description => 'my second cve template', template => 'some updated template text' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteCVETemplate( $id )

Deletes an CVE template.

    $obj->deleteCVETemplate( 6 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setCVETemplate() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
