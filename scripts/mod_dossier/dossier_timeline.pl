#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config);
use Taranis::Assess;
use Taranis::Constituent_Group;
use Taranis::Constituent_Individual;
use Taranis::Dossier;
use Taranis::Dossier::Item;
use Taranis::Dossier::Note;
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use Taranis::Mail ();

use CGI::Simple;
use Encode;
use JSON;
use HTML::Entities;
use URI::Escape;
use strict;

use Data::Dumper;

my @EXPORT_OK = qw(	
	displayDossierTimeline openDialogDossierItemDetails saveDossierItemDetails openDialogNewItemNote 
	saveNewItemNote loadNoteFile getItemNoteHtml openDialogNotesOtherDossier openDialogDossierMailItem
	mailDossierItem
);

my @js = (
	'js/jquery.timepicker.min.js',
	'js/assess.js',
	'js/assess_details.js',
	'js/assess_filters.js',
	'js/assess2analyze.js',
	'js/analyze.js',
	'js/analyze_filters.js',
	'js/analyze_details.js',
	'js/analysis2publication.js',
	'js/dossier.js',
	'js/dossier_timeline.js',
	'js/dossier_filters.js',
);

sub dossier_timeline_export {
	return @EXPORT_OK;
}

sub displayDossierTimeline {
	my ( %kvArgs) = @_;
	my ( $vars, $dossier );

	my $oTaranisTemplate = Taranis::Template->new;

	if ( $kvArgs{id} =~ /^\d+$/ ) {

		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		
		my $contentTypes = $oTaranisDossierItem->getContentTypes();
		
		my $dossierID = $kvArgs{id};
		
		$dossier = $oTaranisDossier->getDossiers( id => $dossierID )->[0];
		my $dossierItems = $oTaranisDossierItem->getDossierItemsFromDossier( $dossierID );

	DOSSIER_ITEM:
		foreach my $dossierItemKey ( keys %$dossierItems ) {
			my $notes = $oTaranisDossierNote->getItemNotes( dossier_item_id => $dossierItems->{$dossierItemKey}->{dossier_item_id} );
			foreach my $note ( @$notes ) {
				$note->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $note->{id} );
				$note->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $note->{id} );
				$note->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $note->{id} );
			}
			
			$dossierItems->{$dossierItemKey}->{notes} = $notes;

			# get the number of notes per dossier for the current item
			my $contentType = $dossierItems->{$dossierItemKey}->{dossier_item_type};
			if($contentType eq 'note') {
				delete $dossierItems->{$dossierItemKey}
					if $dossierItems->{$dossierItemKey}->{text} =~ /\] was discarded /;
				next DOSSIER_ITEM;
			}

			$contentTypes->{$contentType}->{joinColumn} =~ s/^([a-z]+).*$/$1/g;
			$dossierItems->{$dossierItemKey}->{notesCount} = $oTaranisDossierNote->getItemNotesCountPerDossier(
				'di.' . $contentTypes->{$contentType}->{dossier_item_column} =>  $dossierItems->{$dossierItemKey}->{ $contentTypes->{$contentType}->{joinColumn} },
				'di.dossier_id' => { '!=' => $dossierID }
			);
		}
		
		$vars->{dossierStatus} = $dossier->{status};
		$vars->{dossierItems} = $dossierItems;
		$vars->{ticketURL} = Config->{rt_ticket_url};
		$vars->{dossierID} = $dossierID;
	} else {
		$vars->{error} = 'No permission';
	}

	$vars->{page_title} = ( exists( $kvArgs{page_title} ) ) ? $kvArgs{page_title} : $dossier->{description};
	$vars->{write_right} = right("write");
	
	my $htmlContent = $oTaranisTemplate->processTemplate('dossier_timeline.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('dossier_timeline_filters.tt', $vars, 1);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogDossierItemDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight && $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		
		$vars->{dossierItem} = $oTaranisDossierItem->getDossierItems( id => $kvArgs{id} )->[0];
		$vars->{tlpMapping} = $oTaranisDossierItem->getTLPMapping();
		
		$tpl = 'dossier_item_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub saveDossierItemDetails {
	my ( %kvArgs) = @_;
	my ( $message, $noteID );
	my $saveOk = 0;
	my $dossierItemIsChanged = 0;
	my $noteText = '';
	
	if (
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{event_timtestamp_date} =~ /^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[012])-(19|20)\d\d$/
		&& $kvArgs{event_timtestamp_time} =~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/
		&& $kvArgs{tlp} =~ /^[1-4]$/
	) {
		
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		
		my $dossierItem = $oTaranisDossierItem->getDossierItems( id => $kvArgs{id} )->[0];
		if ( $dossierItem->{classification} != $kvArgs{tlp} ) {
			my $tlpMapping = $oTaranisDossierItem->getTLPMapping();
			$noteText = "Changed TLP classification from " . uc( $tlpMapping->{$dossierItem->{classification}} ) . " to " . uc( $tlpMapping->{$kvArgs{tlp}} ) . ".";
		}
		
		my $numbersOnlyNewTimestamp = $kvArgs{event_timtestamp_date} . $kvArgs{event_timtestamp_time};
		$numbersOnlyNewTimestamp =~ s/[-:\s]//g;
		my $numbersOnlyCurrentTimestamp = $dossierItem->{event_timestamp_str};
		$numbersOnlyCurrentTimestamp =~ s/[-:\s]//g;

		if ( $numbersOnlyNewTimestamp != $numbersOnlyCurrentTimestamp ) {
			$noteText .= "\n" if ( $noteText );
			$noteText .= "Moved event from $dossierItem->{event_timestamp_str} to $kvArgs{event_timtestamp_date} $kvArgs{event_timtestamp_time}.";
		}
		
		if ( $noteText ) {
			$oTaranisDossierItem->{dbh}->startTransaction();
			if ( $oTaranisDossierItem->setDossierItem(
				id => $kvArgs{id},
				classification => $kvArgs{tlp},
				event_timestamp => formatDateTimeString( $kvArgs{event_timtestamp_date} ) . ' ' . $kvArgs{event_timtestamp_time}
			) ) {
				
				if ( !$oTaranisDossierNote->addNote(
					dossier_item_id => $kvArgs{id},
					text => $noteText,
					created_by => sessionGet('userid')
				) ) {
					$message = $oTaranisDossierNote->{errmsg};
				}

			} else {
				$message = $oTaranisDossierItem->{errmsg};
			}
		
			if ( $message ) {
				$oTaranisDossierNote->{dbh}->rollbackTransaction();
			} else {
				$oTaranisDossierNote->{dbh}->commitTransaction();
			}
		}
		
	} else {
		$message = 'No permission';
	}
	
	if ( $message ) {
		 setUserAction( action => 'edit dossier item details', comment => "Got error '$message' while trying to edit dossier item details.");
	} else {
		$saveOk = 1;
		setUserAction( action => 'edit dossier item details', comment => $noteText);
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			itemId => $kvArgs{id},
			isChanged => ( $noteText ) ? 1 : 0
		}
	};
}

