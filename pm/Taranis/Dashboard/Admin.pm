# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Admin;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		tpl => 'dashboard_admin.tt',
		tpl_minified => undef
	};
	return( bless( $self, $class ) );
}

sub latestUserActions {
	my ( $self ) = @_;
	
	my $stmnt = 
		"SELECT ua.*, to_char(date, 'dy HH24:MI') AS datetime, u.fullname"
		. " FROM user_action AS ua" 
		. " LEFT JOIN users AS u ON u.username = ua.username"
		. " ORDER BY date DESC LIMIT 20;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	my @userActions;
	while ( $self->{dbh}->nextRecord() ) {
		push @userActions, $self->{dbh}->getRecord();
	}
	return \@userActions;
}

1;

=head1 NAME

Taranis::Dashboard::Admin

=head1 SYNOPSIS

  use Taranis::Dashboard::Admin;

  my $obj = Taranis::Dashboard::Admin->new( $oTaranisConfig );

  $obj->latestUserActions();

=head1 DESCRIPTION

Controls the content of the Admin section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Admin> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Admin->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Sets the template of the Admin section of the dashboard:

    $obj->{tpl}

Sets the template of the Admin section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 latestUserActions()

Retrieves the last 20 entries of table C<user_action>.

Returns an ARRAY reference of user actions.

=cut
