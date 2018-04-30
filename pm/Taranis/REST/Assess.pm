# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::Assess;

use strict;
use Taranis qw(:all);
use Taranis::Assess;
use Taranis::Category;
use Taranis::TagCloud;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);

use HTML::Entities qw(encode_entities);

Taranis::REST->addRoute(
	route        => qr[assess/\d+/?$],
	entitlement  => 'items',
	handler      => \&getAssessItem,
);

Taranis::REST->addRoute(
	route        => qr[^assess/?\?.*category=gaming],
	entitlement  => 'items',
	particularizations => [ 'gaming' ],
	handler      => \&getAssessItems,
);

Taranis::REST->addRoute(
	route        => qr[^assess/?\?.*category=news],
	entitlement  => 'items',
	particularizations => [ 'news' ],
	handler      => \&getAssessItems,
);

Taranis::REST->addRoute(
	route        => qr[^assess/?\?.*category=security-news],
	entitlement  => 'items',
	particularizations => [ 'security-news' ],
	handler      => \&getAssessItems,
);

Taranis::REST->addRoute(
	route        => qr[^assess/?\?.*status=(?:waitingroom|unread)],
	entitlement  => 'items',
	handler      => \&getAssessItems,
);

Taranis::REST->addRoute(
	route        => qr[^assess/total/?\?],
	entitlement  => 'items',
	handler      => \&countAssessItems,
);

Taranis::REST->addRoute(
	route        => qr[^assess/tagcloud/?(?:$|\?)],
	entitlement  => 'items',
	handler      => \&getTagCloud,
);

my $statusDictionary = Taranis::Assess->getStatusDictionary;

# mail items and items with screenshots are excluded from results!

sub getAssessItem {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $path = $params{path};
	
	my $stmnt = "SELECT i.id, i.title, i.description, i.link, i.status, i.source, "
		. "to_char(i.created, 'HH24:MI DD-MM-YYYY') AS created, to_char(i.created, 'HH24:MI') AS created_time, " 
		. "to_char(i.created, 'DD-MM-YYYY') AS created_date, c.name AS category "
		. "FROM item AS i "
		. "JOIN category AS c ON category.id = item.category " 
		. "WHERE i.is_mail = false AND i.screenshot_object_id IS NULL AND i.id = ? ;";
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( $path->[1] );

	if ( my $item = $dbh->fetchRow() ) {
		return $item;
	} elsif ( $dbh->{errmsg} ) {
		die $dbh->{errmsg};
	} else {
		die 404;
	}
}

# count : int
# status : unread|read|important|waitingroom
# category: all category names from DB table category
# search: string
sub getAssessItems {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my $limit = 20;
	
	my ( @items, $error );
	
	my %where = ( is_mail => 0, screenshot_object_id => \'IS NULL' );
	my %join = ( 'JOIN category AS c' => { 'c.id' => 'i.category' } );

	for ( keys %$queryParams ) {
		if (/^count$/) {
			if ( $queryParams->{$_} =~ /^\d+$/ ) {
				$limit = $queryParams->{$_};
			} else {
				$error = 'Invalid parameters';
			}
		} elsif (/^category$/) {
			my $oTaranisCategory = Taranis::Category->new( Config );
			
			$where{category} = [];
			my @categories = flat $queryParams->{$_};

			foreach my $category ( @categories ) {
				if ( my $categoryID = $oTaranisCategory->getCategoryId( $category ) ) {
					push @{ $where{category} }, $categoryID;
				} else {
					$error = "Invalid parameter: category $category";
				}
			}

		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = flat $queryParams->{$_};
			my $itemStatusStr = join( '|', values( %$statusDictionary ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$itemStatusStr)$/ ) {
					push @{ $where{status} }, { reverse( %$statusDictionary ) }->{$status};
				} else {
					$error = "Invalid parameter: status $status";
				}
			}
		} elsif (/^search$/) {
			$where{-or} = {
				title => { -ilike => '%' . trim($queryParams->{$_}) . '%' },
				description => { -ilike => '%' . trim($queryParams->{$_}) . '%' }
			}
		}
	}
	
	if ( $error ) {
		die 400;
	} else {
		
		my $select = "i.id, i.title, i.description, i.link, i.status, i.source, "
			. "to_char(i.created, 'HH24:MI DD-MM-YYYY') AS created, to_char(i.created, 'HH24:MI') AS created_time, "
			. "to_char(i.created, 'DD-MM-YYYY') AS created_date, c.name AS category";
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'item AS i', $select, \%where, 'i.created DESC' );
		
		$stmnt = $dbh->sqlJoin( \%join, $stmnt );

		$stmnt .= " LIMIT $limit" if ( defined( $limit ) && $limit !~ /^0$/ );
		
		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );

		while ( $dbh->nextRecord() ) {
			push @items, $dbh->getRecord();
		}
		
		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return \@items;
		}
	}
}

