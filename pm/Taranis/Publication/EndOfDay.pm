# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication::EndOfDay;

use strict;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql Config);
use Taranis::Publication;

use Date::Parse;
use DateTime;
use Encode;
use SQL::Abstract::More;
use POSIX;

sub new {
	my ($class) = @_;

	my $oTaranisPublication = Taranis::Publication->new();

	my $self = bless +{
		dbh => Database,
		sql => Sql,
		config => Config,
		typeId => $oTaranisPublication->getPublicationTypeId(eod => 'email'), 
	}, $class;

	$self;
}

sub getEndOfDaySendingStatus {
	my ( $self ) = @_;

	my $oTaranisConfig = Config;
	
	my $orangeTime = $oTaranisConfig->{publication_eod_orange};
	my $redTime = $oTaranisConfig->{publication_eod_red};
	my $status = undef;
	my $lastPublication = undef;
	
	if ( $orangeTime =~ /^([01][0-9]|2[0-4])[0-5][0-9]$/ && $redTime =~ /^([01][0-9]|2[0-4])[0-5][0-9]$/ ) {
	
		my $oTaranisPublication = Taranis::Publication->new();

		my $publicationDateTime = $oTaranisPublication->getLatestPublishedPublicationDate( type => $self->{typeId});

		my ( $publicationDate, $publicationTime);

		my $when = $publicationDateTime->{published_on_str}
			or return;

		if($when) {
			my ($publicationDate, $publicationTime) = split(' ', $when);
			my $nowTime = strftime( '%H%M', localtime( time() ) );

			my $nowDateTimeObj = DateTime->today();
			my $publicationDateTimeObj = DateTime->new(
				year => substr( $publicationDate, 0, 4 ),
				month => substr( $publicationDate, 4, 2 ),
				day => substr( $publicationDate, 6, 2 ),
			);
		
			my $offsetInDays = $nowDateTimeObj->delta_days( $publicationDateTimeObj )->in_units('days');
		 
			if ( !$publicationDate || $offsetInDays == 1 ) {
				# there is no published publication or last published publication was yesterday
				if ( $nowTime > $redTime ) {
					$status = 'red';
				} elsif ( $nowTime > $orangeTime ) {
					$status = 'orange';
				} else {
					$status = 'green';
		    	}
		    	
			} elsif ( $offsetInDays > 1 ) {
				# last published publication was more than 1 day ago
				$status = 'red';
			} else {
				# last published publication was of today
				$status = 'green';    	
			}
			
			my $year = substr( $when, 0, 4 );
			my $month = substr( $when, 4, 2 );
			my $dayOfMonth = substr( $when, 6, 2 );
			my $hour = substr( $when, 9, 2 );
			my $minute = substr( $when, 11, 2 );
			$lastPublication = "$hour:$minute $dayOfMonth-$month-$year";
			
		} else {
			$status = 'red';
		} 
	}
	
	return { status => $status, lastPublication => $lastPublication};
}

sub getLatestTimeframeEndOfPublishedEOD {
	my ( $self ) = @_;

	my $stmnt =
"SELECT eod.timeframe_end 
FROM publication_endofday AS eod
JOIN publication AS p ON p.id = eod.publication_id
WHERE p.status = 3 AND p.type = ?
ORDER BY p.published_on DESC
LIMIT 1";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( $self->{typeId} );

	return $self->{dbh}->fetchRow();
}

sub deletePublication {
	my ( $self, $id, $oTaranisPublication ) = @_;

	my $oTaranisTagging = Taranis::Tagging->new();

	withTransaction {
		$oTaranisTagging->removeItemTag( $id, "publication_endofday" );

		my ( $stmnt, @bind ) = $self->{sql}->delete( "publication_endofday", { id => $id } );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	};

	return 1;
}

1;

=head1 NAME

Taranis::Publication::EndOfDay

=head1 SYNOPSIS

  use Taranis::Publication::EndOfDay;

  my $obj = Taranis::Publication::EndOfDay->new( config => $oTaranisConfig );

  $obj->deletePublication( $id, $oTaranisPublication );

  $obj->getEndOfDaySendingStatus();

  $obj->getLatestTimeframeEndOfPublishedEOD();

=head1 DESCRIPTION

Several End-of-Day specific functions.

=head1 METHODS

=head2 new( config => $oTaranisConfig )

Constructor of the C<Taranis::Publication::EndOfDay> module. An object instance of C<Taranis::Config>, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Publication::EndOfDay->new( config => $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Stores the type ID of eod email:

    $obj->{typeId}

Returns the blessed object.

=head2 deletePublication( $id, $oTaranisPublication )

Will delete an End-of-Day and remove the associated tags.

If successful returns TRUE.

=head2 getEndOfDaySendingStatus()

Retrieves the sending status of the End-of-Day publication.

The statuscolor indicates if the End-Of-Day has already been sent today (status=green), 
if the End-Of-Day has not been sent and is passed the 'orange' time (setting C<publication_eod_orange>) in Taranis configuration),
if the End-Of-Day has not been sent and is passed the 'red' time (setting C<publication_eod_red>) in Taranis configuration),

Returns a HASH containing C<< { status => 'green', lastPublication => '11:00 01-01-2014' } >>.

=head2 getLatestTimeframeEndOfPublishedEOD()

Retrieves the timeframe end time of the last published End-of-Day.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
