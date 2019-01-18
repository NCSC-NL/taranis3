# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Write;

use strict;
use Taranis::Config;
use Taranis::Publication::EndOfDay;
use Taranis::Publication::EndOfShift;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database PublicationEndOfDay);

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		tpl => 'dashboard_write.tt',
		tpl_minified => 'dashboard_write_minified.tt',
		config => $config
	};
	return( bless( $self, $class ) );
}

sub endOfDayStatus {
	my ( $self ) = @_;
	return PublicationEndOfDay->getEndOfDaySendingStatus();
}

sub endOfShiftStatus {
	my ( $self ) = @_;
	my $oTaranisPublicationEndOfShift = Taranis::Publication::EndOfShift->new( $self->{config} );
	return $oTaranisPublicationEndOfShift->getEndOfShiftSendingStatus();
}

sub collectorNotifications {
	my ( $self ) = @_;
	
	my $stmnt = "SELECT error, to_char(time_of_error, 'dy HH24:MI') AS datetime FROM errors WHERE ( error_code = 'C016' OR error_code = 'C015' ) AND time_of_error > NOW() - '1 day'::INTERVAL ORDER BY time_of_error DESC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	my @notifications;
	while ( $self->{dbh}->nextRecord() ) {
		push @notifications, $self->{dbh}->getRecord();
	}
	return \@notifications;
}

1;

=head1 NAME

Taranis::Dashboard::Write

=head1 SYNOPSIS

  use Taranis::Dashboard::Write;

  my $obj = Taranis::Dashboard::Write->new( $oTaranisConfig );

  $obj->endOfDayStatus();

  $obj->endOfShiftStatus();

  $obj->collectorNotifications();

=head1 DESCRIPTION

Controls the content of the Write section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Write> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Write->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Sets the template of the Write section of the dashboard:

    $obj->{tpl}

Sets the template of the Write section of the minified dashboard:

    $obj->{tpl_minified}

Sets the absolute path for the publication template configuration file if C<< $objTaranisConfig >> is set: 

    $obj->{publicationTemplatesConfigFile}

Returns the blessed object.

=head2 endOfDayStatus()

Retrieves timestamp of the last sent End-Of-Day as well as a statuscolor. 
The statuscolor indicates if the End-Of-Day has already been sent today (status=green), 
if the End-Of-Day has not been sent and is passed the 'orange' time (setting C<publication_eod_orange>) in Taranis configuration),
if the End-Of-Day has not been sent and is passed the 'red' time (setting C<publication_eod_red>) in Taranis configuration),

Returns a HASH containing C<< { status => 'green', lastPublication => '11:00 01-01-2014' } >>.

=head2 endOfShiftStatus()

Returns getEndOfShiftSendingStatus() of Taranis::Publication::EndOfShift.

=head2 collectorNotifications()

Retrieves a list of notifications created by the collector.
List contains notifications with error code 'C015' and 'C016'.

Returns an ARRAY reference.

=cut
