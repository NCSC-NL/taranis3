#!/usr/bin/perl	
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Database qw(withTransaction);
use Taranis::Users qw(getUserRights);
use Taranis::Template;
use Taranis::Tagging;
use Taranis::MetaSearch;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Session qw(sessionGet);
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw(
	openDialogAnalyzeDetails saveAnalyzeDetails openDialogNewAnalysis 
	saveNewAnalysis closeAnalysis analyzeDetailsMetaSearch openDialogAnalyzeDetailsReadOnly
);

sub analyze_details_export {
	return @EXPORT_OK; 
}

sub openDialogAnalyzeDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $message, $locked, $openedByFullname, $isJoined );
	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	
	$vars->{pageSettings} = getSessionUserSettings();
	my $id = ( exists( $kvArgs{id} ) && $kvArgs{id} =~ /^\d{8}$/ ) ? $kvArgs{id} : undef;
	
	if ( $id ) {
		my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", id => $id )->[0];
		
		$isJoined = ( $analysis->{status} =~ /^joined$/i ) ? 1 : 0;
		
		$analysis->{idstring} = trim( $analysis->{idstring} );
		$analysis->{name}     = $id =~ m/(\d{4})(\d{4})/ ? "AN-$1-$2" : $id;

	    $vars->{analysis} = $analysis;
		$vars->{items} = $oTaranisAnalysis->getLinkedItems( $id );
		my $tags = $oTaranisTagging->getTagsByItem( $id, "analysis" );
		$vars->{tags} = "@$tags";
		
		my $userId = sessionGet('userid');
		
		if ( my $openedBy = $oTaranisAnalysis->isOpenedBy( $id ) ) {
			$locked = ( $openedBy->{opened_by} =~ $userId ) ? 0 : 1;
			$vars->{openedByFullname} = $openedBy->{fullname};
		} elsif( right("write") ) {
			if ( $oTaranisAnalysis->openAnalysis( $userId, $id ) ) {
				$locked = 0;
			} else {
				$locked = 1;
			}
		} else {
			$vars->{locked} = 1;
		}
		$tpl = 'analyze_details.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$message = 'Invalid id...';
	}
	
	$vars->{idLocked} = $locked;
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent, 
		params => {
			id => $id,
			isLocked => $locked,
			isJoined => $isJoined
		}
	};
}

sub openDialogNewAnalysis {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	if ( right("write") ) {
		$vars->{newAnalysis} = 1;
		$vars->{analysis}->{status} = 'pending';
		$vars->{pageSettings} = getSessionUserSettings();
		$tpl = "analyze_details_tab1.tt";
	} else {
		$tpl = "dialog_no_right.tt";
		$vars->{message} = 'No rights...'; 	
	}	

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );		
	
	return { dialog => $dialogContent };
}

sub saveNewAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $analysisId );
	
	my $analysisIsAdded = 0;
	my $tagsAreSaved = 0;
	
	if ( right("write") ) {
		
		my $oTaranisAnalysis = Taranis::Analysis->new( Config );
		
		if ( $analysisId = $oTaranisAnalysis->addObject( 	
			table => "analysis",
			title => $kvArgs{title}, 
			comments => $kvArgs{comments}, 
			idstring => $kvArgs{idstring}, 
			rating => $kvArgs{rating},
			status => $kvArgs{status}
		)) {
			my $tags_str = $kvArgs{tags}; 
			$tags_str =~ s/,$//;
		
			my @tags = split( ',', $tags_str );

			$tagsAreSaved = 1 if ( !@tags );

			if ( $analysisId ) {

				my $oTaranisTagging = Taranis::Tagging->new( Config );
				withTransaction {
					foreach my $t ( @tags ) {
						$t = trim( $t );

						my $tag_id;
						if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $t }, "tag", "IGNORE_CASE" ) ) {
							$oTaranisTagging->addTag( $t );
							$tag_id = $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
						} else {
							$tag_id = $oTaranisTagging->getTagId( $t );
						}

						if ( !$oTaranisTagging->setItemTag( $tag_id, "analysis", $analysisId ) ) {
							$message = $oTaranisTagging->{errmsg};
						}
					} 
				};
				
			} else {
				$message = "Cannot save tag(s), missing analysis id."
			}
			
			if ( $message ) {
				$message .= " The analysis has been saved.";
			} else {
				$tagsAreSaved = 1;
			}
			
			$analysisIsAdded = 1;
		} else {
			$message = $oTaranisAnalysis->{errmsg};
		}	
	}

	if ( $analysisIsAdded ) {
		setUserAction( action => 'add analysis', comment => "Added analysis with ID AN-" . substr( $analysisId, 0, 4 ) . '-' . substr( $analysisId, 4, 4) );
	} else {
		setUserAction( action => 'add analysis', comment => "Got error while trying to add analysis with title '$kvArgs{title}'");
	}

	return { 
		params => {
			analysisIsAdded => $analysisIsAdded,
			message => $message,
			tagsAreSaved => $tagsAreSaved,
			id => $analysisId
		} 
	};
}

