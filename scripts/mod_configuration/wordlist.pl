#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Wordlist;
use JSON;

use strict;

my @EXPORT_OK = qw( 
	displayWordlists openDialogNewWordlist openDialogWordlistDetails 
	saveNewWordlist saveWordlistDetails deleteWordlist getWordlistItemHtml searchWordlist
);

sub wordlist_export {
	return @EXPORT_OK;
}

sub displayWordlists {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisWordlist = Taranis::Wordlist->new( Config );
	
	my $wordlists = $oTaranisWordlist->getWordlist();

	foreach my $wordlist ( @$wordlists ) {
		$wordlist->{canDelete} = 
			( 
				$oTaranisWordlist->{dbh}->checkIfExists( { wordlist_id => $wordlist->{id} }, 'source_wordlist' )
				|| $oTaranisWordlist->{dbh}->checkIfExists( { and_wordlist_id => $wordlist->{id} }, 'source_wordlist' )
			)
			? 0
			: 1;
	}

	$vars->{wordlists} = $wordlists;
	$vars->{numberOfResults} = scalar @$wordlists;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('wordlist.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('wordlist_filters.tt', $vars, 1);
	
	my @js = ('js/wordlist.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewWordlist {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'wordlist_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub openDialogWordlistDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisWordlist = Taranis::Wordlist->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		$id = $kvArgs{id};
		my $wordlist = $oTaranisWordlist->getWordlist( id => $id );

		if ( ref( $wordlist ) =~ /^ARRAY$/ && @$wordlist ) {
			$vars->{wordlist} = $wordlist->[0];
		} else {
			$vars->{message} = $oTaranisWordlist->{errmsg};
		}

		$tpl = 'wordlist_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}
	};
}

sub saveNewWordlist {
	my ( %kvArgs) = @_;
	my ( $message, $wordlistID );
	my $saveOk = 0;
	
	
	my $description = trim( $kvArgs{description} );
	
	if ( right("write") && $description ) {

		my $oTaranisWordlist = Taranis::Wordlist->new( Config );

		if ( !$oTaranisWordlist->{dbh}->checkIfExists( { description => $description }, "wordlist", "IGNORE_CASE" ) ) {

			my @words = sort( split("\n", $kvArgs{wordlist} ) );

			if ( $wordlistID = $oTaranisWordlist->addWordlist(
					description => $description,
					words_json => to_json( $oTaranisWordlist->cleanWordlist( \@words ) )
				)
			) {
				setUserAction( action => 'add wordlist', comment => "Added wordlist $description");
			} else {
				$message = $oTaranisWordlist->{errmsg};
				setUserAction( action => 'add wordlist', comment => "Got error $message while trying to add wordlist with description $description");
			}
		} else {
			$message = "A wordlist with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $wordlistID,
			insertNew => 1
		}
	};
}

sub saveWordlistDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	my $description = trim( $kvArgs{description} );
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ && $description ) {
		$id = $kvArgs{id};
		my $oTaranisWordlist = Taranis::Wordlist->new( Config );

		my @words = sort( split("\n", $kvArgs{wordlist} ) );

		my %wordlistUpdate = (
			id => $kvArgs{id},
			description => $description,
			words_json => to_json( $oTaranisWordlist->cleanWordlist( \@words ) )
		);
		
		if ( !$oTaranisWordlist->{dbh}->checkIfExists( { description => $description, id => {'!=' => $id } } , "wordlist", "IGNORE_CASE" )	) {
			
			if ( !$oTaranisWordlist->setWordlist( %wordlistUpdate ) ) {
				$message = $oTaranisWordlist->{errmsg};
				setUserAction( action => 'edit wordlist', comment => "Got error $message while trying to edit wordlist $description");
			} else {
				setUserAction( action => 'edit wordlist', comment => "Edited wordlist $description");
			} 
		} else {
			$message = "A wordlist with the same description already exists.";
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

sub deleteWordlist {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $oTaranisWordlist = Taranis::Wordlist->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $wordlist = $oTaranisWordlist->getWordlist( id => $id );
		if ( ref( $wordlist ) =~ /^ARRAY$/ && @$wordlist ) {
			if (  !$oTaranisWordlist->deleteWordlist( $kvArgs{id} ) ) {
				$message = $oTaranisWordlist->{errmsg};
				setUserAction( action => 'delete wordlist', comment => "Got error '$message' while trying to delete wordlist $wordlist->[0]->{description}");
			} else {
				$deleteOk = 1;
				setUserAction( action => 'delete wordlist', comment => "Deleted wordlist $wordlist->[0]->{description}");
			}
		} else {
			$message = 'Say what?!';
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

sub getWordlistItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisWordlist = Taranis::Wordlist->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $wordlist = $oTaranisWordlist->getWordlist( id => $id );
 
	if ( ref( $wordlist ) =~ /^ARRAY$/ && @$wordlist ) {

		$wordlist->[0]->{canDelete} = 
			( 
				$oTaranisWordlist->{dbh}->checkIfExists( { wordlist_id => $wordlist->[0]->{id} }, 'source_wordlist' )
				|| $oTaranisWordlist->{dbh}->checkIfExists( { and_wordlist_id => $wordlist->[0]->{id} }, 'source_wordlist' )
			)
			? 0
			: 1;
		
		$vars->{wordlist} = $wordlist->[0];

		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'wordlist_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}

sub searchWordlist {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisWordlist = Taranis::Wordlist->new( Config );
	
	my $search = '%' . trim($kvArgs{search}) . '%';
	
	my $wordlists = $oTaranisWordlist->getWordlist( words_json => { -ilike => $search } );

	foreach my $wordlist ( @$wordlists ) {
		$wordlist->{canDelete} = 
			( 
				$oTaranisWordlist->{dbh}->checkIfExists( { wordlist_id => $wordlist->{id} }, 'source_wordlist' )
				|| $oTaranisWordlist->{dbh}->checkIfExists( { and_wordlist_id => $wordlist->{id} }, 'source_wordlist' )
			)
			? 0
			: 1;
	}

	$vars->{wordlists} = $wordlists;
	$vars->{numberOfResults} = scalar @$wordlists;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('wordlist.tt', $vars, 1);
	
	return { 
		content => $htmlContent
	};
}

1;