# status : unread|read|important|waitingroom
# category: all category names from DB table category
# search: string
sub countAssessItems {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my ( $error, %where );

	for ( keys %$queryParams ) {
		if (/^category$/) {
			my $oTaranisCategory = Taranis::Category->new( Config );

			$where{category} = [];
			my @categories = flat $queryParams->{$_};
			foreach my $category ( @categories ) {
				if ( my $categoryID = $oTaranisCategory->getCategoryId( $category ) ) {
					push @{ $where{category} }, $categoryID;
				} else {
					$error = "Invalid parameter category $category";
				}
			}
			
		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = flat $queryParams->{$_};
			my $itemStatusStr = join( '|', values( %$statusDictionary ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$itemStatusStr)$/ ) {
					push @{ $where{status} }, { reverse( %$statusDictionary ) }->{$status};
				} else {
					$error = "Invalid parameter status $status";
				}
			}
		} elsif (/^search$/) {
			
			$where{-or} = {
				title => { -ilike => '%' . trim($queryParams->{$_}) . '%' },
				description => { -ilike => '%' . trim($queryParams->{$_}) . '%' }
			}
		}
	}

	if ( $error ) {
		die 400;
	} else {
		my ( $stmnt, @binds ) = $dbh->{sql}->select( 'item', "COUNT(id) AS total", \%where );

		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @binds );

		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return $dbh->fetchRow();
		}
	}
}

# status : unread|read|important|waitingroom
# category: all category names from DB table category
# search: string
sub getTagCloud {
	my ( %params ) = @_;
	my $dbh = $params{dbh};
	my $queryParams = $params{queryParams};
	
	my ( $error, %where );

	for ( keys %$queryParams ) {
		if (/^category$/) {
			my $oTaranisCategory = Taranis::Category->new( Config );

			$where{category} = [];
			my @categories = flat $queryParams->{$_};

			foreach my $category ( @categories ) {
				if ( my $categoryID = $oTaranisCategory->getCategoryId( $category ) ) {
					push @{ $where{category} }, $categoryID;
				} else {
					$error = 'Invalid parameters';
				}
			}
			
		} elsif (/^status$/) {
			$where{status} = [];
			my @statuses = flat $queryParams->{$_};
			my $itemStatusStr = join( '|', values( %$statusDictionary ) );

			foreach my $status ( @statuses ) {
				if ( $status =~ /^(?:$itemStatusStr)$/ ) {
					push @{ $where{status} }, { reverse( %$statusDictionary ) }->{$status};
				} else {
					$error = 'Invalid parameters';
				}
			}
		} elsif (/^search$/) {
			my $search = trim($queryParams->{$_});
			$where{-or} = {
				title => { -ilike => "%$search%" },
				description => { -ilike => "%$search%" },
			}
		}
	}

	if ( $error ) {
		die 400;
	} else {
		
		my $oTaranisTagCloud = Taranis::TagCloud->new();
		$where{created} = { '>', \"NOW() - '1 day'::INTERVAL"};
		
		my ( $stmnt, @bind ) = $dbh->{sql}->select( 'item', 'title', \%where );

		$dbh->prepare( $stmnt );
		$dbh->executeWithBinds( @bind );
	
		my $text = '';
		while ( $dbh->nextRecord() ) {
			$text .= $dbh->getRecord()->{title} . ' ';
		}
		
		my $list = $oTaranisTagCloud->createTagsListFromText( text => $text );

		tie my %cleanList, 'Tie::IxHash';
		foreach my $tag ( keys %$list ) {
			if ( !$oTaranisTagCloud->isBlacklisted( $tag ) ) {
				$cleanList{ $tag } = $list->{$tag};
			}
		}

		my $sortedList = $oTaranisTagCloud->sortList( \%cleanList );
		my $resizedList = $oTaranisTagCloud->resizeList( list => $sortedList, maximumUniqWords => 20, level => 20 );
		my @tagCloud;
		foreach my $key ( keys %$resizedList ) {
			push @tagCloud, { text => encode_entities( $key ), weight => $list->{$key} };
		}

		if ( $dbh->{errmsg} ) {
			die $dbh->{errmsg};
		} else {
			return { list => \@tagCloud };
		}
	}
}

