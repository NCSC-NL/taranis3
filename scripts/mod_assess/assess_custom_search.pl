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
		
		my ( $uriw, $checku, $checkr, $checki, $checkw, @statuses );
		if ( exists( $kvArgs{item_status} ) ) {
			if ( ref( $kvArgs{item_status} ) =~ /^ARRAY$/ ) {
				@statuses = @{ $kvArgs{item_status} };
			} else{
				push @statuses, $kvArgs{item_status};
			}
			
			foreach ( @statuses ) {
				if ( /0/) { $checku = 1; }
				if ( /1/) { $checkr = 1; }
				if ( /2/) { $checki = 1; }
				if ( /3/) { $checkw = 1; } 
			}		
		} 

	    $uriw  = ( $checku ) ? "1" : "0";
	    $uriw .= ( $checkr ) ? "1" : "0";
	    $uriw .= ( $checki ) ? "1" : "0";
	    $uriw .= ( $checkw ) ? "1" : "0";
		
		my $startdate = ( exists( $kvArgs{startdate} ) && $kvArgs{startdate} =~ /\d\d-\d\d-\d\d\d\d/ ) 
			? formatDateTimeString( $kvArgs{startdate} ) 
			: undef;
		my $enddate = ( exists( $kvArgs{enddate} ) && $kvArgs{enddate} =~ /\d\d-\d\d-\d\d\d\d/ ) 
			? formatDateTimeString( $kvArgs{enddate} ) 
			: undef;
		
		my @sources;
		if ( exists( $kvArgs{sources_left_column} ) ) {
			if ( ref( $kvArgs{sources_left_column} ) =~ /^ARRAY$/ ) {
				@sources = @{ $kvArgs{sources_left_column} };
			} else{
				push @sources, $kvArgs{sources_left_column};
			}
		}
		
		my @categories;
		if ( exists( $kvArgs{categories_left_column} ) ) {
			if ( ref( $kvArgs{categories_left_column} ) =~ /^ARRAY$/ ) {
				@categories = @{ $kvArgs{categories_left_column} };
			} else{
				push @categories, $kvArgs{categories_left_column};
			}
		}		
		my $sorting = ( exists( $kvArgs{sorting} ) ) ? $kvArgs{sorting} : undef;
		my $keywords = ( exists( $kvArgs{keywords} ) ) ? $kvArgs{keywords} : undef;
		$description = ( exists( $kvArgs{description} ) ) ? $kvArgs{description} : undef;
		my $isPublic = ( exists( $kvArgs{is_public} ) ) ? $kvArgs{is_public} : undef;
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
