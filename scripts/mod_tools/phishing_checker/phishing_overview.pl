#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use CGI::Simple;
use SQL::Abstract::More;
use JSON;
use URI::Split qw(uri_split uri_join);

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config Database Sql);
use Taranis::Template;

my @EXPORT_OK = qw(
	displayPhishingOverview deletePhishingItem addPhishingItem loadImage 
	openDialogPhishingDetails savePhishingDetails openDialogPhishingScreenshot
);

sub phishing_overview_export {
	return @EXPORT_OK;
}

sub displayPhishingOverview {
	my ( %kvArgs) = @_;	
	my ( @items, $vars );
	
	my $tt = Taranis::Template->new;

	my $sql = "SELECT * FROM phish ORDER BY datetime_added";
	Database->prepare( $sql );
	Database->executeWithBinds();
	
	while ( Database->nextRecord() ) {
		my $record = Database->getRecord();
		my $item = $record;

		$item->{status}  = "uninitialized";
		if ( $record->{hash} ne "" ) {
			$item->{status} = "online";
		}
		$item->{dt_laststatus} = $record->{datetime_added};
		if ( ( $record->{datetime_hash_change} ne "" ) && ( $record->{counter_hash_change} >= 2 ) ) {
			$item->{status} = "hashchange";
			$item->{dt_laststatus} = $record->{datetime_hash_change};
		}
		if ( ( $record->{datetime_down} ne "" ) && ( $record->{counter_down} >= 2 ) ) {
			$item->{status} = "offline";
			$item->{dt_laststatus} = $record->{datetime_down};
		}
  
		$item->{dt_laststatus} = substr( $item->{dt_laststatus}, 6, 2 ) . "-" . substr( $item->{dt_laststatus}, 4, 2 ) .
			"-" . substr( $item->{dt_laststatus}, 0, 4 ) . " " . substr( $item->{dt_laststatus}, 8, 2 ) .
			":" . substr( $item->{dt_laststatus}, 10, 2 ) . ":" . substr( $item->{dt_laststatus}, 12, 2 );
      
		$item->{dt_added} = $record->{datetime_added};
  
		$item->{dt_added} = substr( $item->{dt_added}, 6, 2 ) . "-" . substr( $item->{dt_added}, 4, 2 ) .
			"-" . substr( $item->{dt_added}, 0, 4 ) . " " . substr( $item->{dt_added}, 8, 2 ) .
			":" . substr( $item->{dt_added}, 10, 2 ) . ":" . substr( $item->{dt_added}, 12, 2 );

		push @items, $item;
	}

	$vars->{phishingItems} = \@items;
	$vars->{renderItemContainer} = 1;
	
	$vars->{referenceIsMandatory} = ( Config->{phishreferencemandatory} =~ /^on$/i ) ? 1: 0;
	
	my $htmlContent = $tt->processTemplate('phishing_overview.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('phishing_filters.tt', $vars, 1);
	
	my @js = ('js/phishing.js', 'js/taranis.phishing.timer.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogPhishingDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	
	my $writeRight = right("write");	
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {

		my $stmnt = "SELECT * FROM phish WHERE id = ?";
		Database->prepare( $stmnt );
		Database->executeWithBinds( $kvArgs{id} );
		$vars = Database->fetchRow();
		
		my $stmntPhishImages = "SELECT *, to_char(timestamp, 'DD-MM-YYYY HH24:MI') AS timestamp_string FROM phish_image WHERE phish_id = ? ORDER BY timestamp DESC;";
		Database->prepare( $stmntPhishImages );
		Database->executeWithBinds( $kvArgs{id} );
		
		my @images;
		while ( Database->nextRecord() ) {
			push @images, Database->getRecord();
		}
		$vars->{referenceIsMandatory} = ( Config->{phishreferencemandatory} =~ /^on$/i ) ? 1: 0;
		$vars->{images} = \@images;
		
		my ( $scheme, $auth, $path, $query, $frag ) = uri_split( $vars->{url} );
		$vars->{site} = $auth;
		$tpl = 'phishing_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $kvArgs{id}
		}
	};
}

sub savePhishingDetails {
	my ( %kvArgs) = @_;
	my ( $message );
	my $saveOk = 0;
	
	
	my $reference = trim( $kvArgs{reference} );
	my $referenceIsMandatory = ( Config->{phishreferencemandatory} =~ /^on$/i ) ? 1: 0;
	my $referencePatternString = Config->{phishreferencepattern};
	my $referencePattern = qr/$referencePatternString/;
	
	if ( $referenceIsMandatory && ( !$reference || $reference !~ /^$referencePattern$/ ) ) {
		$message = 'You have to set a valid reference';
		
	} elsif ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my $stmnt = "SELECT * FROM phish WHERE id = ?";
		Database->prepare( $stmnt );
		Database->executeWithBinds( $kvArgs{id} );
		my $phisingSite = Database->fetchRow();

		Database->setObject( 'phish', { id => $kvArgs{id} }, { reference => $kvArgs{reference}, campaign => $kvArgs{campaign} } );
		$saveOk = 1;
		setUserAction( action => 'edit phishing site', comment => "Edited phishing site '$phisingSite->{url}'");
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $kvArgs{id},
			reference => $kvArgs{reference},
			campaign => $kvArgs{campaign},
			insertNew => 0
		}
	};
}

