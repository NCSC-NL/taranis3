#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use JSON;
use Taranis::Template;
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);

my @EXPORT_OK = qw(
	displayFeedDigests openDialogNewFeedDigest openDialogFeedDigestDetails
	addFeedDigest saveFeedDigest deleteFeedDigest
);

sub feed_digest_export {
	return @EXPORT_OK;
}

sub displayFeedDigests {
	my ( %kvArgs) = @_;	
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $stmnt = "SELECT * FROM feeddigest ORDER BY sending_hour;";
	
	Database->prepare( $stmnt );
	Database->executeWithBinds();
	my @feeds;
	while ( Database->nextRecord() ) {
		my $record = Database->getRecord();
		push @feeds, $record;
	}
	
	$vars->{write_right} = right("write");
	$vars->{feeds} = \@feeds;
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('feed_digest_overview.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('feed_digest_filters.tt', $vars, 1);
	
	my @js = ('js/feed_digest.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewFeedDigest {
	my ( %kvArgs) = @_;	
	my ( $vars, $tpl );
	my $oTaranisTemplate = Taranis::Template->new;

	$vars->{notafter} = Config->{notafter};
	$vars->{notbefore} = Config->{notbefore};
	
	my $dialogContent = $oTaranisTemplate->processTemplate('feed_digest_details.tt', $vars, 1);
	return { dialog => $dialogContent };
}

sub openDialogFeedDigestDetails {
	my ( %kvArgs) = @_;	
	my ( $vars, $tpl, $id );
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $stmnt = "SELECT * FROM feeddigest WHERE id = ?;";
		
		Database->prepare( $stmnt );
		Database->executeWithBinds( $id );
		
		$vars->{feed} = Database->fetchRow();

		$vars->{notafter} = Config->{notafter};
		$vars->{notbefore} = Config->{notbefore};

		$tpl = 'feed_digest_details.tt';
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}	
	
	return { 
		dialog => $oTaranisTemplate->processTemplate($tpl, $vars, 1),
		params => {
			id => $id,
			writeRight => right("write")
		} 
	};
}

sub addFeedDigest {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message );
	
	my $addOk = 0;
	
	my $writeRight = right("write");
	
	if ( 
		$writeRight
		&& $kvArgs{url} 
		&& $kvArgs{to_address} 
		&& $kvArgs{sending_hour} =~ /^\d+$/ 
		&& $kvArgs{strip_html} =~ /^(0|1)$/ 
	) {
		
		my %insert = (
			url => $kvArgs{url},
			to_address => $kvArgs{to_address},
			sending_hour => $kvArgs{sending_hour},
			strip_html => $kvArgs{strip_html},
			template_header => $kvArgs{template_header},
			template_feed_item => $kvArgs{template_feed_item},
			template_footer => $kvArgs{template_footer}
		);
		
		if ( my $feedID = Database->addObject('feeddigest', \%insert, 1) ) {
			$vars->{renderItemContainer} = 1;
			$vars->{write_right} = $writeRight;
			$vars->{feed} = {
				url => $kvArgs{url},
				sending_hour => $kvArgs{sending_hour},
				id => $feedID
			};
			
			my $oTaranisTemplate = Taranis::Template->new;
			$itemHtml = $oTaranisTemplate->processTemplate( 'feed_digest_item.tt', $vars, 1 );
			$addOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "Invalid input for new feed.";
	}
	
	if ( $addOk ) {
		setUserAction( action => 'add feed digest', comment => "Added feed $kvArgs{url}");
	} else {
		setUserAction( action => 'add feed digest', comment => "Got error $message while trying to add feed $kvArgs{url}");
	}

	return {
		params => {
			message => $message,
			addOk => $addOk,
			itemHtml => $itemHtml
		}
	};
}

sub saveFeedDigest {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message, $id );
	
	my $saveOk = 0;
	
	if (
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{url} 
		&& $kvArgs{to_address} 
		&& $kvArgs{sending_hour} =~ /^\d+$/ 
		&& $kvArgs{strip_html} =~ /^(0|1)$/ 
	) {
		$id = $kvArgs{id};
		my %update = (
			url => $kvArgs{url},
			to_address => $kvArgs{to_address},
			sending_hour => $kvArgs{sending_hour},
			strip_html => $kvArgs{strip_html},
			template_header => $kvArgs{template_header},
			template_feed_item => $kvArgs{template_feed_item},
			template_footer => $kvArgs{template_footer}
		);
		
		if ( Database->setObject('feeddigest', { id => $id }, \%update ) ) {
			$vars->{feed} = {
				url => $kvArgs{url},
				sending_hour => $kvArgs{sending_hour},
				id => $id
			};			
			$vars->{write_right} = 1;
			
			my $oTaranisTemplate = Taranis::Template->new;
			$itemHtml = $oTaranisTemplate->processTemplate( 'feed_digest_item.tt', $vars, 1 );
			$saveOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}
	
	if ( $saveOk ) {
		setUserAction( action => 'edit feed digest', comment => "Edited feed $kvArgs{url}");
	} else {
		setUserAction( action => 'edit feed digest', comment => "Got error $message while trying to edit feed $kvArgs{url}");
	}	

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			itemHtml => $itemHtml,
			id => $id
		}
	};
}
sub deleteFeedDigest {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		if ( Database->deleteObject( 'feeddigest', { id => $id } ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete feed digest', comment => "Deleted feed $kvArgs{url}");
	} else {
		setUserAction( action => 'delete feed digest', comment => "Got error $message while trying to delete feed $kvArgs{url}");
	}

	return {
		params => {
			message => $message,
			deleteOk => $deleteOk,
			id => $id
		}
	};
}

1;
