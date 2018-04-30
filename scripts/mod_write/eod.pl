#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);	
use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication PublicationEndOfDay Database);
use Taranis::Publication;
use Taranis::Publication::EndOfDay;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use strict;
use JSON;
use POSIX;

use Data::Dumper;

my @EXPORT_OK = qw(
	openDialogNewEod openDialogEodDetails openDialogPreviewEod 
	saveEodDetails saveNewEod setEodStatus
	getPublishedAdvisories getVulnerabilityNews getLinkedItems
	getMediaExposureItems getCommunityNewsItems
);

sub eod_export {
	return @EXPORT_OK; 
}

sub openDialogNewEod {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl);
	
	my $oTaranisTemplate = Taranis::Template->new;	
	my $oTaranisPublication = Publication;
	
	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};
	
	if ( rightOnParticularization( $typeName ) ) {
		
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $users = $oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}  
		
		my $latestTimeframeEnd = PublicationEndOfDay->getLatestTimeframeEndOfPublishedEOD();
		$vars->{timeframe_initial} = $latestTimeframeEnd->{timeframe_end};
		
		$vars->{users} = \@users;
		$vars->{organisation} = Config->{organisation};
		
		$vars->{write_right} = right('write');
		$vars->{isNewEod} = 1;
		$vars->{publication_type_id} = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
		
		$tpl = 'write_eod.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );	
	return { dialog => $dialogContent };
}

sub openDialogEodDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	
	my $publicationId = $kvArgs{id};
	
	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};
		
	if ( rightOnParticularization( $typeName ) ) {
		$vars->{eod} = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofday',
			'publication_endofday.publication_id' => $publicationId
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

		my $oTaranisUsers = Taranis::Users->new( Config );
		my $users = $oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}  
	
		$vars->{users} = \@users;
		$vars->{organisation} = Config->{organisation};
		
		$vars->{write_right} = right('write');
		$vars->{publication_type_id} = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};

		$tpl = 'write_eod.tt';
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

