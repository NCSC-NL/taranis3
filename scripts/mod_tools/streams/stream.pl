#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use JSON;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Template;

my @EXPORT_OK = qw(
	displayStreams openDialogNewStream openDialogStreamDetails
	addStream saveStream deleteStream
);

sub stream_export {
	return @EXPORT_OK;
}

sub displayStreams {
	my ( %kvArgs) = @_;	
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $stmnt = "SELECT * FROM stream ORDER BY description;";
	
	Database->prepare( $stmnt );
	Database->executeWithBinds();
	my @streams;
	while ( Database->nextRecord() ) {
		my $record = Database->getRecord();
		$record->{display_count} = ( $record->{displays_json} ) ? scalar( @{ from_json( $record->{displays_json} ) } ) : 0;
		push @streams, $record;
	}
	
	$vars->{write_right} = right("write");
	$vars->{streams} = \@streams;
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('stream.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('stream_filters.tt', $vars, 1);
	
	my @js = ('js/stream.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewStream {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $dialogContent = $oTaranisTemplate->processTemplate('stream_details.tt', $vars, 1);
	return { dialog => $dialogContent };
}

sub openDialogStreamDetails {
	my ( %kvArgs) = @_;	
	my ( $vars, $tpl, $id );
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $stmnt = "SELECT * FROM stream WHERE id = ?;";
		
		Database->prepare( $stmnt );
		Database->executeWithBinds( $id );
		
		$vars->{stream} = Database->fetchRow();
		$vars->{displays} = from_json( $vars->{stream}->{displays_json} );

		$tpl = 'stream_details.tt';
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

sub addStream {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message );
	
	my $addOk = 0;
	
	my $writeRight = right("write");
	
	if (
		$writeRight
		&& $kvArgs{description}
		&& $kvArgs{transition_time} =~ /^\d+$/
 	) {

		my @submittedDisplays = ( $kvArgs{displays} ) ? split( "\n", $kvArgs{displays} ) : ();
		my @displays;
		
		foreach my $display ( @submittedDisplays ) {
			$display = trim( $display );
			next if ( !$display );
			push @displays, $display;
		}
		
		my %insert = (
			description => $kvArgs{description},
			displays_json => to_json( \@displays ),
			transition_time => $kvArgs{transition_time}
		);
		
		if ( my $streamID = Database->addObject('stream', \%insert, 1) ) {
			$vars->{renderItemContainer} = 1;
			$vars->{write_right} = $writeRight;
			$vars->{stream} = {
				description => $kvArgs{description},
				display_count => scalar( @displays ),
				id => $streamID
			};
			
			my $oTaranisTemplate = Taranis::Template->new;
			$itemHtml = $oTaranisTemplate->processTemplate( 'stream_item.tt', $vars, 1 );
			$addOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "Invalid input for new stream.";
	}
	
	if ( $addOk ) {
		setUserAction( action => 'add stream', comment => "Added stream $kvArgs{description}");
	} else {
		setUserAction( action => 'add stream', comment => "Got error $message while trying to add stream $kvArgs{description}");
	}

	return {
		params => {
			message => $message,
			addOk => $addOk,
			itemHtml => $itemHtml
		}
	};
}

sub saveStream {
	my ( %kvArgs) = @_;
	my ( $itemHtml, $vars, $message, $id );
	
	my $saveOk = 0;
	
	if (
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{transition_time} =~ /^\d+$/
		&& $kvArgs{description}
	) {
		$id = $kvArgs{id};
		
		my @submittedDisplays = ( $kvArgs{displays} ) ? split( "\n", $kvArgs{displays} ) : [];
		my @displays;
		
		foreach my $display ( @submittedDisplays ) {
			$display = trim( $display );
			next if ( !$display );
			push @displays, $display;
		}
		
		my %update = (
			description => $kvArgs{description},
			displays_json => to_json( \@displays ),
			transition_time => $kvArgs{transition_time}
		);
		
		if ( Database->setObject('stream', { id => $id }, \%update ) ) {
			$vars->{stream} = {
				description => $kvArgs{description},
				display_count => scalar( @displays ),
				id => $id
			};
			$vars->{write_right} = 1;
			
			my $oTaranisTemplate = Taranis::Template->new;
			$itemHtml = $oTaranisTemplate->processTemplate( 'stream_item.tt', $vars, 1 );
			$saveOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}
	
	if ( $saveOk ) {
		setUserAction( action => 'edit stream', comment => "Edited stream $kvArgs{description}");
	} else {
		setUserAction( action => 'edit stream', comment => "Got error $message while trying to edit stream $kvArgs{description}");
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

sub deleteStream {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		if ( Database->deleteObject( 'stream', { id => $id } ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete stream', comment => "Deleted stream $kvArgs{description}");
	} else {
		setUserAction( action => 'delete stream', comment => "Got error $message while trying to delete stream $kvArgs{description}");
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
