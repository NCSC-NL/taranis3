# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::Announcements;

use strict;
use JSON;

Taranis::REST->addRoute(
	route        => qr[announcements/?(?:$|\?)],
	entitlement  => 'generic',
	handler      => \&getAnnouncements,
);

Taranis::REST->addRoute(
	route        => qr[announcements/\d+/?(?:$|\?)],
	entitlement  => 'generic',
	handler      => \&getAnnouncement,
);

sub getAnnouncement {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $path = $params{path};
	
	my $stmnt = "SELECT id, content_json, title, to_char(created, 'DD-MM-YYYY HH24:MI') AS created_str FROM announcement WHERE id = ?;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( $path->[1] );

	if ( my $announcement = $dbh->fetchRow() ) {
		$announcement->{content} = from_json( delete ( $announcement->{content_json} ) ) if ( $announcement->{content_json} );
		return $announcement;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}

# count: int
# type: bullet-list|todo-list|freeform-text 
sub getAnnouncements {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my $limit = 20;
	
	my ( @announcements, $error );
	
	my %where = ( is_enabled => 1 );
	
	for ( keys %$queryParams ) {
		if (/^count$/) {
			if ( $queryParams->{$_} =~ /^\d+$/ ) {
				$limit = $queryParams->{$_};
			} else {
				$error = 'Invalid parameters';
			}
		} elsif (/^type$/) {
			$where{type} = [];
			my @types = ( ref( $queryParams->{$_} ) =~ /^ARRAY/ )
				? @{ $queryParams->{$_} }
				: $queryParams->{$_};
			
			foreach my $type ( @types ) {
				if ( $type =~ /^(?:bullet-list|todo-list|freeform-text)$/ ) {
					push @{ $where{type} }, $type;
				} else {
					$error = 'Invalid parameters';
				}
			}
		}
	}
	
	if ( $error ) {
		die 400;
	} else {

		my $select = "id, content_json, title, to_char(created, 'DD-MM-YYYY HH24:MI') AS created_str";
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'announcement', $select, \%where, 'created DESC' );
		
		$stmnt .= " LIMIT $limit" if ( defined( $limit ) );
		
		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );
		
		while ( $dbh->nextRecord() ) {
			my $announcement = $dbh->getRecord();
			$announcement->{content} = from_json( delete( $announcement->{content_json} ) ) if ( $announcement->{content_json} );
			push @announcements, $announcement;
		}
		
		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return \@announcements;
		}
	}
}

1;

=head1 NAME

Taranis::REST::Announcements

=head1 SYNOPSIS

  use Taranis::REST::Announcements;

  Taranis::REST::Announcements->getAnnouncements( dbh => $oTaranisDatase, queryParams => { count => $count, type => $type } );

  Taranis::REST::Announcements->getAnnouncement( dbh => $oTaranisDatase, path => [ undef, $announcementID ] );

=head1 DESCRIPTION

Possible REST calls for announcements. 

=head1 METHODS

=head2 getAnnouncements( dbh => $oTaranisDatase, queryParams => { count => $count, type => $type } )

Retrieves a list of announcements. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

type: string (bullet-list|todo-list|freeform-text)

=item *

count: number which sets the maximum number of announcements (LIMIT) to retrieve

=back

    Taranis::REST::Announcements->getAnnouncements( dbh => $oTaranisDatase, queryParams => { count => 10, type => 'bullet-list' } );

Returns an ARRAY reference or dies with 400 or an error message.

=head2 getAnnouncement( dbh => $oTaranisDatase, path => [ undef, $announcementID ] )

Retrieves an announcement.

    Taranis::REST::Announcements->getAnnouncement( dbh => $oTaranisDatase, path => [ undef, 34 ] );

Returns an HASH reference containing the announcement or dies with 404 if the announcement can't be found.
Dies with an error message when a database error occurs.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameters>

Caused by getAnnouncements() when a parameter other then the allowed parameter in queryParams is set.
Can also be caused by invalid value for an allowed parameter.

=back

=cut
