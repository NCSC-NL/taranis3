# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Publish;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		tpl => 'dashboard_publish.tt',
		tpl_minified => 'dashboard_publish_minified.tt'
	};
	return( bless( $self, $class ) );
}

sub numberOfApprovedPublications {
	my ( $self ) = @_;
	my $stmnt = "SELECT COUNT(*) AS count FROM publication WHERE status = 2;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return $self->{dbh}->fetchRow()->{count};	
}

1;

=head1 NAME

Taranis::Dashboard::Publish

=head1 SYNOPSIS

  use Taranis::Dashboard::Publish;

  my $obj = Taranis::Dashboard::Publish->new( $oTaranisConfig );

  $obj->numberOfApprovedPublications();

=head1 DESCRIPTION

Controls the content of the Publish section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Publish> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Publish->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Sets the template of the Publish section of the dashboard:

    $obj->{tpl}

Sets the template of the Publish section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 numberOfApprovedPublications()

Counts the number of publications with status 'approved'.

Returns a number.

=cut
