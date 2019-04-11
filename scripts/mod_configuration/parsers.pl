#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Parsers;
use Taranis::Sources;
use URI::Escape;

my @EXPORT_OK = qw( 
	displayParsers openDialogNewParser openDialogParserDetails
	saveNewParser saveParserDetails deleteParser
	searchParsers getParserItemHtml 
);

sub parsers_export {
	return @EXPORT_OK;
}

sub displayParsers {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $ps = Taranis::Parsers->new( Config );
	my $tt = Taranis::Template->new;
	
	my $parsers = $ps->getParsers();
	$vars->{parsers} = $parsers;
	$vars->{numberOfResults} = scalar @$parsers;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('parsers.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('parsers_filters.tt', $vars, 1);
	
	my @js = ('js/parsers.js');

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewParser {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {

		$tpl = 'parsers_details.tt';
		
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

sub openDialogParserDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( exists( $kvArgs{id} ) && $kvArgs{id} ) {
		$id = $kvArgs{id};

		my $ps = Taranis::Parsers->new( Config );
		my $src	= Taranis::Sources->new( Config );

		my $parser = $ps->getParserSimple( $id );
		
		$vars->{parser} = $parser;
		$vars->{sources} = $src->getSources( parser => $id );
		$vars->{write_right} = $writeRight;
        
		$tpl = 'parsers_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input';
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

sub saveNewParser {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && exists( $kvArgs{parsername} ) && $kvArgs{parsername} ) {
		$id = $kvArgs{parsername};
		my $ps = Taranis::Parsers->new( Config );
		
		if ( !$ps->{dbh}->checkIfExists( { parsername => $kvArgs{parsername} }, "parsers", "IGNORE_CASE" ) ) {
		
			if (
				!$ps->addParser(
					parsername => $kvArgs{parsername}, 
					item_start => $kvArgs{item_start},	
					item_stop => $kvArgs{item_stop}, 
					title_start => $kvArgs{title_start},
					title_stop => $kvArgs{title_stop},
					desc_start => $kvArgs{desc_start},
					desc_stop => $kvArgs{desc_stop},
					link_start => $kvArgs{link_start},
					link_stop => $kvArgs{link_stop},
					link_prefix => $kvArgs{link_prefix},
					strip0_start => $kvArgs{strip0_start},
					strip0_stop => $kvArgs{strip0_stop},													
					strip1_start => $kvArgs{strip1_start},
					strip1_stop => $kvArgs{strip1_stop},
					strip2_start => $kvArgs{strip2_start},
					strip2_stop => $kvArgs{strip2_stop},													
				) 
			) {
				$message = $ps->{errmsg};
				setUserAction( action => 'add parser', comment => "Got error '$message' while trying to add parser '$id'");
			} else {
				setUserAction( action => 'add parser', comment => "Added parser '$id'");
			}
		} else {
			$message = "A parser with the same name already exists.";
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
			insertNew => 1
		}
	};
}

sub saveParserDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} ) {
		$id = $kvArgs{id};
		my $ps = Taranis::Parsers->new( Config );

		if ( 
			!$ps->setParser(
				parsername => $id,
				item_start => $kvArgs{item_start},	
				item_stop => $kvArgs{item_stop}, 
				title_start=> $kvArgs{title_start},
				title_stop => $kvArgs{title_stop},
				desc_start => $kvArgs{desc_start},
				desc_stop => $kvArgs{desc_stop},
				link_start => $kvArgs{link_start},
				link_stop => $kvArgs{link_stop},
				link_prefix => $kvArgs{link_prefix},
				strip0_start => $kvArgs{strip0_start},
				strip0_stop => $kvArgs{strip0_stop},													
				strip1_start => $kvArgs{strip1_start},
				strip1_stop => $kvArgs{strip1_stop},
				strip2_start => $kvArgs{strip2_start},
				strip2_stop => $kvArgs{strip2_stop}
			) 
		) {
			$message = $ps->{errmsg};
			setUserAction( action => 'edit parser', comment => "Got error '$message' while trying to edit parser '$id'");
		} else {
			setUserAction( action => 'edit parser', comment => "Edited parser '$id'");
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

sub deleteParser {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	

	my $ps = Taranis::Parsers->new( Config );
	
	if ( right("write") ) {

		if ( !$ps->deleteParser( parsername => $kvArgs{id} ) ) {
			$message = $ps->{errmsg};
			setUserAction( action => 'delete parser', comment => "Got error '$message' while deleting parser '$kvArgs{id}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete parser', comment => "Deleted parser '$kvArgs{id}'");
		}

	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => uri_escape( $kvArgs{id} )
		}
	};	
}

sub searchParsers {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $tt = Taranis::Template->new;
	my $ps = Taranis::Parsers->new( Config );
	
	my $parsers = $ps->getParsers( $kvArgs{search_parsername} );
	
	$vars->{parsers} = $parsers;
	$vars->{numberOfResults} = scalar @$parsers;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('parsers.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

sub getParserItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ps = Taranis::Parsers->new( Config );
	
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

 	my $parser = $ps->getParserSimple( $id );
 	
	if ( $parser ) {
		$vars->{parser} = $parser;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'parsers_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Error: Could not find the parser...';
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
