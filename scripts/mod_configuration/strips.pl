#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw( 
	displayStrips openDialogNewStrips openDialogStripsDetails
	saveNewStrips saveStripsDetails deleteStrips
	searchStrips getStripsItemHtml 
);

sub strips_export {
	return @EXPORT_OK;
}

sub displayStrips {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );
	my $tt = Taranis::Template->new;
	
	my $unsortedStrips = $sp->loadCollection();
	my @strips = sort { $$a{'hostname'} cmp $$b{'hostname'} } @$unsortedStrips;
	
	$vars->{stripsList} = \@strips;
	$vars->{numberOfResults} = scalar @strips;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('strips.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('strips_filters.tt', $vars, 1);
	
	my @js = ('js/strips.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };		
}

sub openDialogNewStrips {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {

		$tpl = 'strips_details.tt';
		
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

sub openDialogStripsDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );
	my $writeRight = right("write"); 

	if ( exists( $kvArgs{id} ) && $kvArgs{id} ) {
		$id = $kvArgs{id};
		
		my $strips = $sp->getElement( $kvArgs{id} );
		$vars->{strips} = $strips;

		$vars->{write_right} = $writeRight;
        
		$tpl = 'strips_details.tt';
		
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

sub saveNewStrips {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && exists( $kvArgs{hostname} ) && $kvArgs{hostname} ) {
		$id = sanitizeInput("xml_primary_key", $kvArgs{hostname} );
		
		my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );
		
		if ( !$sp->checkIfExists( $id ) ) {
			if ( 
				!$sp->addElement( 
					hostname => $id, 
					strip0 => $kvArgs{strip0},
					strip1 => $kvArgs{strip1}, 
					strip2 => $kvArgs{strip2}, 
				) 
			) {
				$message = $sp->{errmsg};
				setUserAction( action => 'add strip', comment => "Got error '$message' while trying to add strip for '$kvArgs{hostname}'");
			} else {
				setUserAction( action => 'add strip', comment => "Added strip for '$kvArgs{hostname}'");
			}
		} else {
			$message = "A strip with the same name already exists.";			
		}

	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id
		}
	};
}

sub saveStripsDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id, $originalId );
	my $saveOk = 0;
	
	
	if ( right("write") && $kvArgs{hostname} && $kvArgs{originalId} ) {
		( $id, $originalId ) = sanitizeInput("xml_primary_key", $kvArgs{hostname}, $kvArgs{originalId} );	
		my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );

		if ( lc( $id ) eq lc( $originalId ) || !$sp->checkIfExists( $id ) ) {
			if ( 
				!$sp->setElement(	
					hostname => $id,  
					strip0 => $kvArgs{strip0},	
					strip1 => $kvArgs{strip1}, 
					strip2 => $kvArgs{strip2},
					orig_hostname => $originalId, 
				) 
			) {
				$message = $sp->{errmsg};
				setUserAction( action => 'edit strip', comment => "Got error '$message' while trying to edit strip for '$originalId'");
			} else {
				setUserAction( action => 'edit strip', comment => "Edited strip for '$originalId'");
			}
		} else {
			$message = "A strip with the same name already exists.";
		}
		
	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			originalId => $originalId
		}
	};	
}

sub deleteStrips {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );

	if ( right("write") && $kvArgs{id} ) {
		$id = sanitizeInput("xml_primary_key", $kvArgs{id} );
			
		if ( !$sp->deleteElement( $id ) ) {
			$message = $sp->{errmsg};
			setUserAction( action => 'delete strip', comment => "Got error '$message' while trying to delete strip for '$id'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete strip', comment => "Deleted strip for '$id'");
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

sub searchStrips {
	my ( %kvArgs) = @_;
	my ( $vars, @strips );

	
	my $tt = Taranis::Template->new;
	my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );

	my $unsortedStrips = $sp->loadCollection( $kvArgs{search_hostname} );
	@strips = sort { $$a{'hostname'} cmp $$b{'hostname'} } @$unsortedStrips if ( $unsortedStrips );
	
	$vars->{stripsList} = \@strips;
	$vars->{numberOfResults} = scalar @strips;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('strips.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

sub getStripsItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id, $originalId );

	my $tt = Taranis::Template->new;
	my $sp = Taranis::Config::XMLGeneric->new( Config->{stripsconfig}, "hostname", "strips" );
	
	my $insertNew = $kvArgs{insertNew};
	
 	( $id, $originalId ) = sanitizeInput("xml_primary_key", $kvArgs{id}, $kvArgs{originalId} );

	my $strips = $sp->getElement( $id );
	 
	if ( $strips ) {
		$vars->{strips} = $strips;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'strips_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id,
			originalId=> $originalId
		}
	};
}

1;