sub openDialogNewItemNote {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		my $userID = sessionGet('userid');
		
		my $constituentGroupRight = getUserRights( 
			entitlement => "constituent_groups",
			username => $userID 
		)->{constituent_groups}->{read_right};

		my $constituentIndividualRight = getUserRights( 
			entitlement => "constituent_individuals",
			username => $userID 
		)->{constituent_individuals}->{read_right};
		
		my ( @groups, @individuals );
		
		if ( $constituentGroupRight ) {
			$oTaranisConstituentGroup->loadCollection();
			
			while ( $oTaranisConstituentGroup->nextObject() ) {
				push( @groups, $oTaranisConstituentGroup->getObject() );
			}
			foreach my $group ( @groups ) {
				$group->{memberIds} = to_json( [ $oTaranisConstituentGroup->getMemberIds( $group->{id} ) ] ) ;
			}
			$vars->{constituentGroups} = \@groups;
		}
		if ( $constituentIndividualRight ) {
			$oTaranisConstituentIndividual->loadCollection();
			while ( $oTaranisConstituentIndividual->nextObject() ) {
				push( @individuals, $oTaranisConstituentIndividual->getObject() );
			}
			$vars->{constituentIndividuals} = \@individuals;
		}

		$tpl = 'dossier_new_item_note.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub saveNewItemNote {
	my ( %kvArgs) = @_;
	my ( $message, $noteID );
	my $saveOk = 0;

	if ( $kvArgs{dossier_item_id} =~ /^\d+$/ ) {
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		
		my $noteText = trim( $kvArgs{'note-text'} );
		my $urls = $kvArgs{'note-url'};
		my $urlDescriptions = $kvArgs{'note-url-description'};
		my $tickets = $kvArgs{'note-ticket'};
		my @uploadedFiles;
		
		$noteText = $oTaranisDossierNote->processNoteText( $noteText );
		
		# collect uploaded files
		foreach my $file ( CGI->upload ) {
			next if ( !$file );
			my ( $memFile, $fh, %fileInfo );
			my $fhUploadedFile = CGI->upload( $file );

			open($fh, ">", \$memFile);
			binmode $fh;
			while(<$fhUploadedFile>) {
				print $fh $_ or return 0;
			}
			close $fh;
			
			$fileInfo{name} = decode_utf8 $file;  # CGI->upload doesn't decode the filename for us.
			$fileInfo{binary} = $memFile;
			$fileInfo{mime} = CGI->upload_info( $file, 'mime' ); # MIME type of uploaded file

			push @uploadedFiles, \%fileInfo;
		}

		$oTaranisDossierNote->{dbh}->startTransaction();
		
		if ( $noteID = $oTaranisDossierNote->addNote( 
			dossier_item_id => $kvArgs{dossier_item_id},
			text => $noteText,
			created_by => sessionGet('userid')
		) ) {
			
			# store uploaded files in database as large objects
			if ( @uploadedFiles ) {
				foreach my $uploadedFile ( @uploadedFiles ) {
					$uploadedFile->{note_id} = $noteID;
					if ( !$oTaranisDossierNote->addNoteFile( %$uploadedFile ) ) {
						$message = $oTaranisDossierNote->{errmsg};
					}
				}
			}
			
			# store urls
			if ( $urls && ref( $urls ) =~ /^ARRAY$/ ) {
				for ( my $i = 0; $i < @$urls; $i++ ) {
					my $url = trim( $urls->[$i] );
					if ( $url) {
						if ( $url !~ /^http/ ) {
							$url = 'http://' . $url;
						}
						if ( !$oTaranisDossierNote->addNoteUrl(
							note_id => $noteID,
							url => $url,
							description => trim( $urlDescriptions->[$i] )
						) ) {
							$message = $oTaranisDossierNote->{errmsg};
						}
					}
				}
			}
			
			# store tickets
			if ( $tickets && ref( $tickets ) =~ /^ARRAY$/ ) {
				foreach my $ticket ( @$tickets ) {
					$ticket = trim( $ticket );
					if ( $ticket && $ticket =~ /^\d+$/ ) {
						if ( !$oTaranisDossierNote->addNoteTicket(
							note_id => $noteID,
							reference => $ticket,
						) ) {
							$message = $oTaranisDossierNote->{errmsg};
						}
					} elsif ( $ticket ) {
						$message = 'RT tickets can only be numbers.';
					}
				}
			}

		} else {
			$message = $oTaranisDossierNote->{errmsg};
		}
		
		if ( $message ) {
			$oTaranisDossierNote->{dbh}->rollbackTransaction();
		} else {
			$oTaranisDossierNote->{dbh}->commitTransaction();
		}
	} else {
		$message = 'No permission';
	}
	
	if ( $message ) {
		 setUserAction( action => 'add comment', comment => "Got error '$message' while trying to add comment to dossier item with ID $kvArgs{dossier_item_id}.");
	} else {
		$saveOk = 1;
		setUserAction( action => 'add comment', comment => 'Added comment to dossier item with ID $kvArgs{dossier_item_id}.');
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			noteID => $noteID
		}
	};	
}

