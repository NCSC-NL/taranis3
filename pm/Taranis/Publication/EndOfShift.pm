# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication::EndOfShift;

use strict;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Publication;
use Date::Parse;
use DateTime;
use Encode;
use SQL::Abstract::More;
use POSIX qw( strftime mktime );

sub new {
	my ( $class, %args ) = @_;

	my $oTaranisConfig = ( exists( $args{config} ) ) ? $args{config} : Taranis::Config->new();
	my $oTaranisPublication = Taranis::Publication->new();
	my $typeName = Taranis::Config->new( $oTaranisConfig->{publication_templates} )->{eos}->{email};
	my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};

	my $self = {
		dbh => Database,
		sql => Sql,
		config => $oTaranisConfig,
		typeId => $typeId
	};
	
	return( bless( $self, $class ) );
}

sub getEndOfShiftSendingStatus {
	my ( $self ) = @_;
	my ( $currentShift, $previousShift );

	my $sortedShifts = $self->sortShifts();
	foreach my $shift ( @$sortedShifts ) {
		$currentShift = $shift if ( $shift->{isCurrentShift} );
		$previousShift = $shift if ( $shift->{isPreviousShift} );
	}
	
	$previousShift = $sortedShifts->[@$sortedShifts -1] if ( !$previousShift );

	my $nowTime = mktime( localtime() );

	my $stmnt = "SELECT p.published_on FROM publication AS p "
		. "JOIN publication_endofshift AS eos ON eos.publication_id = p.id "
		. "WHERE eos.timeframe_end BETWEEN ? AND ? "
		. "AND p.status = 3 ORDER BY published_on DESC LIMIT 1";
	
	my %results;
	$self->{dbh}->prepare( $stmnt );
	for ( { what => 'current', 'shift' => $currentShift }, { what => 'previous', 'shift' => $previousShift} ) {
		if ( $_->{'shift'} ) {
			# add one minute to shift start time
			my $shiftStartFormatted = strftime( '%Y%m%d %H%M', localtime($_->{'shift'}->{startTime} + 60 ) );
			
			# one hour is added to the shift end time, which allows the user to extend his shift with one hour
			my $shiftEndFormatted = strftime( '%Y%m%d %H%M', localtime($_->{'shift'}->{endTime} + 3600 ) );
			
			$self->{dbh}->executeWithBinds( $shiftStartFormatted, $shiftEndFormatted );
			my $record = $self->{dbh}->fetchRow();
			
			$results{$_->{what}}->{lastPublication} = ( $record ) ? $record->{published_on} : undef;
		}
	}

	if ( $results{previous}->{lastPublication} ) {
		$results{previous}->{status} = 'green';
	} elsif ( mktime( localtime($previousShift->{endTime} + 3600 ) ) > $nowTime ) {
		$results{previous}->{status} = 'orange';
	} else {
		$results{previous}->{status} = 'red';
	}
	
	# if there is no current shift (in case of non-24/7 shifts) or if the EoS for the current shift has been sent
	if ( !$currentShift || $results{current}->{lastPublication}  ) {
		$results{current}->{status} = 'green';
	} else {
		if ( $nowTime > $currentShift->{redTime} ) {
			$results{current}->{status} = 'red';
		} elsif ( $nowTime > $currentShift->{orangeTime} ) {
			$results{current}->{status} = 'orange';
		} else {
			$results{current}->{status} = 'green';
		}
	}
	
	return \%results;
}

sub getLatestTimeframeEndOfPublishedEOS {
	my ( $self ) = @_;

	my $stmnt =
"SELECT eos.timeframe_end 
FROM publication_endofshift AS eos
JOIN publication AS p ON p.id = eos.publication_id
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
		$oTaranisTagging->removeItemTag( $id, "publication_endofshift" );

		my ( $stmnt, @bind ) = $self->{sql}->delete( "publication_endofshift", { id => $id } );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	};

	return 1;
}

