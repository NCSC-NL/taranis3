# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::Analyses;

use strict;
use Taranis::Analysis;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);

Taranis::REST->addRoute(
	route        => qr[^analyses/\d+/?$],
	entitlement  => 'analysis',
	handler      => \&getAnalysis,
);

Taranis::REST->addRoute(
	route        => qr[^analyses/?\?.*status=eow],
	entitlement  => 'analysis',
	particularizations => [ 'eow' ],
	handler      => \&getAnalyses,
);

Taranis::REST->addRoute(
	route        => qr[^analyses/?\?.*status=pending],
	entitlement  => 'analysis',
	particularizations => [ 'pending' ],
	handler      => \&getAnalyses,
);

Taranis::REST->addRoute(
	route        => qr[^analyses/total/?\?],
	entitlement  => 'analysis',
	handler      => \&countAnalyses,
);

my $ratingDictionary = Taranis::Analysis->getRatingDictionary();

sub getAnalysis {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $path = $params{path};

	my $stmnt = "SELECT a.id, a.status, a.title, a.comments, a.rating, "
		. "to_char(a.orgdatetime, 'DD-MM-YYYY HH24:MI') AS created, "
		. "u1.fullname AS owned_by, u2.fullname AS opened_by "
		. "FROM analysis AS a "
		. "LEFT JOIN users AS u1 ON u1.username = a.owned_by "
		. "LEFT JOIN users AS u2 ON u1.username = a.opened_by "
		. "WHERE a.id = ? ;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( $path->[1] );

	if ( my $analysis = $dbh->fetchRow() ) {
		$analysis->{rating} = $ratingDictionary->{ $analysis->{rating} };
		return $analysis;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}

# count : int
# status : statuses set with setting analyze_status_options in taranis.conf.xml
# rating : low|medium|high|undefined
# has_owner: true|false
sub getAnalyses {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};

	my $limit;
	
	my ( %where, @analyses, $error );
	
	for ( keys %$queryParams ) {
		if (/^count$/) {
			if ( $queryParams->{$_} =~ /^\d+$/ ) {
				$limit = $queryParams->{$_};
			} else {
				$error = 'Invalid parameters';
			}
		} elsif (/^rating$/) {
			$where{rating} = [];
			my @ratings = ( ref( $queryParams->{$_} ) =~ /^ARRAY/ )
				? @{ $queryParams->{$_} }
				: $queryParams->{$_};
			
			my $analysesRatingStr = join( '|', values( %$ratingDictionary) );

			foreach my $rating ( @ratings ) {
				if ( $rating =~ /^(?:$analysesRatingStr)$/ ) {
					push @{ $where{rating} }, { reverse( %$ratingDictionary ) }->{$rating};
				} else {
					$error = 'Invalid parameters';
				}
			}
		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = ( ref( $queryParams->{$_} ) =~ /^ARRAY/ )
				? @{ $queryParams->{$_} }
				: $queryParams->{$_};
			
			my $analysesStatusStr = join( '|',  split( ',', Config()->{analyze_status_options} ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$analysesStatusStr)$/ ) {
					push @{ $where{status} }, $status;
				} else {
					$error = 'Invalid parameters';
				}
			}
		} elsif (/^has_owner$/) {
			if ( $queryParams->{$_} =~ /^(?:true|false)$/ ) {
				$where{owned_by} = ( $queryParams->{$_} =~ /^true$/ )
					? \"IS NOT NULL"
					: \"IS NULL";
			} else {
				$error = 'Invalid parameters';
			}
		}
	}
	
	if ( $error ) {
		die 400;
	} else {
		my $select = "a.id, a.status, a.title, a.comments, a.rating, a.opened_by, a.owned_by, to_char(a.orgdatetime, 'DD-MM-YYYY HH24:MI') AS created, u1.fullname AS owned_by_fullname, u2.fullname AS opened_by_fullname";
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'analysis AS a', $select, \%where, 'orgdatetime DESC' );

		my %join = ( 
			'LEFT JOIN users AS u1' => { 'u1.username' => 'a.owned_by' },
			'LEFT JOIN users AS u2' => { 'u2.username' => 'a.opened_by' }
		);
		$stmnt = $dbh->sqlJoin( \%join, $stmnt );
		
		$stmnt .= " LIMIT $limit" if ( defined( $limit ) );
		
		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );
		
		while ( $dbh->nextRecord() ) {
			my $analysis = $dbh->getRecord();
			$analysis->{rating} = $ratingDictionary->{ $analysis->{rating} };
			push @analyses, $analysis;
		}
		
		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return \@analyses;
		}
	}
}