sub loadNoteFile {
	my ( %kvArgs ) = @_;
	
	my $noteFileID = $kvArgs{fileID};
	
	if ( $noteFileID =~ /^\d+$/ ) {
		
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $noteFile = $oTaranisDossierNote->getNoteFiles( id => $noteFileID )->[0];
		
		my $file;
		my $mode = $oTaranisDossierNote->{dbh}->{dbh}->{pg_INV_READ};
		
		withTransaction {
			my $lobj_fd = $oTaranisDossierNote->{dbh}->{dbh}->func( $noteFile->{object_id}, $mode, 'lo_open');

			$oTaranisDossierNote->{dbh}->{dbh}->func( $lobj_fd, $file, $noteFile->{size}, 'lo_read' );
		};

		print CGI->header(
			-type => $noteFile->{mime},
			-content_disposition => qq{attachment; filename="$noteFile->{name}"},
			-content_length => $noteFile->{size},
		);
		binmode STDOUT;
		print $file;
	}
}

sub getItemNoteHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
	
	my $id = $kvArgs{id};
 
 	my $itemNote = $oTaranisDossierNote->getItemNotes( id => $id );
 
	if ( $itemNote ) {
		$vars->{note} = $itemNote->[0];

		$vars->{note}->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $id );
		$vars->{note}->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $id );
		$vars->{note}->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $id );
		$vars->{ticketURL} = Config->{rt_ticket_url};
		$vars->{write_right} = right("write");
		
		$tpl = 'dossier_item_note.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		params => { 
			itemHtml => $itemHtml,
			id => $id
		}
	};	
}

