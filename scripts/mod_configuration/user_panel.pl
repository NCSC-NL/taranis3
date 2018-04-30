#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Category;
use Taranis::AssessCustomSearch;
use Taranis::Assess;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(checkUserPassCombination generatePasswordHash);
use JSON;

my @EXPORT_OK = qw( openDialogUserSettings changePassword saveSearch deleteSearch saveAssessRefreshSetting );

sub user_panel_export {
	return @EXPORT_OK;
}

sub openDialogUserSettings {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
	
	my $userId = sessionGet('userid');

	my @allowedCategorieIds;
	my @assessCategoriesFromSession = @{ getSessionUserSettings()->{assess_categories} };
		
	foreach my $categoryFromSession ( @assessCategoriesFromSession ) {
		push @allowedCategorieIds, $categoryFromSession->{id};
	}
		
	@{ $vars->{all_categories} } = @assessCategoriesFromSession;
	@{ $vars->{all_sources} } = $oTaranisAssess->getDistinctSources( \@allowedCategorieIds );
		
	my $searches = $oTaranisAssessCustomSearch->loadCollection( created_by => $userId );
		
	foreach my $search ( @$searches ) {
		$search->{checku} = 1 if ( substr( $search->{uriw}, 0, 1 ) eq "1" );
		$search->{checkr} = 1 if ( substr( $search->{uriw}, 1, 1 ) eq "1" );
		$search->{checki} = 1 if ( substr( $search->{uriw}, 2, 1 ) eq "1" );
		$search->{checkw} = 1 if ( substr( $search->{uriw}, 3, 1 ) eq "1" );
	}
		
	$vars->{searches} = $searches;
		
	my $userSettings = $oTaranisUsers->getUser( $userId );
	$vars->{assess_autorefresh} = $userSettings->{assess_autorefresh};

	$vars->{username} = $userId;
	my $dialogContent = $oTaranisTemplate->processTemplate( 'user_panel.tt', $vars, 1 );
	
	return { dialog => $dialogContent };
}

sub changePassword {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $oTaranisUsers = Taranis::Users->new(Config);
	my $username = sessionGet('userid');

	my $changeOk = 0;
	
	if ($kvArgs{current_pwd} && $kvArgs{new_pwd}) {
		if (Taranis::Users::checkUserPassCombination($username, $kvArgs{current_pwd})) {
			my $newHash = Taranis::Users::generatePasswordHash($kvArgs{new_pwd});

			if (!$oTaranisUsers->setUser( username => $username, password => $newHash)) {
				$message = $oTaranisUsers->{errmsg};
			}
		} else {
			$message = "Username/password does not match current password.";
		}
	} else {
		$message = 'Invalid input';
	}
	
	$changeOk = 1 if ( !$message );	
	return { 
		params => {
			changeOk => $changeOk,
			message => $message
		}
	}
}

sub saveSearch {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
	my $saveOk = 0;
	
	my $jsonString = $kvArgs{customSearch};
	
	$jsonString =~ s/&quot;/"/g;
	my $customSearch = from_json( $jsonString );

	if ( $customSearch->{startdate} ) {
		$customSearch->{startdate} = formatDateTimeString( $customSearch->{startdate} );
	} else {
		$customSearch->{startdate} = undef;
	}
	
	if ( $customSearch->{enddate} ) {
		$customSearch->{enddate} = formatDateTimeString( $customSearch->{enddate} );
	} else {
		$customSearch->{enddate} = undef;
	}
	
	if ( !$oTaranisAssessCustomSearch->setSearch( %$customSearch ) ) {
		$message = $oTaranisAssessCustomSearch->{errmsg};
	}
	
	$saveOk = 1 if ( !$message );	
	return { 
		params => {
			saveOk => $saveOk,
			message => $message,
			searchSettings => $customSearch
		}
	}	
}

sub deleteSearch {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
	my $deleteOk = 0;
	
	my $searchId = $kvArgs{searchId};
	
	if ( !$oTaranisAssessCustomSearch->deleteSearch( $searchId ) ) {
		$message = $oTaranisAssessCustomSearch->{errmsg};
	}
	
	$deleteOk = 1 if ( !$message );	
	return { 
		params => {
			deleteOk => $deleteOk,
			message => $message,
			searchId => $searchId
		}
	}
}

sub saveAssessRefreshSetting {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $saveOk = 0;
	
	my $assessAutoRefresh = ( $kvArgs{assess_autorefresh} =~ /^(1|0)$/ ) ? $kvArgs{assess_autorefresh} : 1;
	
	if ( !$oTaranisUsers->setUser( username => sessionGet('userid'), assess_autorefresh => $assessAutoRefresh ) ) {
		$message = $oTaranisUsers->{errmsg};
	}	
	
	$saveOk = 1 if ( !$message );	
	return { 
		params => {
			saveOk => $saveOk,
			message => $message
		}
	}
}

1;
