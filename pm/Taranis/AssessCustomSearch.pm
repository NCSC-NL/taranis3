# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::AssessCustomSearch;

use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Data::Dumper;
use Tie::IxHash;
use strict;

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub getSearch {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	tie my %join, "Tie::IxHash";
	
	my $select = "to_char(startdate, 'DD-MM-YYYY') AS startdate_plainformat, to_char(enddate, 'DD-MM-YYYY') AS enddate_plainformat, s.*";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'search s', $select, { id => $id } );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $search = $self->{dbh}->fetchRow();
	
	my @categories;
	my %categoryWhere = ( 'sc.search_id' => $search->{id} );
	
	my ( $categoryStmnt, @categoryBind ) = $self->{sql}->select( 'category c', 'c.*', \%categoryWhere );
	my %categoryJoin = ( 'JOIN search_category sc' => { 'sc.category_id' => 'c.id' } );
	
	$categoryStmnt = $self->{dbh}->sqlJoin( \%categoryJoin, $categoryStmnt );

	$self->{dbh}->prepare( $categoryStmnt );
	$self->{dbh}->executeWithBinds( @categoryBind );

	while ( $self->nextObject() ) {
		push @categories, $self->getObject()->{id};
	}
	
	$search->{categories} = \@categories;
	
	my @sources;
	my %sourceWhere = ( 'search_id' => $search->{id} );
	
	my ( $sourceStmnt, @sourceBind ) = $self->{sql}->select( 'search_source', 'sourcename', \%sourceWhere );

	$self->{dbh}->prepare( $sourceStmnt );
	$self->{dbh}->executeWithBinds( @sourceBind );

	while ( $self->nextObject() ) {
		push @sources, $self->getObject()->{sourcename};
	}
	
	$search->{sources} = \@sources;	

	return $search;	
}

sub loadCollection {
	my ( $self, @where ) = @_;
	undef $self->{errmsg};
	
	my @searches;

	my $select = "to_char(startdate, 'DD-MM-YYYY') AS startdate_plainformat, to_char(enddate, 'DD-MM-YYYY') AS enddate_plainformat, *";	
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'search', $select, \@where, 'description' );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		push @searches, $self->getObject(); 
	}

	foreach my $search ( @searches ) {
		my $searchId = $search->{id};
		my %searchWhere = ( search_id => $searchId );
		
		my @categories;
		my ( $categoryStmnt, @categoryBind ) = $self->{sql}->select( 'category c', 'c.*', \%searchWhere, 'c.name' );
		my %categoryJoin = ( 'JOIN search_category sc' => { 'sc.category_id' => 'c.id' } );
		
		$categoryStmnt = $self->{dbh}->sqlJoin( \%categoryJoin, $categoryStmnt );

		$self->{dbh}->prepare( $categoryStmnt );
		$self->{dbh}->executeWithBinds( @categoryBind );
		
		while ( $self->nextObject() ) {
			push @categories, $self->getObject();
		}
		
		my @sources;
		my ( $sourceStmnt, @sourceBind ) = $self->{sql}->select( 'search_source', 'sourcename', \%searchWhere, 'sourcename' );
		
		$self->{dbh}->prepare( $sourceStmnt );
		$self->{dbh}->executeWithBinds( @sourceBind );
		
		while ( $self->nextObject() ) {
			push @sources, $self->getObject()->{sourcename};
		}		

		$search->{categories} = \@categories;
		$search->{sources} = \@sources;		
	}
	
	return \@searches
}

sub addSearch {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};

	my @sources = @{ delete( $inserts{sources} ) };
	my @categories = @{ delete( $inserts{categories} ) };

	withTransaction {
		my ( $stmnt, @bind ) = $self->{sql}->insert( 'search', \%inserts );
		$self->{dbh}->prepare( $stmnt );

		my $result = $self->{dbh}->executeWithBinds( @bind );

		my $search_id = $self->{dbh}->getLastInsertedId( 'search' );
		foreach my $sourcename ( @sources ) {
			my %sourceInsertWhere = ( search_id => $search_id, sourcename => $sourcename );
			my ( $sourceInsertStmnt, @sourceInsertBind ) = $self->{sql}->insert( 'search_source', \%sourceInsertWhere );

			$self->{dbh}->prepare( $sourceInsertStmnt );
			$self->{dbh}->executeWithBinds( @sourceInsertBind );
		}

		foreach my $category_id ( @categories ) {
			my %categoryInsertWhere = ( search_id => $search_id, category_id => $category_id );
			my ( $categoryInsertStmnt, @categoryInsertBind ) = $self->{sql}->insert( 'search_category', \%categoryInsertWhere );

			$self->{dbh}->prepare( $categoryInsertStmnt );
			$self->{dbh}->executeWithBinds( @categoryInsertBind );
		}
	};

	return 1;
}

