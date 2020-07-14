# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dossier::Contributor;

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
		config => $config,
	};

	return( bless( $self, $class ) );
}

sub getContributors {
	my ( $self, %where ) = @_;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_contributor dc', 'dc.is_owner, dc.username, dc.dossier_id, u.fullname', \%where, 'u.fullname' ); 
	
	my $join = { "JOIN users u" => { "u.username" => "dc.username" } };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	my @contributors;
	while ( $self->{dbh}->nextRecord() ) {
		push @contributors, $self->{dbh}->getRecord();
	}
	return \@contributors;
}

sub addContributor {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->addObject( 'dossier_contributor', \%inserts, 0 ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}
sub setContributor {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{dossier_id} ) || !exists( $settings{username} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $dossierID = delete( $settings{dossier_id} );
	my $username = delete( $settings{username} );
	
	if ( $self->{dbh}->setObject( 'dossier_contributor', { username => $username, dossier_id => $dossierID }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub removeContributor {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->deleteObject( 'dossier_contributor', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

1;

=head1 NAME

Taranis::Dossier::Contributor

=head1 SYNOPSIS

  use Taranis::Dossier::Contributor;

  my $obj = Taranis::Dossier::Contributor->new( $oTaranisConfig );

  $obj->getContributors( %where );

  $obj->addContributor( %contributor );

  $obj->setContributor( %contributor );

  $obj->removeContributor( %where );

=head1 DESCRIPTION

CRUD functionality for dossier contributor.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dossier::Contributor> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dossier::Contributor->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 getContributors( %where )

Retrieves a list of contributors. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

dossier_id: number

=item *

'dc.username': string

=item *

is_owner: boolean

=back

    $obj->getContributors( dossier_id => 3, 'dc.username' => 'someuser', is_owner => 1 );

Returns an ARRAY reference.

=head2 addContributor( %contributor )

Adds a contributor.

    $obj->addContributor( dossier_id => 3, 'dc.username' => 'someuser', is_owner => 1 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setContributor( %contributor )

Updates a contributor. Keys C<username> and C<dossier_id> are mandatory.

    $obj->setContributor( ossier_id => 3, 'dc.username' => 'someuser', is_owner => 0 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 removeContributor( %where )

Deletes a contributor.

    $obj->removeContributor( username => 'someuser' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setContributor() when C<username> or C<dossier_id> are not set.
You should check C<username> and C<dossier_id> settings. They cannot be 0 or undef!

=back

=cut
