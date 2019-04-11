# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dossier;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Tie::IxHash;

my %DOSSIER_STATUS = (
	'ACTIVE' => 1,
	'INACTIVE' => 2,
	'ARCHIVED' => 3,
	'JOINED' => 4
);

my %REVERSE_DOSSIER_STATUS = reverse %DOSSIER_STATUS;

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

sub getDossiers {
	my ( $self, %where ) = @_;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier AS d', 'd.*, u.fullname, u.mailfrom_email', \%where, 'd.status, d.description' ); 
	
	my %join = ( 'LEFT JOIN users AS u' => { 'u.username' => 'd.reminder_account' } );
	
	if ( exists( $where{'dc.username'} ) ) {
		$join{'JOIN dossier_contributor AS dc'} = { 'dc.dossier_id' => 'd.id' };
	}
	
	if ( exists( $where{tag_id} ) ) {
		$join{'JOIN tag_item AS ti'} = { 'ti.item_id' => 'd.id::varchar(50)' };
	}
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt ) if keys %join;

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @dossiers;
	while ( $self->{dbh}->nextRecord() ) {
		push @dossiers, $self->{dbh}->getRecord();
	}
	return \@dossiers;
}

sub addDossier {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $dossierID = $self->{dbh}->addObject( 'dossier', \%inserts, 1 ) ) {
		return $dossierID;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setDossier {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $dossierID = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'dossier', { id => $dossierID }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}	
}

sub getDateLatestActivity {
	my ( $self, $dossierID ) = @_;

	if ( $dossierID !~ /^\d+$/ ) {
		$self->{errmsg} = 'Invalid parameter!';
		return 0;
	}
	my @where = (
		{ 'di.dossier_id' => $dossierID },
		{ 'di2.dossier_id' => $dossierID },
	);
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note AS dn', 'max(dn.created) AS latest_activity', \@where );

	my %join = (
		'LEFT JOIN dossier_item AS di' => { 'di.id' => 'dn.dossier_item_id' },
		'LEFT JOIN dossier_item AS di2' => { 'di2.note_id' => 'dn.id' }
	);
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt ) if keys %join;
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my $result = $self->{dbh}->fetchRow();
	
	return $result->{latest_activity};
}

sub getDossierStatuses { return \%REVERSE_DOSSIER_STATUS ; }

1;

=head1 NAME

Taranis::Dossier

=head1 SYNOPSIS

  use Taranis::Dossier;

  my $obj = Taranis::Dossier->new( $oTaranisConfig );

  $obj->addDossier( %dossier );

  $obj->getDateLatestActivity( $dossierID );

  $obj->getDossiers( %where );

  $obj->getDossierStatuses();

  Taranis::Dossier::->getDossierStatuses();

  $obj->setDossier( %dossier );

=head1 DESCRIPTION

Module for managing dossiers.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dossier> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dossier->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 addDossier( %dossier )

Adds a new dossier. 

    $obj->addDossier( description => 'some dossier name', reminder_account => 'someuser', reminder_interval => '2 days' );

If successful returns the dossier ID of the newly added dossier.
If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getDateLatestActivity( $dossierID )

Retrieves the timestamp of the newest dossier item.

    $obj->getDateLatestActivity( 53 );

Returns a timestamp.

=head2 getDossiers( %where )

Retrieves one or more dossier(s).

    $obj->getDossiers();

OR

    $obj->getDossiers( id => 35 );

OR

    $obj->getDossiers( status => 2, description => 'dossier %' );

Returns an ARRAY reference.

=head2 getDossierStatuses()

Retrieves the dossier status mapping.

  $obj->getDossierStatuses();

OR

    Taranis::Dossier::->getDossierStatuses();

Returns a HASH reference.

=head2 setDossier( %dossier )

Updates a dossier. Parameter C<id> is mandatory.

    $obj->setDossier( id => 34, status => 3, description => 'my updated dossier' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setDossier() when C<id> is not set.
You should check C<id> setting.

=item *

I<Invalid parameter!>

Caused by getDateLatestActivity() when parameter C<$dossierID> is not a number.
You should check parameter C<$dossierID>.

=back

=cut
