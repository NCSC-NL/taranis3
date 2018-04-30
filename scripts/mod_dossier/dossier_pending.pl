#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Assess;
use Taranis::Analysis;
use Taranis::Dossier;
use Taranis::Dossier::Item;
use Taranis::Dossier::Note;
use Taranis::Screenshot;
use Taranis::Tagging;
use Taranis::Template;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use URI::Escape;
use strict;

use Data::Dumper;

my @EXPORT_OK = qw(	displayMyPendingItems openDialogAddPendingItem
	openDialogAddPendingBulk discardPendingItem addPendingItem );

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
	'js/dossier_pending.js',
);

sub dossier_pending_export {
	return @EXPORT_OK;
}

sub displayMyPendingItems {
	my ( %kvArgs) = @_;
	my ( $vars, %tags, @dossierIDs );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	
	my $oTaranisTagging = Taranis::Tagging->new( Config );

	my $dossiers = $oTaranisDossier->getDossiers( 'dc.username' => sessionGet('userid') );
	push @dossierIDs, $_->{id} for @$dossiers;
	
 	$oTaranisTagging->loadCollection( item_table_name => 'dossier', item_id => \@dossierIDs );
	while ( $oTaranisTagging->{dbh}->nextRecord() ) {
		my $tag = $oTaranisTagging->{dbh}->getRecord();
		$tags{$tag->{id}} = $tag;
	}
	
	my @tagIDs = keys %tags;

	$vars->{pendingItems} = $oTaranisDossierItem->getPendingItems( tagIDs => \@tagIDs );

	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('dossier_pending.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('dossier_pending_filters.tt', $vars, 1);

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogAddPendingItem {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $writeRight = right('write');

	if ( $kvArgs{tagid} =~ /^\d+$/ ) {
		
		my $type = $kvArgs{type};
		my $tagID = $kvArgs{tagid};
		my $id = $kvArgs{id};
		$vars->{item_id} = $id;
		$vars->{item} = $oTaranisDossierItem->getPendingItemsOfContentType( contentType => $type, 'ti.tag_id' => $tagID, 'ti.item_id' => $id )->[0];
		$vars->{dossiers} = $oTaranisDossier->getDossiers( tag_id => $tagID, 'dc.username' => sessionGet('userid') );
		$vars->{tlpMapping} = $oTaranisDossierItem->getTLPMapping();
		
		$tpl = 'dossier_add_pending_item.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {	writeRight => $writeRight }
	};
}

sub openDialogAddPendingBulk {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $writeRight = right('write');

	my %dossiers;
	my %items_per_dossier;
	my $username = sessionGet('userid');
	my @selected = split /\:/, $kvArgs{items};
	if (@selected) {
		my @items;
        foreach my $sel (@selected) {
			my ($type, $tagID, $id) = split /\,/, $sel, 3;
			my $item = $oTaranisDossierItem->getPendingItemsOfContentType( contentType => $type, 'ti.tag_id' => $tagID, 'ti.item_id' => $id )->[0];
			$item or next;

			$item->{type} = $type;
			$item->{typeText} = itemtype2text $type;
			$item->{ref}  = $id;   # might be id or digest
			my $itemdos = $dossiers{$tagID} ||= $oTaranisDossier
				->getDossiers(tag_id => $tagID, 'dc.username' => $username);
			$_->{tagid} = $tagID for @$itemdos;
			push @{$items_per_dossier{$_->{id}}}, $item for @$itemdos;
		}

		my @dossiers = sort {$a->{description} cmp $b->{description}}
			map @$_, values %dossiers;
		$vars->{items_per_dossier} = \%items_per_dossier;
		$vars->{dossiers}   = \@dossiers;
		$vars->{tlpMapping} = $oTaranisDossierItem->getTLPMapping();

		$tpl = 'dossier_add_pending_bulk.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {	writeRight => $writeRight }
	};
}

sub addPendingItem {
	my ( %kvArgs ) = @_;
	my $message;
	my $saveOk = 0;
	
	my $useractionText = '';
	
	if (
		$kvArgs{event_timtestamp_date} =~ /^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[012])-(19|20)\d\d$/
		&& $kvArgs{event_timtestamp_time} =~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/
		&& $kvArgs{tlp} =~ /^[1-4]$/
		&& $kvArgs{tagid} =~ /^\d+$/
		&& $kvArgs{itemid}
		&& $kvArgs{dossier}
		&& $kvArgs{type}
	) {
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisAssess = Taranis::Assess->new( Config );
		my $oTaranisAnalyze = Taranis::Analysis->new( Config );
		
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		my @dossiers = ( ref( $kvArgs{dossier} ) =~ /^ARRAY$/ ) ? @{ $kvArgs{dossier} } : $kvArgs{dossier};
		
		my $tlpMapping = $oTaranisDossierItem->getTLPMapping();
		$oTaranisDossierItem->{dbh}->startTransaction();
		
		ADDPENDINGTODOSSIERS:
		foreach my $dossierID ( @dossiers ) {
			
			# if pending item is an Assess item or an Analysis, create screenshot of Assess item(s)
			if ( $kvArgs{type} =~ /^(assess|analyze)$/ ) {
				
				my @assessItems = ( $kvArgs{type} =~ /^assess$/ )
					? $oTaranisAssess->getItem( $kvArgs{itemid} )
					: @{ $oTaranisAnalyze->getLinkedItems( $kvArgs{itemid} ) };
				
				foreach my $assessItem ( @assessItems ) {
					if ( !$assessItem->{screenshot_object_id} && !$assessItem->{is_mail} && $assessItem->{'link'} ) {
						my $screenshotSettings = takeScreenshotOfAssessItem( $assessItem->{'link'} );
						
						my %assessUpdate = ( digest => $assessItem->{digest} );
						
						if ( my $blobDetails = $oTaranisDossierItem->{dbh}->addFileAsBlob( binary => $screenshotSettings->{binary} ) ) {
							
							$assessUpdate{screenshot_file_size} = $blobDetails->{fileSize};
							$assessUpdate{screenshot_object_id} = $blobDetails->{oid};
							if ( !$oTaranisAssess->setAssessItem( %assessUpdate ) ) {
								$message = $oTaranisAssess->{errmsg};
							}
						}
					}
				}
			}
			
			if ( $message ) {
				$oTaranisDossierItem->{dbh}->{db_error_msg} = $message;
				last ADDPENDINGTODOSSIERS;
			} elsif ( 
				 my $dossierItemID = $oTaranisDossierItem->createDossierItemFromPending(
					contentType => $kvArgs{type},
					dossier_id => $dossierID,
					item_id => $kvArgs{itemid},
					classification => $kvArgs{tlp},
					event_timestamp => formatDateTimeString( $kvArgs{event_timtestamp_date} ) . ' ' . $kvArgs{event_timtestamp_time}
				) 
			) {
				my $userDescription = ( $user->{fullname} ) ? $user->{fullname} : $user->{username};
				my $noteText = "Added by " . $userDescription . " with TLP " . uc( $tlpMapping->{ $kvArgs{tlp} } ) . " and with timeline date " . $kvArgs{event_timtestamp_date} . " " . $kvArgs{event_timtestamp_time};
				$oTaranisDossierNote->addNote( dossier_item_id => $dossierItemID, text => $noteText );
				
				if ( !$oTaranisDossierItem->setDossierItemTag(
					contentType => $kvArgs{type},
					tagID => $kvArgs{tagid},
					itemID => $kvArgs{itemid},
					dossier_id => $dossierID
				) ) {
					$message = $oTaranisDossierItem->{errmsg};
				}
				$useractionText .= "Pending item of type $kvArgs{type} with ID $kvArgs{itemid} has been " .  ucfirst( $noteText ) . ".\n";
				
			} else {
				$message = $oTaranisDossierItem->{errmsg};
			}
		}

		$message
			? $oTaranisDossierItem->{dbh}->rollbackTransaction()
			: $oTaranisDossierItem->{dbh}->commitTransaction();
	} else {
		$message = 'No permission';
	}
	
	if ( $message ) {
		 setUserAction( action => 'add pending item', comment => "Got error '$message' while trying to add pending item to dossier.");
	} else {
		$saveOk = 1;
		setUserAction( action => 'add pending item', comment => $useractionText);
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message
		}
	};
}

