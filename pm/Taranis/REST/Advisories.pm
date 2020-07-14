# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::Advisories;

use strict;
use Taranis qw(flat);

use Taranis::Publication;
use Tie::IxHash;

Taranis::REST->addRoute(
	route              => qr[^advisories/\d+/?(?:$|\?)$],
	entitlement        => 'publication',
	particularizations => [ 'advisory (email)', 'advisory (xml)' ],
    handler            => \&getAdvisory,
);

Taranis::REST->addRoute(
	route              => qr[^advisories/?(?:$|\?)],
	entitlement        => 'publication',
	particularizations => 'advisory (email)',
    handler            => \&getAdvisories,
);

Taranis::REST->addRoute(
	route              => qr[^advisories/total/?(?:$|\?)],
	entitlement        => 'publication',
    handler            => \&countAdvisories,
);

my $statusDictionary = Taranis::Publication->getStatusDictionary;

sub getAdvisory {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $path = $params{path};
	my $advisory_id = $path->[1];

	my $stmnt = "SELECT pa.id, pa.title, pa.govcertid, pa.version, "
		. "to_char(p.created_on, 'DD-MM-YYYY HH24:MI') AS created, " 
		. "to_char(p.published_on, 'DD-MM-YYYY HH24:MI') AS published, "
		. "p.contents, u1.fullname AS opened_by_fullname " 
		. "FROM publication_advisory AS pa "
		. "JOIN publication AS p ON p.id = pa.publication_id "
		. "LEFT JOIN users AS u1 ON u1.username = p.opened_by "
		. "WHERE pa.id = ? AND pa.deleted = false;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds($advisory_id);

	if ( my $advisory = $dbh->fetchRow() ) {
		return $advisory;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}


# count : int
# status : sending|ready4review|published|pending|approved
sub getAdvisories {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my $limit = 20;
	
	my ( @advisories, $error );
	
	my %where = ( deleted => 0 );
	
	for ( keys %$queryParams ) {
		if (/^count$/) {
			if ( $queryParams->{$_} =~ /^\d+$/ ) {
				$limit = $queryParams->{$_};
			} else {
				$error = 'Invalid parameters';
			}
		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = flat $queryParams->{$_};
			my $publicationStatusStr = join( '|', values( %$statusDictionary ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$publicationStatusStr)$/ ) {
					push @{ $where{status} }, { reverse( %$statusDictionary ) }->{$status};
				} else {
					$error = 'Invalid parameters';
				}
			}
		}
	}
	
	if ( $error ) {
		die 400;
	} else {
		my $select = "pa.id, pa.title, pa.govcertid, pa.version, p.opened_by, to_char(p.created_on, 'DD-MM-YYYY HH24:MI') AS created, to_char(p.published_on, 'DD-MM-YYYY HH24:MI') AS published, p.contents, u1.fullname AS opened_by_fullname";
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'publication_advisory AS pa', $select, \%where, 'p.created_on DESC' );
		
		tie my %join, "Tie::IxHash";
		%join = ( 
			"JOIN publication AS p" => { "p.id" => "pa.publication_id" },
			"LEFT JOIN users AS u1" => { "u1.username" => "p.opened_by" }
		);
		$stmnt = $dbh->sqlJoin( \%join, $stmnt );
		
		$stmnt .= " LIMIT $limit" if ( defined( $limit ) );
		
		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );
		
		while ( $dbh->nextRecord() ) {
			push @advisories, $dbh->getRecord();
		}
		
		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return \@advisories;
		}
	}
}

# status : sending|ready4review|published|pending|approved
sub countAdvisories {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};

	my ( %where, $error );
	
	for ( keys %$queryParams ) {
		if (/^status$/) {
			$where{status} = [];
			my @statuses = flat $queryParams->{$_};
			my $publicationStatusStr = join( '|', values( %$statusDictionary ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$publicationStatusStr)$/ ) {
					push @{ $where{status} }, { reverse( %$statusDictionary ) }->{$status};
				} else {
					$error = 'Invalid parameters';
				}
			}
		} else {
			$error = 'Invalid parameters';
		}
	}
	
	die 400 if $error;

	my $count = 0;
	foreach my $table (
		'publication_advisory',
		'publication_advisory_forward',
		'publication_advisory_website' ) {

		if($table =~ /website/)
			 { delete $where{deleted} }
		else { $where{deleted} = 0 }

		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'publication AS p', 'COUNT(p.id) AS total', \%where );

		my %join = ( "JOIN $table AS pa" => { 'pa.publication_id' => 'p.id' } );
		$stmnt = $dbh->sqlJoin( \%join, $stmnt );
	
		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );

		$count += $dbh->fetchRow()->{total};
	}
	return { total => $count };
}

1;

=head1 NAME

Taranis::REST::Advisories

=head1 SYNOPSIS

  use Taranis::REST::Advisories;

  Taranis::REST::Advisories->getAdvisories( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status } );

  Taranis::REST::Advisories->getAdvisory( dbh => $oTaranisDatase, path => [ undef, $advisoryID ] );

  Taranis::REST::Advisories->countAdvisories( dbh => $oTaranisDatase, queryParams => { status => $status } );

=head1 DESCRIPTION

Possible REST calls for advisories. 

=head1 METHODS

=head2 getAdvisories( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status } )

Retrieves a list of advisories. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

status: string (sending|ready4review|published|pending|approved)

=item *

count: number which sets the maximum number of advisories (LIMIT) to retrieve

=back

    Taranis::REST::Advisories->getAdvisories( dbh => $oTaranisDatase, queryParams => { count => 10, status => 'pending' } );

Returns an ARRAY reference or dies with 400 or an error message.

=head2 getAdvisory( dbh => $oTaranisDatase, path => [ undef, $advisoryID ] )

Retrieves an advisory.

    Taranis::REST::Advisories->getAdvisory( dbh => $oTaranisDatase, path => [ undef, 34 ] );

Returns an HASH reference containing the advisory or dies with 404 if the analysis can't be found.
Dies with an error message when a database error occurs.

=head2 countAdvisories( dbh => $oTaranisDatase, queryParams => { status => $status } )

Counts advisories with a certain status (sending|ready4review|published|pending|approved).

    Taranis::REST::Advisories->countAdvisories( dbh => $oTaranisDatase, queryParams => { status => 'pending' } );

Returns the result as HASH { total => $count } or dies with 400 in case an error occurs.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameters>

Caused by countAdvisories() and getAdvisories() when a parameter other then the allowed parameter in queryParams is set.
Can also be caused by invalid value for an allowed parameter.

=back

=cut
