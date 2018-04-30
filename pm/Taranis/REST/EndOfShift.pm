# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::EndOfShift;

use strict;
use Taranis::Publication::EndOfShift;
use Tie::IxHash;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);

Taranis::REST->addRoute(
	route       => qr[^endofshift/lastsent/?$],
	entitlement => 'publication',
	particularizations =>['end-of-shift (email)','end-of-shift (email public)'],
	handler     => \&getLastSentEndOfShift,
);

Taranis::REST->addRoute(
	route       => qr[^endofshift/status/?$],
	entitlement => 'publication',
	particularizations =>['end-of-shift (email)','end-of-shift (email public)'],
	handler     => \&getEndOfShiftSendingStatus,
);

my $statusDictionary = Taranis::Publication->getStatusDictionary();

sub getLastSentEndOfShift {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	
	my $stmnt = "SELECT eos.*, "
		. "to_char(p.created_on, 'DD-MM-YYYY HH24:MI') AS created, " 
		. "to_char(p.published_on, 'DD-MM-YYYY HH24:MI') AS published, "
		. "p.contents, u1.fullname AS opened_by_fullname, eos.handler, "
		. "to_char(eos.timeframe_begin, 'Dy DD Mon YYYY HH24:MI - ') || to_char(eos.timeframe_end, 'Dy DD Mon YYYY HH24:MI') AS timeframe " 
		. "FROM publication_endofshift AS eos "
		. "JOIN publication AS p ON p.id = eos.publication_id "
		. "LEFT JOIN users AS u1 ON u1.username = p.opened_by "
		. "WHERE p.status = 3 "
		. "ORDER BY p.published_on DESC LIMIT 1;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds();

	if ( my $endOfShift = $dbh->fetchRow() ) {
		return $endOfShift;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}

sub getEndOfShiftSendingStatus {
	my ( %params ) = @_;
	my $dbh = $params{dbh};

	my $oTaranisPublicationEndOfShift = Taranis::Publication::EndOfShift->new( Config );
	my $eosStatus = $oTaranisPublicationEndOfShift->getEndOfShiftSendingStatus();
	
	if ( !$eosStatus ) {
		die 400;
	} else {
		return $eosStatus;
	}
}

1;

=head1 NAME

Taranis::REST::EndOfShift

=head1 SYNOPSIS

  use Taranis::REST::EndOfShift;

  Taranis::REST::EndOfShift->getEndOfShiftSendingStatus( dbh => $oTaranisDatase );

  Taranis::REST::EndOfShift->getLastSentEndOfShift( dbh => $oTaranisDatase );

=head1 DESCRIPTION

Possible REST calls for End-Of-Shift items.

=head1 METHODS

=head2 getEndOfShiftSendingStatus( dbh => $oTaranisDatase )

Retrieves the End-Of-Shift sending status. 

    Taranis::REST::EndOfShift->getEndOfShiftSendingStatus( dbh => $oTaranisDatase );

Returns a HASH containing C<< { current => { status => 'green', lastPublication => '11:00 01-01-2014' }, previous => {...} } >>.
Dies with 400 in case of and error.

=head2 getLastSentEndOfShift( dbh => $oTaranisDatase )

Retrieves the date/time of last sent End-Of-Shift publication.

    Taranis::REST::EndOfShift->getLastSentEndOfShift( dbh => $oTaranisDatase );

Returns the date/time of last sent End-Of-Shift publication or dies with an error.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
