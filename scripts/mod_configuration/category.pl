#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Category;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use JSON;
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw( 
	displayCategories openDialogNewCategory openDialogCategoryDetails 
	saveNewCategory saveCategoryDetails deleteCategory getCategoryItemHtml
);

sub category_export {
	return @EXPORT_OK;
}

sub displayCategories {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $ca = Taranis::Category->new( Config );
	
	my @categories = $ca->getCategory();
	
	$vars->{categories} = \@categories;
	$vars->{numberOfResults} = scalar @categories;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('category.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('category_filters.tt', $vars, 1);
	
	my @js = ('js/category.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewCategory {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'category_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};		
}

sub openDialogCategoryDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $ca = Taranis::Category->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		$id = $kvArgs{id};
		my $category = $ca->getCategory( id => $id );

		if ( exists $category->{id} ) {
			$vars->{category} = $category;
		} else {
			$vars->{message} = $ca->{errmsg};
		}

		$tpl = 'category_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};
}

sub saveNewCategory {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") ) {

		my $ca = Taranis::Category->new( Config );
		if ( !$ca->{dbh}->checkIfExists( { name => $kvArgs{name} }, "category", "IGNORE_CASE" ) ) {
			
			if ( $ca->addCategory( name => $kvArgs{name} ) ) {
				$id = $ca->{dbh}->getLastInsertedId('category');
				setUserAction( action => 'add category', comment => "Added category '$kvArgs{name}'");
			} else {
				$message = $ca->{errmsg};
				setUserAction( action => 'add category', comment => "Got error '$message' while trying to add category '$kvArgs{name}'");
			} 
		} else {
			$message = "A category with the same name already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};
}

sub saveCategoryDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my $ca = Taranis::Category->new( Config );
		my $originalCategoryName = $ca->getCategory( id => $id )->{name};
		
		my $is_enabled = ( $kvArgs{disable_category} ) ? 0 : 1;
		
		my %category_update = ( 
			id => $kvArgs{id}, 
			name => $kvArgs{name}, 
			is_enabled => $is_enabled 
		);
		
		if (
			lc( $kvArgs{name} ) eq lc( $originalCategoryName ) 
			|| !$ca->{dbh}->checkIfExists( { name => $kvArgs{name} } , "category", "IGNORE_CASE" ) 
		) {
							
			if ( !$ca->setCategory( %category_update ) ) {
				$message = $ca->{errmsg};
				setUserAction( action => 'edit category', comment => "Got error '$message' while trying to edit category name '$originalCategoryName' to '$kvArgs{name}'");
			} else {
				setUserAction( action => 'edit category', comment => "Edited category name '$originalCategoryName' to '$kvArgs{name}'");
			}
		} else {
			$message = "A category with the same name already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
}

sub deleteCategory {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $ca = Taranis::Category->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $category = $ca->getCategory( id => $kvArgs{id} );
		
		if ( !$ca->deleteCategory( $kvArgs{id} ) ) {
			$message = $ca->{errmsg};
			setUserAction( action => 'delete category', comment => "Got error '$message' while trying to delete category '$category->{name}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete category', comment => "Deleted category '$category->{name}'");
		}

	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $id
		}
	};
}

sub getCategoryItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ca = Taranis::Category->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $category = $ca->getCategory( id => $id );
 
	if ( $category ) {
		$vars->{category} = $category;

		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'category_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}
1;