sub openDialogPreviewEod {
	my ( %kvArgs ) = @_;
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $executeRight = right('execute');
	my $userId = sessionGet('userid');

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};

	if ( rightOnParticularization( $typeName ) ) {

		my $oTaranisPublication = Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );
		
		my $eod = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofday',
			'publication_endofday.publication_id' => $publicationId 
		);

		$vars->{eod_id} = $eod->{id};
		$vars->{publication_id} = $eod->{publication_id};
		$vars->{eod_heading} = $eod->{pub_title} . ' created on '
			. substr( $eod->{created_on_str}, 6, 2 ) . '-' 
			. substr( $eod->{created_on_str}, 4, 2 ) . '-' 
			. substr( $eod->{created_on_str}, 0, 4 );

		$vars->{created_by_name} = ( $eod->{created_by} ) ? $oTaranisUsers->getUser( $eod->{created_by}, 1 )->{fullname} : undef;
		$vars->{approved_by_name} = ( $eod->{approved_by} ) ? $oTaranisUsers->getUser( $eod->{approved_by}, 1 )->{fullname} : undef;
		$vars->{published_by_name} = ( $eod->{published_by} ) ? $oTaranisUsers->getUser( $eod->{published_by}, 1 )->{fullname} : undef; 
		$vars->{eod} = $eod;
		$vars->{preview} = $eod->{contents};
		$vars->{current_status} = $eod->{status};
		
		### SET opened_by OR RETURN locked = 1 ###
		if ( my $openedBy = $oTaranisPublication->isOpenedBy( $eod->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $openedBy->{fullname};
		} elsif( $writeRight || $executeRight ) {
			if ( $oTaranisPublication->openPublication( $userId, $eod->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_eod_preview.tt', $vars, 1 );	
		return { 
			dialog => $dialogContent,
			params => { 
				publicationid => $publicationId,
				isLocked => $vars->{isLocked},
				executeRight => $executeRight,
				currentStatus => $eod->{status}
			}
		};	
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}
}

sub saveNewEod {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eodId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;	
	my $oTaranisPublication = Publication;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $timeframe = getTimeframe( \%kvArgs );
      
		if ( $timeframe->{error} ) {
			$message = $timeframe->{error};
		} else { 

			my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
			withTransaction {
				if (
					!$oTaranisPublication->addPublication(
						title => 'TLP:AMBER End-of-Day',
						created_by => $userId,
						type => $typeId,
						status => '0'
					)
					|| !( $publicationId = $oTaranisPublication->{dbh}->getLastInsertedId('publication') )
					|| !$oTaranisPublication->linkToPublication(
							table => 'publication_endofday',
							handler => $kvArgs{handler} || undef,
							first_co_handler => $kvArgs{first_co_handler} || undef,
							second_co_handler => $kvArgs{second_co_handler} || undef,
							timeframe_begin => $timeframe->{begin},
							timeframe_end => $timeframe->{end},
							general_info => $kvArgs{general_info},
							vulnerabilities_threats => $kvArgs{vulnerabilities_threats},
							published_advisories => $kvArgs{published_advisories},
							linked_items => $kvArgs{linked_items},
							incident_info => $kvArgs{incident_info},
							community_news => $kvArgs{community_news},
							media_exposure => $kvArgs{media_exposure},
							tlp_amber => $kvArgs{tlp_amber},
							publication_id => $publicationId,
						) 
					|| !( $eodId = $oTaranisPublication->{dbh}->getLastInsertedId('publication_endofday') )
				) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					my $previewText = $oTaranisTemplate->processPreviewTemplate( 'eod', 'email', $eodId, $publicationId, 0 );

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
		}
		
		if ( $saveOk ) {
			setUserAction( action => 'add end-of-day', comment => "Added end-of-day on " . nowstring(5) );
		} else {
			setUserAction( action => 'add end-of-day', comment => "Got error '$message' while trying to add end-of-day on " . nowstring(5) );
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

sub saveEodDetails {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eodId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
		$publicationId = $kvArgs{pub_id};
		$eodId = $kvArgs{eod_id};

		my $timeframe = getTimeframe( \%kvArgs );

		if ( $timeframe->{error} ) {
			$message = $timeframe->{error};
		} else {

			withTransaction {
				if ( !$oTaranisPublication->setPublicationDetails(
					table => "publication_endofday",
					where => { id => $eodId },
					handler => $kvArgs{handler} || undef,
					first_co_handler => $kvArgs{first_co_handler} || undef,
					second_co_handler => $kvArgs{second_co_handler} || undef,
					timeframe_begin => $timeframe->{begin},
					timeframe_end => $timeframe->{end},
					general_info => $kvArgs{general_info},
					vulnerabilities_threats => $kvArgs{vulnerabilities_threats},
					published_advisories => $kvArgs{published_advisories},
					linked_items => $kvArgs{linked_items},
					incident_info => $kvArgs{incident_info},
					community_news => $kvArgs{community_news},
					media_exposure => $kvArgs{media_exposure},
					tlp_amber => $kvArgs{tlp_amber}
				) ) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					my $previewText = $oTaranisTemplate->processPreviewTemplate( 'eod', 'email', $eodId, $publicationId, 71 );
					if ( !$oTaranisPublication->setPublication( 
						id => $publicationId, 
						contents => $previewText,
						type => $typeId
					)) {
						$message = $oTaranisPublication->{errmsg};
					} else {
						$saveOk = 1;
					}
				}
			};
		}

		if ( !exists( $kvArgs{skipUserAction} ) ) {
			if ( $saveOk ) {
				setUserAction( action => 'edit end-of-day', comment => "Edited end-of-day of " . nowstring(5) );
			} else {
				setUserAction( action => 'edit end-of-day', comment => "Got error '$message' while trying to edit end-of-day of " . nowstring(5));
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

# Cleaner in Taranis 4
sub _date_time_pubtype($) {
	my $args      = shift;
	my $message;

	my $beginDate = $args->{begin_date};
	my $endDate   = $args->{end_date};
	my $beginTime = $args->{begin_time};
	my $endTime   = $args->{end_time};
	my $pubtype   = $args->{publicationTypeId};

	# check if dates have format 'dd-mm-yyyy'
	foreach my $date ( $beginDate, $endDate ) {
	    if ( $date !~ /^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[012])-(19|20)\d\d$/ ) {
	        $message = "Invalid date format supplied. Please specify a date by 'dd-mm-yyyy'.";
	    }
	}

	# check if times have format 'HH:MM'
	foreach my $time ( $beginTime, $endTime ) {
	    if ( $time !~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/ ) {
	        $message = "Invalid time format supplied. Please specify a time by 'HH:MM'.";
	    }
	}

	# check if publication_type_id is a number
	if ( $pubtype !~ /^\d+$/ ) {
	    $message = "Cannot collect selected news items, because of invalid input.";
	}

	my ($begin, $end);
	unless($message) {
		$begin = formatDateTimeString($beginDate) . ' ' . $beginTime;
		$end   = formatDateTimeString($endDate)   . ' ' . $endTime;
	}

	($message, $begin, $end, $pubtype);
}

sub _publication_items($$$$) {
	my ($beginDate, $endDate, $pubtype, $group) = @_;

	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $items = $oTaranisAssess->getItemsAddedToPublication($beginDate, $endDate, $pubtype, $group);

	# create standard markup for items. Example:
	# - item title
	# item description
	# item link
	my @text;
	foreach my $item ( @$items ) {
		push @text, "&minus; $item->{title}\n$item->{description}\n$item->{link}";
	}
	join "\n", @text;
}

sub getPublishedAdvisories {
	my ( %kvArgs ) = @_;

	my $publicationId = $kvArgs{publicationid};
	my ($message, $beginDate, $endDate, $publicationTypeId) = _date_time_pubtype(\%kvArgs);

	my $sentPublications    = '';

	if ( !$message ) {

		# collect advisories within timeframe			  
		my $oTaranisPublication = Publication;
		my $advisories = $oTaranisPublication->loadPublicationsCollection( 
			table => 'publication_advisory',
			status => [3],
			start_date => $beginDate,
			end_date => $endDate,
			date_column => 'published_on',
			hitsperpage => 100,
			offset => 0,
			search => '',
			order_by => 'govcertid, version'
		);
		
		# hash to be used to convert int values to readable damage/probability level
		my %level = ( 1 => 'H', 2 => 'M', 3 => 'L' );

		# create standard markup for advisories. Example: NCSC-2012-0001 [v1.00][M/M] My advisory title
		foreach my $publication ( @$advisories ) {

			$sentPublications .= $publication->{govcertid} . ' '
				. $publication->{version_str}
				. '[' . $level{ $publication->{probability} } . '/'
				. $level{ $publication->{damage} } . '] '
				. $publication->{pub_title} ."\n";
		}
	}

	return {
		params => {
			message => $message,
			publicationId => $publicationId,
			sentPublications => $sentPublications
		}
	};	
}

sub getVulnerabilityNews {
	my ( %kvArgs ) = @_;

	my $publicationId       = $kvArgs{publicationid};
	my ($message, $beginDate, $endDate, $pubtype) = _date_time_pubtype(\%kvArgs);

	my $vulnerabilityNews   = $message ? '' :
		_publication_items($beginDate, $endDate, $pubtype, 'vuln_threats');

	return {
		params => {
			message => $message,
			publicationId => $publicationId,
			vulnerabilityNews => $vulnerabilityNews
		}
	};	
}

sub getLinkedItems {
	my %kvArgs = @_;

	# LinkedItems are not linked to the publication, but to all advisories:
	# take the items which got linked to any advisory today.
	my $publicationId = $kvArgs{publicationid};

	my ($message, $beginDate,$endDate, $pubtype) = _date_time_pubtype(\%kvArgs);
	my $eod   = Taranis::Publication::EndOfDay->new->{typeId};

	#XXX item status != deleted?
	my @items = Database->{simple}->query(<<__ITEMS, $beginDate, $endDate, $eod)->hashes;
SELECT i.title, pa.govcertid AS advisory_certid
  FROM advisory_linked_items      AS ali
       JOIN item_publication_type AS ipt ON ali.item_digest = ipt.item_digest
       JOIN item                  AS i   ON ali.item_digest = i.digest
       JOIN publication_advisory  AS pa  ON ali.publication_id = pa.publication_id
 WHERE ali.created BETWEEN ? AND ?
   AND ipt.publication_type      = ?
   AND ipt.publication_specifics = 'linked_item'
__ITEMS

	my @linked_items;
	foreach my $item (@items) {
		push @linked_items, "$item->{advisory_certid} -> $item->{title}";
	}

	return {
		params => {
			message       => $message,
			publicationId => $publicationId,
			linkedItems   => join("\n", sort @linked_items)."\n",
		}
	};	
}

sub getMediaExposureItems {
	my ( %kvArgs ) = @_;

	my $publicationId       = $kvArgs{publicationid};
	my ($message, $beginDate, $endDate, $pubtype) = _date_time_pubtype(\%kvArgs);

	my $mediaExposureItems = $message ? '' :
		_publication_items($beginDate, $endDate, $pubtype, 'media_exposure');

	return {
		params => {
			message => $message,
			publicationId => $publicationId,
			mediaExposureItems => $mediaExposureItems,
		}
	};
}

sub getCommunityNewsItems {
	my ( %kvArgs ) = @_;

	my $publicationId       = $kvArgs{publicationid};
    my ($message, $beginDate, $endDate, $pubtype) = _date_time_pubtype(\%kvArgs);

    my $communityNewsItems = $message ? '' :
        _publication_items($beginDate, $endDate, $pubtype, 'community_news');

	return {
		params => {
			message => $message,
			publicationId => $publicationId,
			communityNewsItems => $communityNewsItems
		}
	};
}

sub setEodStatus {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;
	my $oTaranisPublication = Publication;
	my $publicationId = $kvArgs{publicationId};
	my $newStatus = $kvArgs{status};
	my $userId = sessionGet('userid'); 
	
	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};
	
	if ( 
		( rightOnParticularization( $typeName ) && right('write') )
		|| $newStatus =~ /^(0|1|2)$/ 
	) {

		my $eod = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofday',
			'publication_endofday.publication_id' => $publicationId 
		);

		my $currentStatus = $eod->{status};
		if (
			 ( $currentStatus eq '0' && $newStatus eq '1' ) || 
			 ( $currentStatus eq '1' && $newStatus eq '0' ) ||
			 ( $currentStatus eq '2' && $newStatus eq '0' ) ||
			 ( $currentStatus eq '1' && $newStatus eq '2' && right('execute') )
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
			$message = 'This status change action is not permitted.';
		}

		if ( $saveOk ) {
			setUserAction( action => 'change end-of-day status', comment => "Changed end-of-day of " . nowstring(5) . " from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
		} else {
			setUserAction( action => 'change end-of-day status', comment => "Got error '$message' while trying to change status of end-of-day of " . nowstring(5) . " from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
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


sub getTimeframe {
	my ( $timeframeData )= @_;
	
	my $timeframe = { begin => undef, end => undef, error => undef };
  
	my $timeframeBeginDate = $timeframeData->{timeframe_begin_date};
	my $timeframeEndDate = $timeframeData->{timeframe_end_date};
	my $timeframeBeginTime = $timeframeData->{timeframe_begin_time};
	my $timeframeEndTime = $timeframeData->{timeframe_end_time};
      
	# check if dates have format 'dd-mm-yyyy'
	foreach my $date ( $timeframeBeginDate, $timeframeEndDate ) {
		if ( $date !~ /^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[012])-(19|20)\d\d$/ ) {
			$timeframe->{error} = "Invalid date format supplied. Please specify a date by 'dd-mm-yyyy'.";
		}
	}

	# check if times have format 'HH:MM'
	foreach my $time ( $timeframeBeginTime, $timeframeEndTime ) {
		if ( $time !~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/ ) {
			$timeframe->{error} = "Invalid time format supplied. Please specify a time by 'HH:MM'.";
		}
	}
	$timeframe->{begin} = formatDateTimeString( $timeframeBeginDate ) . ' ' . $timeframeBeginTime;
	$timeframe->{end} = formatDateTimeString( $timeframeEndDate ) . ' ' . $timeframeEndTime;

	return $timeframe; 
}

1;