sub setSearch {
	my ( $self, %updates ) = @_;
	undef $self->{errmsg};

	my @sources = @{ delete( $updates{sources} ) };
	my @categories = @{ delete( $updates{categories} ) };
	my $search_id  = delete $updates{id};

	my %where = ( id => $search_id );

	withTransaction {
		my ( $stmnt, @bind ) = $self->{sql}->update( "search", \%updates, \%where );
		$self->{dbh}->prepare( $stmnt );

		my $result = $self->{dbh}->executeWithBinds( @bind );

		# DELETE and INSERT sources in search_source
		my ( $sourceDeleteStmnt, @sourceDeleteBind ) = $self->{sql}->delete( 'search_source', { search_id => $search_id } );

		$self->{dbh}->prepare( $sourceDeleteStmnt );
		$self->{dbh}->executeWithBinds( @sourceDeleteBind );

		foreach my $sourcename ( @sources ) {
			my %sourceInsertWhere = ( search_id => $search_id, sourcename => $sourcename );
			my ( $sourceInsertStmnt, @sourceInsertBind ) = $self->{sql}->insert( 'search_source', \%sourceInsertWhere );

			$self->{dbh}->prepare( $sourceInsertStmnt );
			$self->{dbh}->executeWithBinds( @sourceInsertBind );
		}

		# DELETE and INSERT categories in search_category
		my ( $categoryDeleteStmnt, @categoryDeleteBind ) = $self->{sql}->delete( 'search_category', { search_id => $search_id } );

		$self->{dbh}->prepare( $categoryDeleteStmnt );
		$self->{dbh}->executeWithBinds( @categoryDeleteBind );

		foreach my $category_id ( @categories ) {
			my %categoryInsertWhere = ( search_id => $search_id, category_id => $category_id );
			my ( $categoryInsertStmnt, @categoryInsertBind ) = $self->{sql}->insert( 'search_category', \%categoryInsertWhere );

			$self->{dbh}->prepare( $categoryInsertStmnt );
			$self->{dbh}->executeWithBinds( @categoryInsertBind );
		}
	};

	return 1;
}

sub deleteSearch {
	my ( $self, $searchId ) = @_;
	undef $self->{errmsg};

	my ( $deleteSearchSourceStmnt, @deleteSearchSourceBind ) = $self->{sql}->delete( "search_source", { search_id => $searchId } );

	withTransaction {
		$self->{dbh}->prepare( $deleteSearchSourceStmnt );

		if ( !$self->{dbh}->executeWithBinds( @deleteSearchSourceBind ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
		} else {

			my ( $deleteSearchCategoryStmnt, @deleteSearchCategoryBind ) = $self->{sql}->delete( "search_category", { search_id => $searchId } );

			$self->{dbh}->prepare( $deleteSearchCategoryStmnt );

			if ( !$self->{dbh}->executeWithBinds( @deleteSearchCategoryBind ) ) {
				$self->{errmsg} = $self->{dbh}->{db_error_msg};
			} else {

				my ( $deleteSearchStmnt, @deleteSearchBind ) = $self->{sql}->delete( "search", { id => $searchId } );

				$self->{dbh}->prepare( $deleteSearchStmnt );

				if ( !$self->{dbh}->executeWithBinds( @deleteSearchBind ) ) {
					$self->{errmsg} = $self->{dbh}->{db_error_msg};
				}
			}
		}
	};

	if ( !$self->{errmsg} ) {
		return 1;
	} else {
		return 0
	}
}

sub isOwnerOrPublic {
	my ( $self, %settings ) = @_;
	
	my $user = $settings{user};
	my $search_id = $settings{search_id};
	
	my @where = ( 
								{ created_by => $user, id => $search_id }, 
								{ is_public => 1, id => $search_id } 
							);
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'search', 'COUNT(*) AS cnt', \@where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $result = $self->{dbh}->fetchRow();
	
	if ( $result->{cnt} == 0 ) {
		return 0;
	} else {
		return 1;
	}
}

sub checkRights {
	my ( $self, %settings ) = @_;
	
	my $allowedCategories = $settings{allowedCategories};
	
	my @categories;
	foreach my $category ( @$allowedCategories ) {
		push @categories, $category->{id};
	}

	my %where = ( 
								search_id => $settings{searchId}, 
								category_id => \@categories 
							);
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'search_category', 'COUNT(*) AS cnt', \%where );

	my %whereSubQuery = ( search_id => $where{search_id} );

	my ( $subStmnt, @subBind ) = $self->{sql}->select( 'search_category', 'COUNT(*)', \%whereSubQuery );
	
	$stmnt .= ' OR ( ' . $subStmnt . ' ) = 0 ';

	push @bind, @subBind;

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $result = $self->{dbh}->fetchRow();
	
	if ( $result->{cnt} == 0 ) {
		return 0;
	} else {
		return 1;
	}	
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord();
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord();		
}