sub openDialogNotesOtherDossier {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	
	my $contentTypes = $oTaranisDossierItem->getContentTypes();
	
	if ( $kvArgs{dossierid} =~ /^\d+$/ && $kvArgs{productid} && $kvArgs{itemtype} && exists( $contentTypes->{ $kvArgs{itemtype} } ) ) {
		
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		
		my $notes = $oTaranisDossierNote->getItemNotes( dossier_id => $kvArgs{dossierid}, $contentTypes->{ $kvArgs{itemtype} }->{dossier_item_column} => $kvArgs{productid} );
		foreach my $note ( @$notes ) {
			$note->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $note->{id} );
			$note->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $note->{id} );
			$note->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $note->{id} );
		}
		
		$vars->{notes} = $notes; 
		$vars->{dossier} = $oTaranisDossier->getDossiers( id => $kvArgs{dossierid} )->[0];
		
		$vars->{ticketURL} = Config->{rt_ticket_url};
		
		$tpl = 'dossier_item_notes.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return { dialog => $dialogContent };
}

sub openDialogDossierMailItem {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
	my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $contentTypes = $oTaranisDossierItem->getContentTypes();
	
	if ( $kvArgs{itemid} =~ /^\d+$/ && $kvArgs{itemtype} && exists( $contentTypes->{ $kvArgs{itemtype} } ) ) {

		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		$vars->{mailfrom_sender} = $user->{mailfrom_sender};
		$vars->{mailfrom_email} = $user->{mailfrom_email};
		
		my @maillistAddresses = split( ";", Config->{maillist} ); 
			for ( my $i = 0; $i < @maillistAddresses; $i++ ) {
			$maillistAddresses[$i] = trim( $maillistAddresses[$i] );
		}
		
		$vars->{nonConstituents} = \@maillistAddresses;
		
		my $userID = sessionGet('userid');
		
		my $constituentIndividualRight = getUserRights( 
			entitlement => "constituent_individuals",
			username => $userID 
		)->{constituent_individuals}->{read_right};
		
		my ( @constituentIndividuals );
		
		if ( $constituentIndividualRight ) {
			$oTaranisConstituentIndividual->loadCollection();
			while ( $oTaranisConstituentIndividual->nextObject() ) {
				push( @constituentIndividuals, $oTaranisConstituentIndividual->getObject() );
			}
			
			foreach my $constituentIndividual ( @constituentIndividuals ) {
			
				$oTaranisConstituentIndividual->getGroups( $constituentIndividual->{id} );
				while ( $oTaranisConstituentIndividual->nextObject ) {
					my $group = $oTaranisConstituentIndividual->getObject();
					push @{ $constituentIndividual->{groups} }, $group->{name} if ( $group->{status} == "0" );
				}
			}
			
			$vars->{constituentIndividuals} = \@constituentIndividuals;
		}
		
		my $dossierItem = $oTaranisDossierItem->getDossierItems( id => $kvArgs{itemid} )->[0];

		if ( $dossierItem->{note_id} ) {
			$vars->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $dossierItem->{note_id} );
			$vars->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $dossierItem->{note_id} );
			$vars->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $dossierItem->{note_id} );
			
			$vars->{ticketURL} = Config->{rt_ticket_url};
		}
		
		$vars->{dossierItemContent} = $oTaranisDossierItem->getDossierItemContent( contentType => $kvArgs{itemtype}, dossierItem => $dossierItem );
		$vars->{dossierItem} = $dossierItem;
		$vars->{dossierItemType} = $kvArgs{itemtype};
		
		my $notesHaveAttachments = 0; 
		my $notes = $oTaranisDossierNote->getItemNotes( dossier_item_id => $dossierItem->{id} );
		foreach my $note ( @$notes ) {
			$note->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $note->{id} );
			$note->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $note->{id} );
			$notesHaveAttachments = 1 if  ( $note->{tickets} );
			$note->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $note->{id} );
		}
		$vars->{notesHaveAttachments} = $notesHaveAttachments;
		$vars->{notes} = $notes;
		
		$tpl = 'dossier_mail_item.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return { dialog => $dialogContent };
}

