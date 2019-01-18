# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use strict;

my $MINIFIED = 1;
my $MAXIMIZED = 2;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		dbh => Database,
		sql => Sql,
		errmsg => undef,
		minified => $MINIFIED,
		maximized => $MAXIMIZED 
	};
	
	return( bless( $self, $class ) );
}

sub setDashboardItems {
	my ( $self, %args ) = @_;
	
	my %where = ( type => $args{type} );
	my %update = ( html => $args{html}, json => $args{json} );
	
	my ( $stmnt, @bind ) = $self->{sql}->update( 'dashboard', \%update, \%where );	

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
		$self->{errmsg} = $self->{dbh}->{db_error_msg} || "Action failed, corresponding id not found in database.";
		return 0;
	}	
}

sub getDashboard {
	my ( $self, $type ) = @_;
	undef $self->{errmsg};

	my %where = ( type => $type );

	my ( $stmnt, @bind ) = $self->{sql}->select( 'dashboard', '*', \%where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	return $self->{dbh}->fetchRow();
}

1;

=head1 NAME

Taranis::Dashboard - Get and set (minified) dashboard data

=head1 SYNOPSIS

  use Taranis::Dashboard;

  my $obj = Taranis::Dashboard->new( $oTaranisConfig );

  $obj->getDashboard( $dashboardType );

  $obj->setDashboardItems( type => $dashboardType, html => $html, json => $json );

=head1 DESCRIPTION

Getter and setter for dashboard and minified dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the type ID for dashboard and minified dashboard:

    $obj->{maximized}; # typically 2

    $obj->{minified}; # typically 1
 
Returns the blessed object.

=head2 getDashboard( $dashboardType )

Retrieves the dashboard or the minified dashboard data, depending on the C<$dashboardType>.

    $obj->getDashboard( 2 );

Returns an HASH.

=head2 setDashboardItems( type => $dashboardType, html => $html, json => $json )

Update the dashboard or minified dashboard, depending on the C<$dashboardType>.

    $obj->setDashboardItems( type => 2, html => '<div>...</div>', json => '{}' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Action failed, corresponding id not found in database.>

Caused by setDashboardItems() when there is no dashboard that has the specified dashboard type id. 
You should check the input parameters.

=back

=cut
