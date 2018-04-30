#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);	
use Taranis::Template;
use Taranis::Analysis;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Publication;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use strict;
use JSON;
use POSIX;
use Data::Dumper;
use HTML::Entities qw(encode_entities decode_entities);

my @EXPORT_OK = qw(
	openDialogNewEow openDialogEowDetails openDialogPreviewEow 
	saveEowDetails saveNewEow setEowStatus 
	getSentAdvisories getAnalysisForEow
);

sub eow_export {
	return @EXPORT_OK; 
}

sub openDialogNewEow {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl);
	
	my $oTaranisTemplate = Taranis::Template->new;	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
	if ( rightOnParticularization( "end-of-week (email)" ) ) {
		my $currentWeekday = strftime( '%w', localtime( time() ) );
		my $startDate = time() - ( 86400 * ( 2 + $currentWeekday ) );
		my $endDate = time() + ( 86400 * ( 4 - $currentWeekday) );
	
		$vars->{datefrom} = strftime( '%d-%m-%Y', localtime( $startDate ) );
		$vars->{dateto}	= strftime( '%d-%m-%Y', localtime( $endDate ) );
	
		$vars->{eow}->{sent_advisories} = getSentAdvisories( startDate => $vars->{datefrom}, endDate => $vars->{dateto} )->{params}->{sentAdvisoryText};
		$vars->{all_eow_analysis} = $oTaranisAnalysis->getRecordsById( table => "analysis", status => { -ilike => "EOW" } );
		
		$vars->{write_right} = right('write');
		$vars->{isNewEow} = 1;

		$tpl = 'write_eow.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );	
	return { dialog => $dialogContent };	
}