sub mailDossierItem {
	my ( %kvArgs) = @_;
	my ( $message );


	if ( right("execute") ) {
		
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		
		my $user = $oTaranisUsers->getUser( sessionGet('userid') );

		my $jsonAddresses = $kvArgs{addresses};
		$jsonAddresses =~ s/&quot;/"/g;
		my $addresses = from_json( $jsonAddresses );
		
		my $subject = encode( "MIME-Header", HTML::Entities::decode( $kvArgs{subject} ) );
		$subject =~ s/\s+/ /g;
		
		my @attachments;
		foreach my $key ( 'dossier_attachment', 'dossier_attachment_note' ) {
			
			if ( exists( $kvArgs{$key} ) ) {
				
				my @attachmentIDs = ( ref( $kvArgs{$key} ) =~ /^ARRAY$/ )
					? @{ $kvArgs{$key} }
					: $kvArgs{$key};
					
				foreach my $attachmentID ( @attachmentIDs ) {
					$attachmentID =~ s/&quot;/"/g;
					my $object = from_json( $attachmentID );
					my $attachment = $oTaranisDossierNote->getNoteFiles( object_id => $object->{a}, note_id => $object->{b} );
					if ( $attachment ) {
						$attachment = $attachment->[0];
						if ( $attachment->{binary} = $oTaranisDossierNote->{dbh}->getBlob( object_id => $attachment->{object_id}, size => $attachment->{size} ) ) {
							push @attachments, $attachment;
						}
					}
				}
			}
		}
			
		if ( $kvArgs{dossier_attachment_assess} ) {
			my $oTaranisAssess = Taranis::Assess->new( Config );
			my $assessItem = $oTaranisAssess->getItem( uri_unescape( $kvArgs{dossier_attachment_assess} ), 0 );
			if ( !$assessItem ) {
				$assessItem = $oTaranisAssess->getItem( uri_unescape( $kvArgs{dossier_attachment_assess} ), 1 );
			}

			if ( $assessItem ) {
				my $attachment = { name => $assessItem->{'link'} . '.png', mime => 'image/png' };
				if ( $attachment->{binary} = $oTaranisDossierNote->{dbh}->getBlob( object_id => $assessItem->{screenshot_object_id}, size => $assessItem->{screenshot_file_size} ) ) {
					
					push @attachments, $attachment;
				}
			}
		}

		my $from = HTML::Entities::decode( $user->{mailfrom_sender} )
			. " <$user->{mailfrom_email}>";

		my $text = decode_entities( $kvArgs{description} );
		$text .= "\n\n" . decode_entities( $kvArgs{comments} )
			if $kvArgs{dossier_comments};

		my @attachments = map Taranis::Mail->attachment(
			description => $_->{name},
			mime_type   => $_->{mime},
			filename    => $_->{name},
			data        => $_->{binary},
		), @attachments;

		foreach my $address ( @$addresses ) {
			my $msg = Taranis::Mail->build(
				From       => $from,
				To		   => $address,
				Subject    => $subject,
				plain_text => $text,
			);

			$message .= "E-mail to $address sent!<br>";
		}

	} else {
		$message = '<div id="dialog-error">Sorry, you do not have enough privileges to send this email...</div>';
	}

	my $dialogContent = '<div class="dialog-form-wrapper block">' . $message . '</div>';
	return { dialog => $dialogContent };
}
