#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Constituent::Group;
use Taranis::Constituent::Individual;
use Taranis::Dossier::Item;
use Taranis::Dossier::Note;
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use JSON;
use Encode qw(decode_utf8);
use strict;

use Data::Dumper;

my @EXPORT_OK = qw(	openDialogNewNote saveNewNote openDialogNoteDetails );

sub dossier_note_export {
	return @EXPORT_OK;
}

sub openDialogNewNote {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $writeRight = right("write");

	if ($writeRight) {
		$vars->{tlpMapping} = $oTaranisDossierItem->getTLPMapping();

		my $userID = sessionGet('userid');

		my $constituentGroupRight = getUserRights(
			entitlement => "constituent_groups",
			username => $userID,
		)->{constituent_groups}->{read_right};

		if($constituentGroupRight) {
			my $cg = Taranis::Constituent::Group->new(Config);
			my @groups = $cg->searchGroups;
			foreach my $group (@groups) {
				my @memberIds = $cg->getMemberIds($group->{id});
				$group->{memberIds} = to_json \@memberIds;
			}
			$vars->{constituentGroups} = \@groups;
		}

		my $constituentIndividualRight = getUserRights(
			entitlement => "constituent_individuals",
			username => $userID,
		)->{constituent_individuals}->{read_right};

		if($constituentIndividualRight) {
			my $ci = Taranis::Constituent::Individual->new(Config);
			$vars->{constituentIndividuals} = [ $ci->loadIndividuals ];
		}

		$tpl = 'dossier_new_note.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight },
	};
}

sub saveNewNote {
	my ( %kvArgs) = @_;
	my ( $message, $noteID );
	my $saveOk = 0;

	my $event_timestamp_date = formatDateTimeString $kvArgs{event_timtestamp_date};
	if (
		$kvArgs{dossier_id} =~ /^\d+$/
		&& $event_timestamp_date
		&& $kvArgs{event_timtestamp_time} =~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/
		&& $kvArgs{tlp} =~ /^[1-4]$/
	) {
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );

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
			text => $noteText,
			created_by => sessionGet('userid')
		) ) {

			if ( !$oTaranisDossierItem->addDossierItem(
				note_id => $noteID,
				event_timestamp => "$event_timestamp_date} $kvArgs{event_timtestamp_time}",
				classification => $kvArgs{tlp},
				dossier_id => $kvArgs{dossier_id}
			) ) {
				$message = $oTaranisDossierItem->{errmsg};
			}

			# store uploaded files in database as large objects
			foreach my $uploadedFile ( @uploadedFiles ) {
				$uploadedFile->{note_id} = $noteID;
				if ( !$oTaranisDossierNote->addNoteFile( %$uploadedFile ) ) {
					$message = $oTaranisDossierNote->{errmsg};
				}
			}

			# store urls
			if($urls && ref $urls eq 'ARRAY') {
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
			foreach my $ticket (map trim($_), flat $tickets) {
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
		 setUserAction( action => 'add note', comment => "Got error '$message' while trying to add to dossier with ID $kvArgs{dossier_id}.");
	} else {
		$saveOk = 1;
		setUserAction( action => 'add note', comment => "Added note to dossier with ID $kvArgs{dossier_id}.");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			noteID => $noteID
		}
	};
}
sub openDialogNoteDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");

	if ( $kvArgs{id} =~ /^\d+$/ ) {

		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );

		my $dossierItem = $oTaranisDossierItem->getDossierItems( id => $kvArgs{id} )->[0];
		$vars->{dossierItem} = $dossierItem;

		$vars->{note} = $oTaranisDossierNote->getItemNotes( id => $dossierItem->{note_id} )->[0];
		$vars->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $dossierItem->{note_id} );
		$vars->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $dossierItem->{note_id} );
		$vars->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $dossierItem->{note_id} );

		$vars->{ticketURL} = Config->{rt_ticket_url};

		$tpl = 'dossier_note_details.tt';
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