sub openDialogEowDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
	my $publicationId = $kvArgs{id};
	
	if ( rightOnParticularization( "end-of-week (email)" ) ) {
		$vars->{eow} = $oTaranisPublication->getPublicationDetails( 
			table => "publication_endofweek",
			"publication_endofweek.publication_id" => $publicationId
		);

		### SET opened_by OR RETURN locked = 1 ###
		if ( my $opened_by = $oTaranisPublication->isOpenedBy( $publicationId ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $opened_by->{fullname};
		} elsif(  right('write') ) {
			if ( $oTaranisPublication->openPublication( sessionGet('userid'), $publicationId ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}

		my $currentWeekday = strftime( '%w', localtime( time() ) );
		my $startDate = time() - ( 86400 * ( 2 + $currentWeekday ) );
		my $endDate = time() + ( 86400 * ( 4 - $currentWeekday) );
	
		$vars->{datefrom} = strftime( '%d-%m-%Y', localtime( $startDate ) );
		$vars->{dateto}	= strftime( '%d-%m-%Y', localtime( $endDate ) );
	
		$vars->{all_eow_analysis} = $oTaranisAnalysis->getRecordsById( table => "analysis", status => { -ilike => "EOW" } );
		$vars->{write_right} = right('write');

		$tpl = 'write_eow.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );	
	return { 
		dialog => $dialogContent,
		params => { 
			publicationid => $publicationId,
			isLocked => $vars->{isLocked} 
		} 
	};	
}

sub openDialogPreviewEow {
	
	my ( %kvArgs ) = @_;
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $executeRight = right('execute');
	my $userId = sessionGet('userid');

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eow}->{email};

	if ( rightOnParticularization( $typeName ) ) {

		my $oTaranisPublication = Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );
		
		my $eow = $oTaranisPublication->getPublicationDetails( 
			table => "publication_endofweek",
			"publication_endofweek.publication_id" => $publicationId 
		);

		$vars->{eow_id} = $eow->{id};
		$vars->{publication_id} = $eow->{publication_id};
		$vars->{eow_heading} = $eow->{pub_title} . " created on "
			. substr( $eow->{created_on_str}, 6, 2 ) . "-" 
			. substr( $eow->{created_on_str}, 4, 2 ) . "-" 
			. substr( $eow->{created_on_str}, 0, 4 );

		$vars->{created_by_name} = ( $eow->{created_by} ) ? $oTaranisUsers->getUser( $eow->{created_by}, 1 )->{fullname} : undef;
		$vars->{approved_by_name} = ( $eow->{approved_by} ) ? $oTaranisUsers->getUser( $eow->{approved_by}, 1 )->{fullname} : undef;
		$vars->{published_by_name} = ( $eow->{published_by} ) ? $oTaranisUsers->getUser( $eow->{published_by}, 1 )->{fullname} : undef; 
		$vars->{eow} = $eow;
		$vars->{preview} = $eow->{contents};
		$vars->{current_status} = $eow->{status};
		$vars->{user_is_author} = ( $eow->{created_by} eq $userId ) ? 1 : 0;
		
		### SET opened_by OR RETURN locked = 1 ###
		if ( my $openedBy = $oTaranisPublication->isOpenedBy( $eow->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $openedBy->{fullname};
		} elsif( $writeRight || $executeRight ) {
			if ( $oTaranisPublication->openPublication( $userId, $eow->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_eow_preview.tt', $vars, 1 );	
		return { 
			dialog => $dialogContent,
			params => { 
				publicationid => $publicationId,
				isLocked => $vars->{isLocked},
				executeRight => $executeRight,
				userIsAuthor => $vars->{user_is_author},
				currentStatus => $eow->{status}
			}
		};	
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}
}

sub saveNewEow {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eowId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	if ( rightOnParticularization( "end-of-week (email)" ) && right('write') ) {

		my $currentWeekday  = strftime( '%w', localtime( time() ) );
		my $weekEndingDate = strftime( '%d-%m-%Y', localtime( time() + ( 86400 * ( 4 - $currentWeekday) ) ) );

		my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eow}->{email};
		my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
	
		withTransaction {
			if (
				!$oTaranisPublication->addPublication(
					title => "TLP:GREEN End-of-Week",
					created_by => $userId,
					type => $typeId,
					status => "0"
				)
				|| !( $publicationId = $oTaranisPublication->{dbh}->getLastInsertedId("publication") )
				|| !$oTaranisPublication->linkToPublication(
						table => "publication_endofweek",
						closing => $kvArgs{closing_txt},
						introduction => $kvArgs{introduction_txt},
						newondatabank => $kvArgs{newkbitems_txt},
						newsitem => $kvArgs{othernews_txt},
						sent_advisories => $kvArgs{sentadvisories_txt},
						publication_id => $publicationId
				) 
				|| !( $eowId = $oTaranisPublication->{dbh}->getLastInsertedId("publication_endofweek") 
			)) {
				$message = $oTaranisPublication->{errmsg};
			} else {
				my $previewText = $oTaranisTemplate->processPreviewTemplate( "eow", "email", $eowId, $publicationId, 71 );

				if ( !$oTaranisPublication->setPublication( 
					id => $publicationId, 
					contents => $previewText 
				)) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					$saveOk = 1;	
				}
			}
		};
		
		if ( $saveOk ) {
			setUserAction( action => 'add end-of-week', comment => "Added end-of-week" );
		} else {
			setUserAction( action => 'add end-of-week', comment => "Got error '$message' while trying to add end-of-week" );
		}
		
	} else {
		$message = 'No persmission';
	}
	
	return {
		params => { 
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};	
}

sub saveEowDetails {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eowId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	if ( rightOnParticularization( "end-of-week (email)" ) && right('write') ) {

		my $type_name = Taranis::Config->new( Config->{publication_templates} )->{eow}->{email};
		my $type_id = $oTaranisPublication->getPublicationTypeId( $type_name )->{id};
		$publicationId = $kvArgs{pub_id};
		my $eowId = $kvArgs{eow_id};
		
		withTransaction {
			if ( !$oTaranisPublication->setPublicationDetails(
				table => "publication_endofweek",
				where => { id => $eowId },
				closing => $kvArgs{closing_txt},
				introduction => $kvArgs{introduction_txt},
				newondatabank => $kvArgs{newkbitems_txt},
				newsitem => $kvArgs{othernews_txt},
				sent_advisories => $kvArgs{sentadvisories_txt},
			)) {
				$message = $oTaranisPublication->{errmsg};
			} else {
				my $preview_txt = $oTaranisTemplate->processPreviewTemplate( "eow", "email", $eowId, $publicationId, 71 );
				if ( !$oTaranisPublication->setPublication( 
					id => $publicationId, 
					contents => $preview_txt,
					type => $type_id
				)) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					$saveOk = 1;
				}
			}
		};
		if ( !exists( $kvArgs{skipUserAction} ) ) {
			if ( $saveOk ) {
				setUserAction( action => 'edit end-of-week', comment => "Edited end-of-week" );
			} else {
				setUserAction( action => 'edit end-of-week', comment => "Got error '$message' while trying to edit end-of-week");
			}
		}
	}

	return {
		params => { 
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};
}

sub setEowStatus {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;
	my $oTaranisPublication = Publication;
	my $publicationId = $kvArgs{publicationId};
	my $newStatus = $kvArgs{status};
	my $userId = sessionGet('userid'); 
	
	if ( 
		( rightOnParticularization( 'end-of-week (email)' ) && right('write') )
		|| $newStatus =~ /^(0|1|2)$/ 
	) {

		my $eow = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofweek',
			'publication_endofweek.publication_id' => $publicationId 
		);

		my $currentStatus = $eow->{status};
		if (
			 ( $currentStatus eq '0' && $newStatus eq '1' ) || 
			 ( $currentStatus eq '1' && $newStatus eq '0' ) ||
			 ( $currentStatus eq '2' && $newStatus eq '0' ) ||
			 ( $currentStatus eq '1' && $newStatus eq '2' && $eow->{created_by} ne $userId && right('execute') )
		) {

			if ( $newStatus eq '2' ) {
				if ( !$oTaranisPublication->setPublication( 
						id => $publicationId, 
						status => $newStatus,
						approved_on => nowstring(10),
						approved_by => $userId 
					) 
				) {
				
					$message = $oTaranisPublication->{errmsg};
				
				} else {
					$saveOk = 1;
				}			
			} else {
				if ( !$oTaranisPublication->setPublication( 
						id => $publicationId,
						status => $newStatus,
						approved_on => undef,
						approved_by => undef 
					)
				) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					$saveOk = 1;
				}
			}				
		} else {
			$message = "This status change action is not permitted.";
		}
		
		if ( $saveOk ) {
			setUserAction( action => 'change end-of-week status', comment => "Changed end-of-week status from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
		} else {
			setUserAction( action => 'change end-of-week status', comment => "Got error '$message' while trying to change status of end-of-week from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
		}

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};	
}

sub getSentAdvisories {
	my ( %kvArgs ) = @_;
	my ( $sentAdvisoryText );

	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	my $publicationId = $kvArgs{publicationid}; 
	my $start_date = formatDateTimeString( $kvArgs{startDate} );
	my $end_date = formatDateTimeString( $kvArgs{endDate} );
	my $publications = $oTaranisPublication->loadPublicationsCollection(
		table => "publication_advisory",
		status => [3],
		start_date => $start_date,
		end_date => $end_date,
		date_column	=> "published_on",
		hitsperpage => 100,
		offset => 0,
		search => "",
		order_by => "govcertid, version"
	);
	my %level = ( 1 => "H", 2 => "M", 3 => "L" );
	
	foreach my $publication ( @$publications ) {
		
		my $publication_details = $publication->{govcertid} . " "
			. $publication->{version_str}
			. "[" . $level{ $publication->{probability} } . "/"
			. $level{ $publication->{damage} } . "] ";
		
		my $margin = length( $publication_details );
		my $alignment_space;

		for ( my $i = 0; $i < $margin; $i++ ) {
			$alignment_space .= " ";
		}

		$publication->{pub_title} = $oTaranisTemplate->setNewlines( $publication->{pub_title}, $margin, 71 );

		my $title;
		foreach ( split("\n", $publication->{pub_title} ) ) {
			$title .= $_."\n".$alignment_space;
		}

		$title =~ s/\n$alignment_space$//;		

		$sentAdvisoryText .= $publication_details . $title ."\n";
	}

	return {
		params => {
			publicationId => $publicationId,
			sentAdvisoryText => $sentAdvisoryText
		}
	};
}

sub getAnalysisForEow {
	my ( %kvArgs ) = @_;

	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );

	my $publicationId = $kvArgs{publicationid};
	my $analysisId = $kvArgs{analysisid};
	
	my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", status => { -ilike => "EOW" }, id => $analysisId )->[0];

	my $comments = decode_entities( $analysis->{comments} );
	
	my $eow_tags_txt = "";
	my $check = 1;

	while ( $check ) {
		if ( $comments =~ s/(<eow>(.*?)<\/eow>)//is ) {	
			$eow_tags_txt .= trim $2;
			$check = 1;	
		} else {
			$check = 0;	
		}
	}
	
	$analysis->{comments} = encode_entities( $eow_tags_txt || $comments );

	$analysis->{links} = $oTaranisPublication->getItemLinks( analysis_id => $analysisId );
	
	return {
		params => { 
			analysis => $analysis,
		 	publicationid => $publicationId
		}
	};
}

1;
