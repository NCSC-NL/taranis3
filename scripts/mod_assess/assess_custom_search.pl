#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Assess;
use Taranis::AssessCustomSearch;
use Taranis::Session qw(sessionGet);
use strict;

my @EXPORT_OK = qw(displayCustomSearch addSearch);

sub assess_custom_search_export {
	return @EXPORT_OK; 
}

sub displayCustomSearch {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	my $tt = Taranis::Template->new;
	
	if ( right("write") ) {
		my $as = Taranis::Assess->new( Config );	
		my @allowedCategorieIds; 
		my @assessCategoriesFromSession = @{ getSessionUserSettings()->{assess_categories} };
		
		foreach my $categoryFromSession ( @assessCategoriesFromSession ) {
			push @allowedCategorieIds, $categoryFromSession->{id};
		}		
			
		@{ $vars->{all_categories} } = @assessCategoriesFromSession;
			
		@{ $vars->{all_sources} } = $as->getDistinctSources( \@allowedCategorieIds );
			
		my $today = nowstring( 5 );
		$vars->{startdate} = $today;
		$vars->{enddate} = $today;
		$vars->{hitsperpage} = 100;
		$vars->{is_public} = 0;
		$tpl = 'assess_custom_search.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = "Sorry, you do not have enough privileges to add a custom search...";
	}
	
	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);
	
	return { dialog => $dialogContent };
}

sub addSearch {
	my ( %kvArgs ) = @_;
	my $addOk = 0;
	my ( $message, $searchId, $description );

	my $cs = Taranis::AssessCustomSearch->new( Config );
	
	if ( !$cs->{dbh}->checkIfExists( {description => $kvArgs{'description'} }, "search", "IGNORE_CASE" ) ) {
		
 		my ($checku, $checkr, $checki, $checkw) = (0,0,0,0);
		my @statuses = flat $kvArgs{item_status};
		foreach ( @statuses ) {
			if ( /0/) { $checku = 1; }
			if ( /1/) { $checkr = 1; }
			if ( /2/) { $checki = 1; }
			if ( /3/) { $checkw = 1; } 
		} 
		my $uriw = join '', $checku, $checkr, $checki, $checkw;
		
		my $startdate = formatDateTimeString $kvArgs{startdate};
		my $enddate   = formatDateTimeString $kvArgs{enddate};

		my @sources    = flat $kvArgs{sources_left_column};
		my @categories = flat $kvArgs{categories_left_column};

		my $sorting  = $kvArgs{sorting};
		my $keywords = $kvArgs{keywords};
		$description = $kvArgs{description};
		my $isPublic = $kvArgs{is_public};
		my $hitsPerPage = val_int $kvArgs{hitsperpage} || 100;

		my %inserts = ( 
			description => $description,
			keywords 	=> $keywords,
			uriw 		=> $uriw,
			startdate 	=> $startdate,
			enddate 	=> $enddate,
			hitsperpage => $hitsPerPage,
			sortby 		=> $sorting,
			sources 	=> \@sources,
			categories 	=> \@categories,
			is_public 	=> $isPublic,
			created_by 	=> sessionGet('userid')							
		);			
			
		if ( !$cs->addSearch( %inserts ) ) {
			$message = $cs->{errmsg};
		} else {
			$addOk = 1;
			$searchId = $cs->{dbh}->getLastInsertedId('search');
		}
		
	} else {
		$message = "A search with the same description already exists.";
	}

	if ( $addOk ) {
		setUserAction( action => 'add search', comment => "Added search '$description'");
	} else {
		setUserAction( action => 'add search', comment => "Got error '$message' while trying to add search '$description'");
	}

	return { 
		params => { 
			message => $message, 
			search_id => $searchId, 
			search_is_added => $addOk, 
			search_description => $description
		}
	};
}

1;
