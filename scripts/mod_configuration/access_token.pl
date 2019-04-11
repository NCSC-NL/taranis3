#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use JSON;
use Taranis::REST::AccessToken;
use Taranis::Template;
use Taranis::Users qw();
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);

my @EXPORT_OK = qw(
	displayTokens openDialogNewToken openDialogTokenDetails
	saveNewToken saveTokenDetails deleteToken getTokenItemHtml
);

sub access_token_export {
	return @EXPORT_OK;
}

sub displayTokens {
	my ( %kvArgs) = @_;	
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );
	
	my $tokens = $oTaranisAccessToken->getAccessToken();
	
	$vars->{write_right} = right("write");
	$vars->{tokens} = $tokens;
	$vars->{numberOfResults} = scalar @$tokens;
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('access_token.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('access_token_filters.tt', $vars, 1);
	
	my @js = ('js/access_token.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewToken {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $users = $oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}  
		$vars->{users} = \@users;
		
		$tpl = 'access_token_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate('access_token_details.tt', $vars, 1);
	return { 
		dialog => $dialogContent,
		params => {	writeRight => $writeRight } 
	};
}

sub openDialogTokenDetails {
	my ( %kvArgs) = @_;	
	my ( $vars, $tpl, $token );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	
	if ( $kvArgs{token} ) {
		$token = $kvArgs{token};
		
		my $accessToken = $oTaranisAccessToken->getAccessToken( token => $token );

		if(ref $accessToken eq 'ARRAY' && @$accessToken == 1 ) {
			$vars->{token} = $accessToken->[0];
		}
		
		my $users = $oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}  
		$vars->{users} = \@users;
		
		$tpl = 'access_token_details.tt';
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}	
	
	return { 
		dialog => $oTaranisTemplate->processTemplate($tpl, $vars, 1),
		params => {
			token => $token,
			writeRight => right("write")
		} 
	};
}

sub saveNewToken {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message );

	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );

	my $saveOk = 0;
	
	my $writeRight = right("write");

	my $token = $oTaranisAccessToken->generateAccessToken();
	if ( 
		$writeRight
		&& $kvArgs{username}
 	) {
		
		my %insert = (
			username => $kvArgs{username},
			token => $token,
			expiry_time => $kvArgs{expiry_time} || undef
		);
		
		if ( $oTaranisAccessToken->addAccessToken( %insert ) ) {
			
			$saveOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "Invalid input for new token.";
	}
	
	if ( $saveOk ) {
		setUserAction( action => 'add access token', comment => "Added token for $kvArgs{username}");
	} else {
		setUserAction( action => 'add access token', comment => "Got error $message while trying to add token for $kvArgs{username}");
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			insertNew => 1,
			token => $token
		}
	};
}

sub saveTokenDetails {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message, $token );
	
	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );
	
	my $saveOk = 0;

	if (
		right("write")
		&& $kvArgs{token}
		&& $kvArgs{username}
		&& ( $kvArgs{expiry_time} =~ /^\d+$/ || !$kvArgs{expiry_time} )
	) {
		$token = $kvArgs{token};
		my %update = (
			username => $kvArgs{username},
			token => $token,
			expiry_time => $kvArgs{expiry_time} || undef
		);
		
		if ( $oTaranisAccessToken->setAccessToken( %update ) ) {
			$saveOk = 1;
		} else {
			$message = $oTaranisAccessToken->{errmsg};
		}
		
	} else {
		$message = "No permission.";
	}
	
	if ( $saveOk ) {
		setUserAction( action => 'edit token', comment => "Edited token for $kvArgs{username}");
	} else {
		setUserAction( action => 'edit token', comment => "Got error $message while trying to edit token for $kvArgs{username}");
	}	

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			token => $token
		}
	};
}

sub deleteToken {
	my ( %kvArgs) = @_;
	my ( $message, $token );

	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{token} ) {
		$token = $kvArgs{token};
		
		if ( $oTaranisAccessToken->deleteAccessToken( $token ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete token', comment => "Deleted token $kvArgs{token}");
	} else {
		setUserAction( action => 'delete token', comment => "Got error $message while trying to delete token $kvArgs{token}");
	}

	return {
		params => {
			message => $message,
			deleteOk => $deleteOk,
			id => $token
		}
	};
}

sub getTokenItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAccessToken = Taranis::REST::AccessToken->new( Config );
		
	my $token = $kvArgs{token};
	my $insertNew = $kvArgs{insertNew};
 
	my $accessToken = $oTaranisAccessToken->getAccessToken( token => $token );

	if(ref $accessToken eq 'ARRAY' && @$accessToken == 1 ) {
		$vars->{token} = $accessToken->[0];

		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'access_token_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $token
		}
	};
}

1;