sub saveAnalyzeDetails {
	my ( %kvArgs ) = @_;
	my ( $message );
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
	my $isSaved = 0;
	my $analysisId = ( exists($kvArgs{id}) && $kvArgs{id} =~ /^\d{8}$/ ) ? $kvArgs{id} : undef;	
	
	if ( $analysisId ) {
		if ( !$oTaranisAnalysis->setAnalysis( 
			id => $analysisId,
			title => $kvArgs{title}, 
			comments => $kvArgs{comments}, 
			idstring => $kvArgs{idstring}, 
			rating => $kvArgs{rating},
			status => $kvArgs{status},
			original_status => $kvArgs{original_status} 
		)) {
			$message = $oTaranisAnalysis->{errmsg};
			setUserAction( action => 'edit analysis', comment => "Got error while trying to edit analysis AN-" . substr( $analysisId, 0, 4 ) . '-' . substr( $analysisId, 4, 4) );
		} else {
			$isSaved = 1;
			setUserAction( action => 'edit analysis', comment => "Edited analysis AN-" . substr( $analysisId, 0, 4 ) . '-' . substr( $analysisId, 4, 4) );
		}
	} else {
		$message = 'Invalid id...';
	}

	return {
		params => {
			isSaved => $isSaved,
			message => $message,
			analysisId => $analysisId
		}
	};
}

sub closeAnalysis {
	my ( %kvArgs ) = @_;
	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );

	my $id = $kvArgs{id};

	my $userid = sessionGet('userid');

	my $is_admin = getUserRights( 
		entitlement => "admin_generic", 
		username => $userid 
	)->{admin_generic}->{write_right};

	my $openedBy = $oTaranisAnalysis->isOpenedBy( $id );

	if ( ( exists( $openedBy->{opened_by} ) && $openedBy->{opened_by} eq $userid ) || $is_admin ) {
		$oTaranisAnalysis->closeAnalysis( $id );
	}
	
	return {
		params => { 
			id => $id,
			removeItem => $kvArgs{removeItem}
		}
	};
}

sub analyzeDetailsMetaSearch {
	my ( %kvArgs ) = @_;
	my ( $vars );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisMetaSearch = Taranis::MetaSearch->new( Config );

	my $searchSettings = $oTaranisMetaSearch->dissectSearchString( $kvArgs{ids} );
	my $searchArchive = $kvArgs{archive};
	my $analysisId = $kvArgs{id};
	
	my %searchDBSettings;
	$searchDBSettings{item}->{archive} = $searchArchive;
	$searchDBSettings{analyze}->{searchAnalyze} = 1;
	$searchDBSettings{publication}->{searchAllProducts} = 1;
	$searchDBSettings{publication_advisory}->{status} = 3;
	$searchDBSettings{publication_endofweek}->{status} = 3;

	$vars->{results} = $oTaranisMetaSearch->search( $searchSettings, \%searchDBSettings ); 

	my $analyzeDetailsTab3Html = $oTaranisTemplate->processTemplate( 'analyze_details_tab3.tt', $vars, 1 );

	return {
		params => { 
			searchResultsHtml => $analyzeDetailsTab3Html,
			id => $analysisId 
		}
	};
}

sub openDialogAnalyzeDetailsReadOnly {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $message );
	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	
	$vars->{pageSettings} = getSessionUserSettings();
	
	if ( $kvArgs{id} =~ /^\d{8}$/ ) {
		my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", id => $kvArgs{id} )->[0];
		
		$analysis->{idstring} = trim( $analysis->{idstring} );      
		
		$vars->{analysis} = $analysis;
		$vars->{items} = $oTaranisAnalysis->getLinkedItems( $kvArgs{id} );
		
		my $userId = sessionGet('userid');
		
		$tpl = 'analyze_details_readonly.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$message = 'Invalid id...';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { dialog => $dialogContent };
}

1;