sub sortShifts {
	my ( $self ) = @_;
	my ( $currentShift, $previousShift );
	
	my $nowTime = mktime( localtime() );
	my $oneDayTime = 86400;
	
	# sort the shifts according to earliest end time first
	my @sortedShifts = sort { $a->{end} <=> $b->{end} } @{ $self->{config}->{shifts}->{'shift'} };
	
	# figure out what shift is the current shift and what are the previous shifts
	foreach my $sortedShiftIndex ( 0 .. $#sortedShifts ) {
		
		my $shift = $sortedShifts[$sortedShiftIndex];
		$shift->{isCurrentShift} = 0;
		$shift->{isPreviousShift} = 0 if ( !exists( $shift->{isPreviousShift} ) );
		
		my ( $startTime, $endTime );
		$shift->{$_.'TimeCalc'} = time() for qw( start end orange red);
		
		if ( $shift->{start} > strftime( '%H%M', localtime() ) ) {
			# this shift is a previous shift which started yesterday
			
			$shift->{'startTimeCalc'} -= $oneDayTime;
			
			for ( qw( end orange red ) ) {
				# if start hours < end/orange/red hours then end/orange/red is also yesterday
				$shift->{$_.'TimeCalc'} -= $oneDayTime if ( $shift->{start} < $shift->{$_} );
			}
		} elsif ( $shift->{start} > $shift->{end} ) {
			# shift ends next day
			if ( strftime( '%H%M', localtime() ) < $shift->{end} ) {
				# startdate is yesterday
				$shift->{'startTimeCalc'} -= $oneDayTime;
			} else {
				# enddate is tomorrow
				$shift->{'endTimeCalc'} += $oneDayTime;
			}
			
			for ( qw(orange red) ) {
				# if hours now > orange hours/red hours then orange/red is tomorrow
				$shift->{$_.'TimeCalc'} += $oneDayTime if ( strftime( '%H%M', localtime() ) > $shift->{$_} );
			}
		}
		
		# create 'startTime', 'endTime', 'orangeTime' and 'redTime' we can use to compare with $nowTime
		for ( qw( start end orange red ) ) {
			$shift->{$_.'Time'} = mktime( 
				0, 								# second
				substr( $shift->{$_}, 2, 2 ), 	# minute
				substr( $shift->{$_}, 0, 2 ), 	# hour
				[ localtime( $shift->{$_.'TimeCalc'} ) ]->[3], # day
				[ localtime( $shift->{$_.'TimeCalc'} ) ]->[4], # month
				[ localtime( $shift->{$_.'TimeCalc'} ) ]->[5]  # year
			);
		}
		
		# nowTime is between startTime and endTime of $shift we got the current shift
		if ( $shift->{startTime} <= $nowTime && $shift->{endTime} >= $nowTime ) {
			$shift->{isCurrentShift} = 1;
			
			# we can set the previous shift because we sorted the shifts
			$sortedShifts[$sortedShiftIndex - 1]->{isPreviousShift} = 1;
		}
	}
	
	return \@sortedShifts;
}

1;

=head1 NAME

Taranis::Publication::EndOfShift

=head1 SYNOPSIS

  use Taranis::Publication::EndOfShift;

  my $obj = Taranis::Publication::EndOfShift->new( config => $oTaranisConfig );

  $obj->deletePublication( $id, $oTaranisPublication );

  $obj->getEndOfShiftSendingStatus();

  $obj->getLatestTimeframeEndOfPublishedEOS();

  $obj->sortShifts();

=head1 DESCRIPTION

Several End-of-Shift specific functions.

=head1 METHODS

=head2 new( config => $oTaranisConfig )

Constructor of the C<Taranis::Publication::EndOfShift> module. An object instance of C<Taranis::Config>, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Publication::EndOfShift->new( config => $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Stores the type ID of eos email:

    $obj->{typeId}

Returns the blessed object.

=head2 deletePublication( $id, $oTaranisPublication )

Will delete an End-of-Shift and remove the associated tags.

If successful returns TRUE.

=head2 getEndOfShiftSendingStatus()

Retrieves the sending status of the End-of-Shift publication for the current and previous shift.

The helper sub sortShifts() determines what is the current shift and what is de previous shift.

In taranis.conf.xml under <shifts>, each <shift> has a <orange> tag and <red> tag which is used for orange time and red time.

The statuscolor indicates if the End-Of-Shift has already been sent (status=green), 
if the End-Of-Shift has not been sent and is passed the 'orange' time,
if the End-Of-Shift has not been sent and is passed the 'red' time,

Returns a HASH containing C<< { current => { status => 'green', lastPublication => '11:00 01-01-2014' }, previous => {...} } >>.

=head2 getLatestTimeframeEndOfPublishedEOS()

Retrieves the timeframe end time of the last published End-of-Shift.

=head2 softShifts()

Sorts the shifts which are configured in taranis.conf.xml according to earliest end time first.
Also sets flags for current shift 'isCurrentShift' and previous shift 'isPreviousShift'. 

Returns an array reference with the sorted shifts.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