1;

=head1 NAME

Taranis::AssessCustomSearch - functionality for custom searches in Assess

=head1 SYNOPSIS

  use Taranis::AssessCustomSearch;

  my $obj = Taranis::AssessCustomSearch->new( $objTaranisConfig );

  $obj->getSearch( $search_id );

  $obj->loadCollection( created_by => $userid, is_public => 1, ... );

  $obj->addSearch( description => $description, keywords => $keywords, uriw => $uriw,
                   startdate => $startdate,	enddate => $enddate, hitsperpage => $hitsPerPage,
                   sortby => $sorting, sources => \@sources, categories	=> \@categories,
                   is_public => $is_public,	created_by => $userid );

  $obj->setSearch( id => $search_id, description => $description,	keywords => $keywords, uriw	=> $uriw,
                   startdate => $startdate,	enddate => $enddate, hitsperpage => $hitsPerPage,
                   sortby => $sorting, sources => \@sources, categories	=> \@categories,
                   is_public => $is_public, created_by => $userid );								  

  $obj->deleteSearch( $search_id );

  $obj->isOwnerOrPublic( search_id => $search_id, user => $userid );

  $obj->checkRights( searchId => $searchId, allowedCategories => \@categories );

  $obj->nextObject();

  $obj->getObject();

=head1 DESCRIPTION

Within Assess it's possible to use custom made searches which can be saved for regular use. 
The searches can be added via the main window of Assess and can be edited and removed from the user panel.
This module contains all methods for adding, editing, deletion and retrieval of custom searches as well as performing some checks on user rights and search rights. 

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::AssessCustomSearch> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::AssessCustomSearch->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Returns the blessed object.

=head2 getSearch( $search_id )

This method retrieves the search settings of one custom search.
Takes the search id as argument.

    $obj->getSearch( 87 ); 

Returns the settings as HASH reference where C<startdate> and C<enddate> are formatted to DD-MM-YYYY and renamed to C<startdate_plainformat> and C<enddate_plainformat>.
Also the search categories can be found in the HASH with the key C<categories>. Same goes for sources which can be found with key C<sources>.

=head2 loadCollection( created_by => $userid, is_public => 1, ... )

This method can be used for retrieving a list of custom searches. It takes all columns as argument if specified like column_name => "value".

    $obj->loadCollection( created_by => $userid, is_public => 1 );

Formatting of columns C<startdate> and C<enddate> and the retrieval of categories and sources from the HASH reference is the same as getSearch().

Returns found searches as an ARRAY of HASHES.

=head2 addSearch( \%inserts )

Save a newly created custom search. Takes all columns of table search as argument as well as an ARRAY reference for sources and categories.

    $obj->addSearch( description => $description, keywords => $keywords, sources => \@sources, categories	=> \@categories, created_by	=> $userid );

Returns TRUE if all goes well.

=head2 setSearch( \%updates )

Same as addSearch() except argument search id, which is mandatory.

=head2 deleteSearch( $search_id )

Method to delete a custom search. Takes the search id as argument.

    $obj->deleteSearch( 87 );

Return TRUE on success.

=head2 isOwnerOrPublic( search_id => $search_id, user => $userid )

Checks if the custom search, specified by the C<search_id> argument, was created by the specified C<user> or if the custom search is set to public.
If one of these conditions is true, the method will return TRUE. Else it will return FALSE.

    $obj->isOwnerOrPublic( search_id => 87, user => 'userx' );

=head2 checkRights( searchId => $searchId, allowedCategories => \@categories )

Checks if the specified search contains at least one of the specified categories.

    $obj->checkRights( searchId => 87, allowedCategories => [ 2, 5, 8 ] );

Returns TRUE or FALSE depending on the found result.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method  like loadCollection().

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=cut
