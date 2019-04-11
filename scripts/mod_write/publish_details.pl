#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Publish;
use Taranis::CallingList qw(getCallingList getPublicationLists);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config Database Publish Template);
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use Taranis qw(:all);
use CGI::Simple;
use JSON;
use strict;

my @EXPORT_OK = qw( 
	openDialogPublishingDetails saveCallDetails	downloadPublishDetails 
	setCallLockState releaseAllCallLocks adminRemoveCallLock 
);

sub publish_details_export {
	return @EXPORT_OK; 
}

sub openDialogPublishingDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $executeRight = right("execute"); 

	my $publicationId = $kvArgs{id};
	my $publicationType= $kvArgs{pt};
	
	if ( $executeRight && $publicationId =~ /^\d+$/ ) {

		my $userId = sessionGet('userid');

		$vars->{is_admin} = getUserRights( 
				entitlement => "admin_generic", 
				username => $userId 
			)->{admin_generic}->{write_right};	
		
		my $publishDetails = Publish->getPublishDetails( $publicationId, $publicationType );

		my $additionalDetails = "";

		$vars->{details} = $publishDetails;
		$vars->{user} = $userId;
		$vars->{additional_details} = $additionalDetails;	
		$vars->{calling_list} = getCallingList($publicationId);

		$tpl = 'publish_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = Template->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { 
			executeRight => $executeRight,
			publicationId => $publicationId,
			publicationType => $publicationType,
			canUnlock => $vars->{is_admin}
		}  
	};	
}

sub saveCallDetails {
	my ( %kvArgs ) = @_;
	my ( $message, $list );

	my $saveOk = 0;
	
	if ( right("execute") && $kvArgs{id} =~ /^\d+$/ ) {
		my $publishDetails = Publish->getPublishDetails( $kvArgs{publicationId}, 'advisory' );

		Database->simple->update(
			-table => 'calling_list',
			-set => {
				comments => $kvArgs{comments},
				is_called => $kvArgs{isCalled},
				locked_by => undef
			},
			-where => {
				id => $kvArgs{id},
			},
		);
		$list = getPublicationLists($kvArgs{publicationId});
		setUserAction( action => "edit call details", comment => "Edited call details of '$publishDetails->{publication}->{pub_title}'" );
	} else {
		$message = 'No permission.';
	}

	$saveOk = 1 if ( !$message );

	return {
		params => {
			list => $list,
			saveOk => $saveOk,
			message => $message,
			callId => $kvArgs{id}
		}
	};	
}

sub downloadPublishDetails {
	my ( %kvArgs ) = @_;
	my ( $vars );

	my $publicationId = $kvArgs{id};
	my $publicationType= $kvArgs{pt};
		
	my $publishDetails = Publish->getPublishDetails( $publicationId, $publicationType );

	setUserAction( action => "download publish details", comment => "Downloaded publishing details of '$publishDetails->{publication}->{pub_title}'" );

	$vars->{details} = $publishDetails;

	print CGI->header(
		-content_disposition => 'attachment; filename="publishing_details.txt"',
		-type => 'text/plain',
	);
	print Template->processTemplate( "publish_details_savefile.tt", $vars, 1 );

	return {};
}

sub setCallLockState {
	my ( %kvArgs ) = @_;
	my ( $message, $list, $callId, $lockState );

	my $lockSetOk = 0;
	my $isLocked = 0;
	
	if ( 
		right("execute") 
		&& $kvArgs{id} =~ /^\d+$/ 
		&& $kvArgs{publicationId} =~ /^\d+$/ 
		&& $kvArgs{'state'} =~ /^(set|release)$/ 
	) {
		
		my $userId = sessionGet('userid');
		my $publicationId = $kvArgs{publicationId};
		$lockState = $kvArgs{'state'};
		$callId = $kvArgs{id};
				
		$list = getPublicationLists($publicationId);

		foreach my $call ( @$list ) {
			if ( $call->{id} == $callId ) {
				if ( $call->{locked_by} && $call->{locked_by} ne $userId ) {
					$isLocked = 1;
				} else {
					undef $call->{locked_by};
				}
			}	
		}

		if ( !$isLocked ) {
			Database->simple->update(
				-table => 'calling_list',
				-set => {
					locked_by => $lockState =~ /^set$/ ? $userId : undef,
				},
				-where => {
					id => $callId
				},
			);
		}

	} else {
		$message = 'No permission.';
	}
	
	$lockSetOk = 1 if ( !$message );
	
	return {
		params => {
			lockSetOk => $lockSetOk,
			message => $message,
			list => $list,
			callId => $callId,
			isLocked => $isLocked,
			lockState => $lockState
		}
	};	
}

sub releaseAllCallLocks {
	my ( %kvArgs ) = @_;
	my ( $message );

	my $saveOk = 0;
	
	if ( right("execute") && $kvArgs{publicationId} =~ /^\d+$/ ) {
		Database->simple->update(
			-table => 'calling_list',
			-set => {
				locked_by => undef,
			},
			-where => {
				publication_id => $kvArgs{publicationId},
				user => sessionGet('userid'),
			},
		);
	} else {
		$message = 'No permission.';
	}
	
	$saveOk = 1 if ( !$message );
	
	return {};
}

sub adminRemoveCallLock {
	my ( %kvArgs ) = @_;
	my ( $message, $list );

	my $removeOk = 0;
	
	if ( right("execute") && $kvArgs{publicationId} =~ /^\d+$/ && $kvArgs{id} =~ /^\d+$/ ) {
		my $publicationId = $kvArgs{publicationId};
		
		if ( getUserRights( entitlement => "admin_generic", username => sessionGet('userid') )->{admin_generic}->{write_right} ) {
			Database->simple->update(
				-table => 'calling_list',
				-set => {
					locked_by => undef,
				},
				-where => {
					id => $kvArgs{id},
				},
			);
		} else {
			$message = "You do not have the right privileges for this action.";					
		}
		
		$list = getPublicationLists($publicationId);
		
	} else {
		$message = 'No permission.';
	}

	$removeOk = 1 if ( !$message );

	return {
		params => {
			removeOk => $removeOk,
			message => $message,
			callId => $kvArgs{id},
			list => $list
		}
	};
}

1;
