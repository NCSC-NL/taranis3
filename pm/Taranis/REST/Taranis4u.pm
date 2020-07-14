# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::Taranis4u;

use strict;
use JSON;

# get streams for user X
# get displays for user X (?)

Taranis::REST->addRoute(
	route       => qr[^streams/?(?:$|\?)],
	entitlement => 'generic',
	handler     => \&getStreams,
);

# count : int
sub getStreams {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my $limit = ($queryParams->{count} || '') =~ /^(\d+)$/ ? $1 : 20;

	my ( $stmnt, @binds ) = $dbh->{sql}->select('stream', '*', {}, 'description');
	
	$stmnt .= " LIMIT $limit";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( @binds );

	my @streams;
	while ( $dbh->nextRecord() ) {
		my $stream   = $dbh->getRecord();
		my @displays = $stream->{displays_json} ? @{ from_json( $stream->{displays_json} ) } : [];
		$stream->{displays} = \@displays; 
		push @streams, $stream;
	}

	if ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		return \@streams;
	}
}

1;

=head1 NAME

Taranis::REST::Taranis4u

=head1 SYNOPSIS

  use Taranis::REST::Taranis4u;

  Taranis::REST::Taranis4u->getStreams( dbh => $oTaranisDatase, queryParams => { count => $limit } );

=head1 DESCRIPTION

Possible REST calls for Taranis streams

=head1 METHODS

=head2 getStreams( dbh => $oTaranisDatase, queryParams => { count => $limit } )

Retrieves the streams of screens which are used for display on the BigScreen. 
The number of streams can be limited by the count parameter. Count defaults to 20.

    Taranis::REST::Taranis4u->getStreams( dbh => $oTaranisDatase, queryParams => { count => 15 } );

Returns a ARRAY reference of streams
Dies with 400 in case of and error.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
