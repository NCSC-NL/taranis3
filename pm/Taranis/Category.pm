# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Category;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
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

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord();
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord();		
}

sub getCategory {
  my ( $self, %where ) = @_;
	undef $self->{errmsg};
	my @categories; 
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "category", "*", \%where, "name" );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		 $self->{errmsg} = $self->{dbh}->{db_error_msg};
		 return 0;
	} else {
		while ( $self->nextObject ) {
			push ( @categories, $self->getObject );
		}	
		
		if ( scalar @categories > 1 ) {
			return @categories;
		} else {
			return $categories[0];
		}		
	}
}

sub setCategory {
  my ( $self, %updates ) = @_;
	undef $self->{errmsg};
  
  my %where = ( id => $updates{id} ); 
  delete $updates{id};
  
	my ( $stmnt, @bind ) = $self->{sql}->update( "category", \%updates, \%where );
	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Update failed, corresponding id not found in database.";
		return 0;
	}
}

sub addCategory {
  my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "category", \%inserts );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteCategory {
  my ( $self, $id ) = @_;
	undef $self->{errmsg};

	if ( 
				!$self->{dbh}->checkIfExists( { category => $id }, 'item' ) && 
				!$self->{dbh}->checkIfExists( { category => $id }, 'item_archive' ) &&
				!$self->{dbh}->checkIfExists( { category_id => $id }, 'search_category' ) && 
				!$self->{dbh}->checkIfExists( { category => $id }, 'sources' )
	) {	
		
		my ( $stmnt, @bind ) = $self->{sql}->delete( 'category', { id => $id } );
		$self->{dbh}->prepare( $stmnt );
		
		if ( $self->{dbh}->executeWithBinds( @bind) > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} else {
			$self->{errmsg} = "Delete failed, corresponding id not found in database.";
			return 0;
		}		
		
	} else {
		$self->{errmsg} = 'This category is still in use. To remove this category from menu, set the category to disable.';
		return 0;
	}
}

sub getCategoryId {
	my ( $self, $categoryName ) = @_;
	undef $self->{errmsg};
	
	my %where = ( name => { -ilike => $categoryName } );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'category', 'id', \%where );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $category = $self->{dbh}->fetchRow();
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		 $self->{errmsg} = $self->{dbh}->{db_error_msg};
		 return 0;	
	}
	
	if ( exists( $category->{id} ) ) {
		return $category->{id};
	}	else {
		return 0;
	}
}

1;

=head1 NAME

Taranis::Category - functionality for add, edit, delete and retrieval of Assess categories.

=head1 SYNOPSIS

  use Taranis::Category;

  my $obj = Taranis::Category->new( $objTaranisConfig );

  $obj->addCategory( name => $category_name );

  $obj->setCategory( id => $category_id, name => $category_name, is_enabled => $is_enabled );

  $obj->getCategory( id => $category_id );

  $obj->deleteCategory( $id );

  $obj->getCategoryId( $category_name );

  $obj->nextObject();

  $obj->getObject();

=head1 DESCRIPTION

Sources in Taranis are divided in categories. These categories are used in Assess to view items of a particular category.
These categories are also used for setting particularization rights on entitlement C<item>.  
This module can be used to add, edit, retrieve and delete Assess categories.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Category> module.  An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Category->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Returns the blessed object.

=head2 addCategory( name => $categoryName )

Method for adding a Assess category. Both columns C<name> and C<is_enabled> can be given in C<< key => value >> pairs.
If C<is_enabled> is not given it will be set to true.

    $obj->addCategory( name => 'myCategoryName' ); 

Returns TRUE if addiotion is successful. If it's not ok it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setCategory( id => $category_id, name => $category_name, is_enabled => $is_enabled )

Method for editing a category. Takase C<id> as mandatory argument.

    $obj->setCategory( id => 68, name => 'myCategoryName', is_enabled => 1 );

Returns TRUE if update is successful. If it's not ok it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 $obj->getCategory( id => $category_id )

Method for retrieval of one or more categories. 
Can take any column of table C<category> as argument in C<< key => value >> format.
If no arguments are supplied a list of all categories will be returned.

    $obj->getCategory( id => 78 );
    
OR

    $obj->getCategory( is_enabled => 1 );

OR

    $obj->getCategory();

If only one category is found it will return a HASH reference with keys C<id>, C<name> and C<is_enabled>.

If more than one category is found it will return an ARRAY of HASHES with mentioned keys.

If a database error occurs it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteCategory( $id )

Method used for deleting a category. Only takes the category id as argument, which is mandatory.

    $obj->deleteCategory( 67 );

Before deleting the specified category it will check if the category is referenced is one of the following tables:

=over

=item *

item

=item *

item_archive

=item *

search_category

=item *

users

=item *

sources

=back

If the category is referenced it will return FALSE. 
It will also return FALSE if a database error occurs, which will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
If category deletion is successful it will return TRUE. 

=head2 getCategoryId( $category_name )

Method for retrieving the category id. Takes the category name as argument which is mandatory. 
The category name lookup is case insensitive.

    $obj->getCategoryId( 'myCategoryName' );

If category is found returns the category id. If not found it will return FALSE.
Will also return FALSE if a database error occurs, which will also set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method like loadCollection().

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Update failed, corresponding id not found in database.> & I<Delete failed, corresponding id not found in database.>

Caused by setCategory() & deleteCategory() when there is no category that has the specified category id. 
You should check what feeds the input category id of the method. 

=item * 

I<This category is still in use. To remove this category from menu and select options, try setting the category to disable.>

Caused by deleteCategory() when you're trying to delete a category which is still referenced in on the tables ( C<item>, C<item_archive>, C<search_category>, C<users> and C<sources> ).
This is not possible because the category is a foreign key in one of the mentionded tables.  

=back

=cut