sub addPhishingItem {
	my ( %kvArgs) = @_;	
	my ( $message, $itemHtml, $vars, %phishingItem );
	
	my $addOk = 0;

	my $reference = trim( $kvArgs{reference} );
	my $referenceIsMandatory = ( Config->{phishreferencemandatory} =~ /^on$/i ) ? 1: 0;
	my $referencePatternString = Config->{phishreferencepattern};
	my $referencePattern = qr/$referencePatternString/;
	
	if ( $referenceIsMandatory && ( !$reference || $reference !~ /^$referencePattern$/ ) ) {
		$message = 'You have to set a valid reference';
		
	} elsif ( !Database->checkIfExists( { url => $kvArgs{url} }, "phish" ) ) {
		my %insert = ( 
			url => $kvArgs{url},
			datetime_added => nowstring( 2 ),
			counter_down => 0,
			counter_hash_change => 0,
			reference => $reference,
			campaign => $kvArgs{campaign}
		);
		
		my ( $stmnt, @bind ) = Sql->insert( "phish", \%insert );
				
		Database->prepare( $stmnt );
		Database->executeWithBinds( @bind );
		$phishingItem{id} = Database->getLastInsertedId('phish');

		my $dt = nowstring( 2 );
		$phishingItem{url} = $kvArgs{url};
		$phishingItem{reference} = $reference;
		$phishingItem{campaign} = $kvArgs{campaign};
		$phishingItem{dt_added} = substr( $dt, 6, 2 ) . "-" . substr( $dt, 4, 2 ) .
			"-" . substr( $dt, 0, 4 ) . " " . substr( $dt, 8, 2 ) .
			":" . substr( $dt, 10, 2 ) . ":" . substr( $dt, 12, 2 );
		$phishingItem{dt_laststatus} = $phishingItem{dt_added};
		$phishingItem{status} = 'uninitialized';

		my $tt = Taranis::Template->new;
		$vars->{renderItemContainer} = 1;
		$vars->{phishingItem} = \%phishingItem;
		$itemHtml = $tt->processTemplate( 'phishing_item.tt', $vars, 1 );		

		$addOk = 1;
	} else {
		$message = "URL already exists!";
	}

	if ( $addOk ) {
		setUserAction( action => 'add phishing site', comment => "Added phishing site '$kvArgs{url}'");
	} else {
		setUserAction( action => 'add phishing site', comment => "Got error '$message' while trying to add phishing site '$kvArgs{url}'");
	}

	return {
		params => {
			message => $message,
			addOk => $addOk,
			itemHtml => $itemHtml
		}
	};
}

sub deletePhishingItem {
	my ( %kvArgs) = @_;	
	my ( $message );

	my $deleteOk = 0;

	my $stmnt = "SELECT * FROM phish WHERE id = ?";
	Database->prepare( $stmnt );
	Database->executeWithBinds( $kvArgs{id} );
	my $phisingSite = Database->fetchRow();

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my ( $stmntDeleteImages, @bindDeleteImages ) = Sql->delete( "phish_image", { phish_id => $kvArgs{id} } );

		Database->prepare( $stmntDeleteImages );
		Database->executeWithBinds( @bindDeleteImages );
		
		my ( $stmntDeletePhishDetails, @bindDeletePhishDetails ) = Sql->delete( "phish", { id => $kvArgs{id} } );

		Database->prepare( $stmntDeletePhishDetails );
		Database->executeWithBinds( @bindDeletePhishDetails );
		
		$deleteOk = 1;
		setUserAction( action => 'delete phishing site', comment => "Deleted phishing site '$phisingSite->{url}'");
	} else {
		$message = "No permission!";
		setUserAction( action => 'delete phishing site', comment => "Got error '$message' while trying to delete phishing site '$phisingSite->{url}'");
	}

	return {
		params => {
			message => $message,
			deleteOk => $deleteOk,
			id => $kvArgs{id}
		}
	};	
}
 sub openDialogPhishingScreenshot {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;

	if ( $kvArgs{phishid} =~ /^\d+$/ && $kvArgs{objectid} =~ /^\d+$/ ) {

		my $stmnt = "SELECT *, to_char(timestamp, 'DD-MM-YYYY HH24:MI') AS timestamp_string FROM phish_image WHERE object_id = ? AND phish_id = ?;";
		Database->prepare( $stmnt );
		Database->executeWithBinds( $kvArgs{objectid}, $kvArgs{phishid} );

		my $phishingDetails = Database->fetchRow();
		$vars->{screenshot_details} = to_json( { tool => 'phishing_checker', object_id => $phishingDetails->{object_id}, file_size => $phishingDetails->{file_size} } );
		$vars->{timestamp_string} = $phishingDetails->{timestamp_string};
		 
		$tpl = 'phishing_screenshot.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = "Does not compute...";
	} 

	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return { 
		dialog => $dialogContent 
	};
}

sub loadImage {
	my ( %kvArgs ) = @_;
	my $dbh = Database;

	my $objectId = $kvArgs{object_id};
	my $fileSize = $kvArgs{file_size};
	my $image;
	my $mode = $dbh->{dbh}->{pg_INV_READ};
	
	withTransaction {
		my $lobj_fd = $dbh->{dbh}->func($objectId, $mode, 'lo_open');

		$dbh->{dbh}->func( $lobj_fd, $image, $fileSize, 'lo_read' );
	};

	print CGI->header(
		-type => 'image/png',
		-content_length => $fileSize,
	);
	binmode STDOUT;
	print $image;
}

1;
