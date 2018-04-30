#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Entitlement;
use Taranis::Template;
use Taranis::Users;
use Time::Local;

my @EXPORT_OK = qw( displayUserActions searchUserActions );

my $maxNumberOfItemsOnPage = 100;

sub user_actions_export {
	return @EXPORT_OK;
}

sub displayUserActions {
	my ( %kvArgs) = @_;
	my ( $vars, @userActions, @users, @entitlements );
	
	my $tt = Taranis::Template->new;
	my $en = Taranis::Entitlement->new( Config );
	my $us = Taranis::Users->new( Config );
	
	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;
	
	my $offset = ( $pageNumber - 1 ) * $maxNumberOfItemsOnPage;
	$us->getUserActions( limit => $maxNumberOfItemsOnPage, offset => $offset );
	
	while ( $us->nextObject() ) {
		push @userActions, $us->getObject();
	}
	$vars->{userActions} = \@userActions;

	$us->getUsersList();
	while ( $us->nextObject() ) {
		my $user = $us->getObject();
		push @users, { username => $user->{username}, fullname => $user->{fullname} }
	}
	$vars->{users} = \@users;

	$en->getEntitlement();
	while ( $en->nextObject() ) {
	    push @entitlements, $en->getObject();
	}
	$vars->{entitlements} = \@entitlements;
	
	my $userActionsCount = $us->getUserActionsCount();
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $userActionsCount, $maxNumberOfItemsOnPage );
	$vars->{filterButton} = 'btn-user-actions-search';
	$vars->{numberOfResults} = $userActionsCount;
	
	my $htmlContent = $tt->processTemplate('logging_user_actions.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('logging_user_actions_filters.tt', $vars, 1);
	
	my @js = ('js/logging_user_actions.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };		
}
	
sub searchUserActions {
	my ( %kvArgs, %search ) = @_;
	my ( $vars, @userActions );

	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	if ( exists( $kvArgs{startdate} ) ) {
		$search{startDate} = ( checkDate( $kvArgs{startdate} ) ) ? formatDateTimeString( $kvArgs{startdate} ): undef;
	}
	if ( exists( $kvArgs{enddate} ) ) {
		$search{endDate} = ( checkDate( $kvArgs{enddate} ) ) ? formatDateTimeString( $kvArgs{enddate} ): undef;
	}	

	$search{'ua.username'} = $kvArgs{username} if ( $kvArgs{username} );
	$search{'ua.entitlement'} = $kvArgs{entitlement} if ( $kvArgs{entitlement} );

	if ( exists( $kvArgs{searchkeywords} ) && $kvArgs{searchkeywords} ) { 
		$search{-or} = {
			'ua.action' => {'-ilike' => '%' . trim($kvArgs{searchkeywords}) . '%'},
			'ua.comment' => {'-ilike' => '%' . trim($kvArgs{searchkeywords}) . '%'}
		}
	}
	
	my $userActionsCount = $us->getUserActionsCount( %search );
	
	$search{limit} = $maxNumberOfItemsOnPage;
	$search{offset} = ( $pageNumber - 1 ) * $maxNumberOfItemsOnPage;
	
	$us->getUserActions( %search );
	while ( $us->nextObject() ) {
		push @userActions, $us->getObject();
	}
	$vars->{userActions} = \@userActions;
	
	$vars->{filterButton} = 'btn-user-actions-search';
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $userActionsCount, $maxNumberOfItemsOnPage );
	$vars->{numberOfResults} = $userActionsCount;

	my $htmlContent = $tt->processTemplate('logging_user_actions.tt', $vars, 1);

	return { content => $htmlContent };
}

# expects a string as dd-mm-yyyy
sub checkDate {
	my ( $dateString ) = @_;

	$dateString =~ s/-//g;
	my ( $day, $month, $year ) = unpack( "A2 A2 A4", $dateString );
	
	eval{ 
	    timelocal(0,0,0,$day, $month-1, $year);
	};

	return ( $@ ) ? 0 : 1;
}

1;