sub discardPendingItem {
	my ( %kvArgs ) = @_;
	my $message;
	my $saveOk = 0;
	my $useractionText = '';
	
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $contentTypes = $oTaranisDossierItem->getContentTypes();

	if (
		$kvArgs{itemid}
		&& $kvArgs{type}
		&& exists( $contentTypes->{ $kvArgs{type} } )
		&& $kvArgs{tagid} =~ /^\d+$/
	) {
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisUsers = Taranis::Users->new( Config );

		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		my $userDescription = ( $user->{fullname} ) ? $user->{fullname} : $user->{username};
		my $pendingItem = $oTaranisDossierItem->getPendingItemsOfContentType( contentType => $kvArgs{type}, 'ti.tag_id' => $kvArgs{tagid}, 'ti.item_id' => $kvArgs{itemid} )->[0];
		
		my $noteText = ( $pendingItem->{title} ) ? "$pendingItem->{title} " : "";
		$noteText .= "[" . uc( $kvArgs{type} ) . "] was discarded by $userDescription";
		
		my $dossiers = $oTaranisDossier->getDossiers( tag_id => $kvArgs{tagid}, username => sessionGet('userid') );

		if ( $oTaranisDossierItem->discardPendingItem(
			item_id => $kvArgs{itemid}, 
			item_table_name => $contentTypes->{ $kvArgs{type} }->{table},
			tag_id => $kvArgs{tagid}
		) ) {
			
			foreach my $dossier ( @$dossiers ) {
				
				if ( my $noteID = $oTaranisDossierNote->addNote( text => $noteText ) ) {

					if ( !$oTaranisDossierItem->addDossierItem(
						note_id => $noteID,
						classification => 4,
						dossier_id => $dossier->{id}
					) ) {
						$message = $oTaranisDossierItem->{errmsg};
					}
				} else {
					$message = $oTaranisDossierNote->{errmsg};
				}
				
				$useractionText .= $noteText . ".\n";
			}

		} else {
			$message = $oTaranisDossierItem->{errmsg};
		}
	} else {
		$message = 'No permission';
	}
	
	if ( $message ) {
		 setUserAction( action => 'discard pending item', comment => "Got error '$message' while trying to discard pending item.");
	} else {
		$saveOk = 1;
		setUserAction( action => 'discard pending item', comment => $useractionText);
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			itemId => uri_escape( $kvArgs{itemid} )
		}
	};
}

sub takeScreenshotOfAssessItem {
	my ($url) = @_;
	
	my %screenshotArgs = ( screenshot_module => Config->{screenshot_module} ); 
	$screenshotArgs{proxy_host} = Config->{proxy_host} if ( Config->{proxy_host} );
	$screenshotArgs{user_agent} = Config->{useragent} if ( Config->{useragent} );
	
	my $screenshot = Taranis::Screenshot->new( %screenshotArgs );

	if ( my $screenshot = $screenshot->takeScreenshot( siteAddress => $url ) ) {

		return {
			binary => $screenshot,
			mimetype => 'image/png'
		}
	}  else {
		return 0;
	}
}
