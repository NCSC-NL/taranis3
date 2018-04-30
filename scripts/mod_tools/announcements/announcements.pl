#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Template;
use JSON;
 
my @EXPORT_OK = qw(
	deleteAnnouncement openDialogAnnouncementDetails openDialogNewAnnouncement
	saveAnnouncementDetails saveNewAnnouncement displayAnnouncements
);

sub announcements_export {
	return @EXPORT_OK;
}

sub displayAnnouncements {
	my ( %kvArgs) = @_;	
	
	my $vars;
	my $oTaranisTemplate = Taranis::Template->new;
	my $selectStmnt = "SELECT *, to_char(created, 'DD-MM-YYYY HH24:MI') AS created_str FROM announcement ORDER BY created DESC;";

	Database->prepare( $selectStmnt );
	Database->executeWithBinds();
	
	my @announcements;
	while ( Database->nextRecord() ) {
		my $record = Database->getRecord();
		push @announcements, $record;
	} 	

	$vars->{announcements} = \@announcements;

	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate( 'announcements.tt', $vars, 1 );
	my $htmlFilters = $oTaranisTemplate->processTemplate( 'announcements_filters.tt', $vars, 1 );
	
	my @js = ( 'js/announcements.js'	);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewAnnouncement {
	my ( %kvArgs) = @_;	
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;

	my $dialogContent = $oTaranisTemplate->processTemplate('announcements_details.tt', $vars, 1);

	return { 
		dialog => $dialogContent,
		params => {	writeRight => right('write') }
	};	
}

sub openDialogAnnouncementDetails {
	my ( %kvArgs) = @_;	
	my ( $vars, $announcement, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$announcement = getAnnouncement( $kvArgs{id} );
		$announcement->{content} = from_json( $announcement->{content_json} ) if ( exists( $announcement->{content_json} ) );
		$vars->{announcement} = $announcement;
		
		$tpl = 'announcements_details.tt';
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}	
	
	return { 
		dialog => $oTaranisTemplate->processTemplate($tpl, $vars, 1),
		params => {
			id => $kvArgs{id}, 
			writeRight => right('write')
		}
	};
}

sub saveNewAnnouncement {
	my ( %kvArgs) = @_;	
	
	my ( $message, $announcementHtml, $vars );
	my $saveOk = 0;
	my $writeRight = right("write");

	if (
		$writeRight
		&& $kvArgs{type} =~ /^(freeform-text|bullet-list|todo-list)$/
	) {

		my $announcement = {
			type => $kvArgs{type},
			title => $kvArgs{title},
			content_json => announcementContentToJSON( %kvArgs )
		};
		
		if ( my $announcementID = Database->addObject('announcement', $announcement, 1) ) {
			$vars->{renderItemContainer} = 1;
			$vars->{write_right} = $writeRight;
			
			$vars->{announcement} = getAnnouncement( $announcementID );
			
			my $oTaranisTemplate = Taranis::Template->new;
			$announcementHtml = $oTaranisTemplate->processTemplate( 'announcements_item.tt', $vars, 1 );
			$saveOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
	} else {
		$message = "Invalid input for new announcement.";
	}

	if ( $saveOk ) {
		setUserAction( action => 'add announcement', comment => "Added announcement '$kvArgs{title}'");
	} else {
		setUserAction( action => 'add announcement', comment => "Got error while trying to add announcement '$kvArgs{title}'");
	}

	return { 
		params => {
			saveOk => $saveOk,
			message => $message,
			itemHtml => $announcementHtml,
			insertNew => 1
		}
	};	
}

sub saveAnnouncementDetails {
	my ( %kvArgs) = @_;	
	my ( $message, $vars, $announcementHtml );
	
	my $saveOk = 0;
	
	if (
		right('write')
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{type} =~ /^(freeform-text|bullet-list|todo-list)$/
		&& $kvArgs{is_enabled} =~ /^(0|1)$/
	) {
		
		my $oTaranisTemplate = Taranis::Template->new;

		my $announcement = {
			type => $kvArgs{type},
			title => $kvArgs{title},
			is_enabled => $kvArgs{is_enabled},
			content_json => announcementContentToJSON( %kvArgs )
		};

		if ( Database->setObject('announcement', { id => $kvArgs{id} }, $announcement ) ) {
			$vars->{announcement} = getAnnouncement( $kvArgs{id} );
			
			$vars->{write_right} = 1;
			
			my $oTaranisTemplate = Taranis::Template->new;
			$announcementHtml = $oTaranisTemplate->processTemplate( 'announcements_item.tt', $vars, 1 );
			$saveOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
	
	} else {
		$message = 'No permission';
	}

	if ( $saveOk ) {
		setUserAction( action => 'edit announcement', comment => "Edited announcement '$kvArgs{title}'");
	} else {
		setUserAction( action => 'edit announcement', comment => "Got error while trying to edit announcement '$kvArgs{title}'");
	}
	
	return { 
		params => {
			saveOk => $saveOk,
			message => $message,
			itemHtml => $announcementHtml,
			id => $kvArgs{id}			
		}
	};
}

sub deleteAnnouncement {
	my ( %kvArgs) = @_;	
	my $message;
	my $deleteOk = 0;
	
	if (
		right("write")
		&& $kvArgs{id} =~ /^\d+$/ 
	) {
		
		if ( Database->deleteObject( 'announcement', { id => $kvArgs{id} } ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}

	} else {
		$message = 'No permission';
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete announcement', comment => "Deleted announcement '$kvArgs{title}'");
	} else {
		setUserAction( action => 'delete announcement', comment => "Got error while trying to delete announcement '$kvArgs{title}'");
	}
	
	return {
		params =>{
			message => $message,
			deleteOk => $deleteOk,
			id => $kvArgs{id}
		}
	};
}

# HELPERS
sub announcementContentToJSON {
	my ( %kvArgs) = @_;
	
	my $contentJSON = '{}';
	
	for ( $kvArgs{type} ) {
		if (/^freeform-text$/) {
			$contentJSON = to_json( { description => $kvArgs{description} } );
		} elsif (/^bullet-list$/) {
			if ( $kvArgs{'announcement-bullet-list-item'} ) {
				my @list;
				foreach my $listItem ( @{ $kvArgs{'announcement-bullet-list-item'} } ) {
					next if !$listItem;
					push @list, $listItem;
				}
				
				$contentJSON = to_json( { bullets => \@list } );
			}
		} elsif (/^todo-list$/) {
			if ( $kvArgs{todolist} ) {
				my $todoListJSON = $kvArgs{todolist}; 
				$todoListJSON =~ s/&quot;/"/g;
				$contentJSON = '{"todos":' . $todoListJSON . '}';
			}
		}
	}	
	
	return $contentJSON;
}

sub getAnnouncement {
	my ($id) = @_;
	
	my $stmnt = "SELECT *, to_char(created, 'DD-MM-YYYY HH24:MI') AS created_str FROM announcement WHERE id = ?;";
	
	Database->prepare( $stmnt );
	Database->executeWithBinds( $id );
	
	return Database->fetchRow();	
}
1;