1;

=head1 NAME

Taranis::REST::Assess

=head1 SYNOPSIS

  use Taranis::REST::Assess;

  Taranis::REST::Assess->getAssessItems( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status, ... } );

  Taranis::REST::Assess->getAssessItem( dbh => $oTaranisDatase, path => [ undef, $assessItemID ] );

  Taranis::REST::Assess->countAssessItems( dbh => $oTaranisDatase, queryParams => { status => $status } );

  Taranis::REST::Assess->getTagCloud( dbh => $oTaranisDatase, queryParams => { status => $status } );

=head1 DESCRIPTION

Possible REST calls for assess items.

=head1 METHODS

=head2 getAssessItems( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status, ... } )

Retrieves a list of assess items. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

status: string (unread|read|important|waitingroom)

=item *

count: number which sets the maximum number of assess items (LIMIT) to retrieve

=item *

category: string (all category names from DB table category)

=item *

search: string

=back

    Taranis::REST::Assess->getAssessItems( dbh => $oTaranisDatase, queryParams => { count => 10, status => 'unread', category => 'some category', search => 'taranis' } );

Returns an ARRAY reference or dies with 400 or an error message.

=head2 getAssessItem( dbh => $oTaranisDatase, path => [ undef, $assessItemID ] )

Retrieves an assess item.

    Taranis::REST::Assess->getAssessItem( dbh => $oTaranisDatase, path => [ undef, 34 ] );

Returns an HASH reference containing the assess item or dies with 404 if the assess items can't be found.
Dies with an error message when a database error occurs.

=head2 countAssessItems( dbh => $oTaranisDatase, queryParams => { status => $status } )

Counts assess items which can be filtered with the following settings:

=over

=item *

status: string (unread|read|important|waitingroom)

=item *

category: string (all category names from DB table category)

=item *

search: string

=back

    Taranis::REST::Assess->countAssessItems( dbh => $oTaranisDatase, queryParams => { status => 'unread', category => 'some category', search => 'taranis' } );

Returns the result as HASH { total => $count } or dies with 400 in case an error occurs.

=head2 getTagCloud( dbh => $oTaranisDatase, queryParams => { count => $count, status => $status, ... } )

Retrieves tagcloud data. 
Tagcloud can be tuned with the following settings:

=over

=item *

status: string (unread|read|important|waitingroom)

=item *

category: string (all category names from DB table category)

=item *

search: string

=back

Returns an HASH { list => \@tagCloud }. The tagcloud list consists of several HASH tag entries: { text => 'tag', weight => tagWeight }.
Dies with 400 or an error message if an error occurs.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameters>

Caused by countAssess() and getAssess() when a parameter other then the allowed parameter in queryParams is set.
Can also be caused by invalid value for an allowed parameter.

=back

=cut