# status : statuses set with setting analyze_status_options in taranis.conf.xml
# rating : low|medium|high|undefined
# has_owner: true|false
sub countAnalyses {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};

	my ( %where, $error );
	
	for ( keys %$queryParams ) {
		if (/^rating$/) {
			$where{rating} = [];
			my @ratings = ( ref( $queryParams->{$_} ) =~ /^ARRAY/ )
				? @{ $queryParams->{$_} }
				: $queryParams->{$_};
			
			my $analysesRatingStr = join( '|', values( %$ratingDictionary) );

			foreach my $rating ( @ratings ) {
				if ( $rating =~ /^(?:$analysesRatingStr)$/ ) {
					push @{ $where{rating} }, { reverse( %$ratingDictionary ) }->{$rating};
				} else {
					$error = 'Invalid parameters';
				}
			}
		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = ( ref( $queryParams->{$_} ) =~ /^ARRAY/ )
				? @{ $queryParams->{$_} }
				: $queryParams->{$_};
			
			my $analysesStatusStr = join( '|',  split( ',', Config()->{analyze_status_options} ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$analysesStatusStr)$/ ) {
					push @{ $where{status} }, $status;
				} else {
					$error = 'Invalid parameters';
				}
			}
		} elsif (/^has_owner$/) {
			if ( $queryParams->{$_} =~ /^(?:true|false)$/ ) {
				$where{owned_by} = ( $queryParams->{$_} =~ /^true$/ )
					? \"IS NOT NULL"
					: \"IS NULL";
			} else {
				$error = 'Invalid parameters';
			}
		}
	}
	
	if ( $error ) {
warn $error;
		die 400;
	} else {
		
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'analysis', 'COUNT(id) AS total', \%where );

		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );
		
		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return $dbh->fetchRow();
		}
	}
}

1;

=head1 NAME

Taranis::REST::Analyses

=head1 SYNOPSIS

  use Taranis::REST::Analyses;

  Taranis::REST::Analyses->getAnalyses( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status } );

  Taranis::REST::Analyses->getAnalysis( dbh => $oTaranisDatase, path => [ undef, $analysisID ] );

  Taranis::REST::Analyses->countAnalyses( dbh => $oTaranisDatase, queryParams => { status => $status } );

=head1 DESCRIPTION

Possible REST calls for analyses.

=head1 METHODS

=head2 getAnalyses( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status } )

Retrieves a list of analyses. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

status: string (statuses set with setting analyze_status_options in taranis.conf.xml)

=item *

count: number which sets the maximum number of analyses (LIMIT) to retrieve

=item *

rating: string (low|medium|high|undefined)

=item *

has_owner: string (true|false)

=back

    Taranis::REST::Analyses->getAnalyses( dbh => $oTaranisDatase, queryParams => { count => 10, status => 'pending', has_owner => 'true' } );

Returns an ARRAY reference or dies with 400 or an error message.

=head2 getAnalysis( dbh => $oTaranisDatase, path => [ undef, $analysisID ] )

Retrieves an analysis.

    Taranis::REST::Analyses->getAnalysis( dbh => $oTaranisDatase, path => [ undef, 34 ] );

Returns an HASH reference containing the analysis or dies with 404 if the analysis can't be found.
Dies with an error message when a database error occurs.

=head2 countAnalyses( dbh => $oTaranisDatase, queryParams => { status => $status } )

Counts analyses which can be filtered with the following settings:

=over

=item *

status: string (statuses set with setting analyze_status_options in taranis.conf.xml)

=item *

rating: string (low|medium|high|undefined)

=item *

has_owner: string (true|false)

=back

    Taranis::REST::Analyses->countAnalyses( dbh => $oTaranisDatase, queryParams => { status => 'pending', rating => 'low', has_owner => 'false' } );

Returns the result as HASH { total => $count } or dies with 400 in case an error occurs.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameters>

Caused by countAnalyses() and getAnalyses() when a parameter other then the allowed parameter in queryParams is set.
Can also be caused by invalid value for an allowed parameter.

=back

=cut
