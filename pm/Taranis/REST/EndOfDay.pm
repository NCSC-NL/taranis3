# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::EndOfDay;

use strict;
use Taranis::Publication::EndOfDay;
use Tie::IxHash;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config PublicationEndOfDay);

Taranis::REST->addRoute(
	route       => qr[^endofday/lastsent/?(?:$|\?)],
	entitlement => 'publication',
	particularizations => [ 'end-of-day (email)', 'end-of-day (email public)' ],
	handler     => \&getLastSentEndOfDay,
);

Taranis::REST->addRoute(
	route       => qr[^endofday/status/?(?:$|\?)],
	entitlement => 'publication',
	particularizations => [ 'end-of-day (email)', 'end-of-day (email public)' ],
	handler     => \&getEndOfDaySendingStatus,
);

my $statusDictionary = Taranis::Publication->getStatusDictionary();

sub getLastSentEndOfDay {
	my (%params) = @_;
	my $dbh = $params{dbh};
	
	my $stmnt = "SELECT eod.*, "
		. "to_char(p.created_on, 'DD-MM-YYYY HH24:MI') AS created, " 
		. "to_char(p.published_on, 'DD-MM-YYYY HH24:MI') AS published, "
		. "p.contents, u1.fullname AS opened_by_fullname, eod.handler, "
		. "eod.first_co_handler, eod.second_co_handler, "
		. "to_char(eod.timeframe_begin, 'Dy DD Mon YYYY HH24:MI - ') ||  to_char(eod.timeframe_end, 'Dy DD Mon YYYY HH24:MI') AS timeframe " 
		. "FROM publication_endofday AS eod "
		. "JOIN publication AS p ON p.id = eod.publication_id "
		. "LEFT JOIN users AS u1 ON u1.username = p.opened_by "
		. "WHERE p.status = 3 "
		. "ORDER BY p.published_on DESC LIMIT 1;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds();

	if ( my $endOfDay = $dbh->fetchRow() ) {
		return $endOfDay;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}

sub getEndOfDaySendingStatus {
	my $status = PublicationEndOfDay->getEndOfDaySendingStatus();
	$status or die 400;
}

1;

=head1 NAME

Taranis::REST::EndOfDay

=head1 SYNOPSIS

  use Taranis::REST::EndOfDay;

  Taranis::REST::EndOfDay->getEndOfDaySendingStatus( dbh => $oTaranisDatase );

  Taranis::REST::EndOfDay->getLastSentEndOfDay( dbh => $oTaranisDatase );

=head1 DESCRIPTION

Possible REST calls for End-Of-Day items.

=head1 METHODS

=head2 getEndOfDaySendingStatus( dbh => $oTaranisDatase )

Retrieves the End-Of-Day sending status. 

    Taranis::REST::EndOfDay->getEndOfDaySendingStatus( dbh => $oTaranisDatase );

Returns a HASH containing C<< { status => 'green', lastPublication => '11:00 01-01-2014' } >>.
Dies with 400 in case of and error.

=head2 getLastSentEndOfDay( dbh => $oTaranisDatase )

Retrieves the date/time of last sent End-Of-Day publication.

    Taranis::REST::EndOfDay->getLastSentEndOfDay( dbh => $oTaranisDatase );

Returns the date/time of last sent End-Of-Day publication or dies with an error.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
