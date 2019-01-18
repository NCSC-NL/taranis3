#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);
use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Publication;
use Taranis::Publication::EndOfShift;
use Taranis::Report::ContactLog;
use Taranis::Report::IncidentLog;
use Taranis::Report::SpecialInterest;
use Taranis::Report::ToDo;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use strict;
use JSON;
use POSIX qw(mktime strftime);

my @EXPORT_OK = qw(
	openDialogNewEos openDialogEosDetails openDialogPreviewEos 
	saveEosDetails saveNewEos setEosStatus
);

sub eos_export {
	return @EXPORT_OK; 
}

sub openDialogNewEos {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublicationEndOfShift = Taranis::Publication::EndOfShift->new( Config );
	my $typeName = Config->publicationTemplateName(eos => 'email');

	if ( rightOnParticularization($typeName) ) {

		my $oTaranisUsers = Taranis::Users->new( Config );
		my $users = $oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}

		$vars = getUpdatedContent( Config, {}, 1 );
		$vars->{contactLog} = $vars->{contactLogUpdated};
		$vars->{incidentLog} = $vars->{incidentLogUpdated};
		$vars->{specialInterest} = $vars->{specialInterestUpdated};
		$vars->{done} = $vars->{doneUpdated};
		$vars->{todo} = $vars->{todoUpdated};
		$vars->{users} = \@users;
		$vars->{handler} = sessionGet('userid');
		
		$vars->{write_right} = right('write');
		$vars->{isNewEos} = 1;
		$vars->{publication_type_id} = $oTaranisPublication->getPublicationTypeId($typeName);

		$tpl = 'write_eos.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	return { dialog => $dialogContent };	
}

sub openDialogEosDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	
	my $publicationId = $kvArgs{id};
	
	my $typeName = Config->publicationTemplateName(eos => 'email');
	if ( rightOnParticularization( $typeName ) ) {

		my $eos = $oTaranisPublication->getPublicationDetails(
			table => 'publication_endofshift',
			'publication_endofshift.publication_id' => $publicationId
		);
		my $startTime = $eos->{timeframe_begin};
		my $endTime = $eos->{timeframe_end};
		
		$startTime =~ s/[-:]//g;
		$startTime =~ s/(.*?)\d\d(\.|\+).*/$1/;
		$endTime =~ s/[-:]//g;
		$endTime =~ s/(.*?)\d\d(\.|\+).*/$1/;
		
		$vars = getUpdatedContent( Config, { startTime => $startTime, endTime => $endTime } );
		$vars->{eos} = $eos;
		
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
		
		$vars->{write_right} = right('write');
		$vars->{publication_type_id} = $oTaranisPublication->getPublicationTypeId($typeName);

		$tpl = 'write_eos.tt';
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

sub openDialogPreviewEos {
	
	my ( %kvArgs ) = @_;
	my $vars;
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $executeRight = right('execute');
	my $userId = sessionGet('userid');

	my $typeName = Config->publicationTemplateName(eos => 'email');
	if ( rightOnParticularization( $typeName ) ) {

		my $oTaranisPublication = Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );
		
		my $eos = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofshift',
			'publication_endofshift.publication_id' => $publicationId 
		);

		$vars->{eos_id} = $eos->{id};
		$vars->{publication_id} = $eos->{publication_id};
		$vars->{eos_heading} = $eos->{pub_title} . ' created on '
			. substr( $eos->{created_on_str}, 6, 2 ) . '-' 
			. substr( $eos->{created_on_str}, 4, 2 ) . '-' 
			. substr( $eos->{created_on_str}, 0, 4 );

		$vars->{created_by_name} = ( $eos->{created_by} ) ? $oTaranisUsers->getUser( $eos->{created_by}, 1 )->{fullname} : undef;
		$vars->{approved_by_name} = ( $eos->{approved_by} ) ? $oTaranisUsers->getUser( $eos->{approved_by}, 1 )->{fullname} : undef;
		$vars->{published_by_name} = ( $eos->{published_by} ) ? $oTaranisUsers->getUser( $eos->{published_by}, 1 )->{fullname} : undef; 
		$vars->{eos} = $eos;
		$vars->{preview} = $eos->{contents};
		$vars->{current_status} = $eos->{status};
		
		### SET opened_by OR RETURN locked = 1 ###
		if ( my $openedBy = $oTaranisPublication->isOpenedBy( $eos->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $openedBy->{fullname};
		} elsif( $writeRight || $executeRight ) {
			if ( $oTaranisPublication->openPublication( $userId, $eos->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_eos_preview.tt', $vars, 1 );	
		return { 
			dialog => $dialogContent,
			params => { 
				publicationid => $publicationId,
				isLocked => $vars->{isLocked},
				executeRight => $executeRight,
				currentStatus => $eos->{status}
			}
		};	
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };	
	}
}

sub saveNewEos {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eosId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');
	
	my $oTaranisTemplate = Taranis::Template->new;	
	my $oTaranisPublication = Publication;
	my $typeName = Config->publicationTemplateName(eos => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $timeframe = getTimeframe( \%kvArgs );

		if ( $timeframe->{error} ) {
			$message = $timeframe->{error};
		} else {
			my $typeId = $oTaranisPublication->getPublicationTypeId($typeName);
	
			withTransaction {
				if (
					!$oTaranisPublication->addPublication(
						title => "TLP:AMBER End-of-Shift by $kvArgs{handler}",
						created_by => $userId,
						type => $typeId,
						status => '0'
					)
					|| !( $publicationId = $oTaranisPublication->{dbh}->getLastInsertedId('publication') )
					|| !$oTaranisPublication->linkToPublication(
							table => 'publication_endofshift',
							handler => $kvArgs{handler} || undef,
							timeframe_begin => $timeframe->{begin},
							timeframe_end => $timeframe->{end},
							notes => $kvArgs{notes},
							todo => $kvArgs{todo},
							contact_log => $kvArgs{contact_log},
							incident_log => $kvArgs{incident_log},
							special_interest => $kvArgs{special_interest},
							done => $kvArgs{done},
							publication_id => $publicationId
						) 
					|| !( $eosId = $oTaranisPublication->{dbh}->getLastInsertedId('publication_endofshift') )
				) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					my $previewText = $oTaranisTemplate->processPreviewTemplate( 'eos', 'email', $eosId, $publicationId, 0 );
		
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
			setUserAction( action => 'add end-of-shift', comment => "Added end-of-shift on " . nowstring(5) );
		} else {
			setUserAction( action => 'add end-of-shift', comment => "Got error '$message' while trying to add end-of-shift on " . nowstring(5) );
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

sub saveEosDetails {
	my ( %kvArgs ) = @_;
	my ( $message, $publicationId, $eosId );

	my $saveOk = 0;
	my $userId = sessionGet('userid');

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $typeName = Config->publicationTemplateName(eos => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {
		my $typeId = $oTaranisPublication->getPublicationTypeId($typeName);
		$publicationId = $kvArgs{pub_id};
		$eosId = $kvArgs{eos_id};

		my $timeframe = getTimeframe( \%kvArgs );

		if ( $timeframe->{error} ) {
			$message = $timeframe->{error};
		} else {

			withTransaction {
				if ( !$oTaranisPublication->setPublicationDetails(
					table => "publication_endofshift",
					where => { id => $eosId },
					handler => $kvArgs{handler} || undef,
					timeframe_begin => $timeframe->{begin},
					timeframe_end => $timeframe->{end},
					notes => $kvArgs{notes},
					todo => $kvArgs{todo},
					contact_log => $kvArgs{contact_log},
					incident_log => $kvArgs{incident_log},
					special_interest => $kvArgs{special_interest},
					done => $kvArgs{done}
				) ) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					my $previewText = $oTaranisTemplate->processPreviewTemplate( 'eos', 'email', $eosId, $publicationId, 71 );
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
				setUserAction( action => 'edit end-of-shift', comment => "Edited end-of-shift of " . nowstring(5) );
			} else {
				setUserAction( action => 'edit end-of-shift', comment => "Got error '$message' while trying to edit end-of-shift of " . nowstring(5));
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

sub setEosStatus {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;
	my $oTaranisPublication = Publication;
	my $publicationId = $kvArgs{publicationId};
	my $newStatus = $kvArgs{status};
	my $userId = sessionGet('userid'); 
	my $typeName = Config->publicationTemplateName(eos => 'email');
	
	if ( 
		( rightOnParticularization( $typeName ) && right('write') )
		|| $newStatus =~ /^(0|1|2)$/ 
	) {

		my $eos = $oTaranisPublication->getPublicationDetails( 
			table => 'publication_endofshift',
			'publication_endofshift.publication_id' => $publicationId 
		);

		my $currentStatus = $eos->{status};
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
			setUserAction( action => 'change end-of-shift status', comment => "Changed end-of-shift of " . nowstring(5) . " from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
		} else {
			setUserAction( action => 'change end-of-shift status', comment => "Got error '$message' while trying to change status of end-of-shift of " . nowstring(5) . " from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
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
  
	my $timeframeBeginDate = formatDateTimeString $timeframeData->{timeframe_begin_date};
	my $timeframeEndDate   = formatDateTimeString $timeframeData->{timeframe_end_date};
	my $timeframeBeginTime = $timeframeData->{timeframe_begin_time};
	my $timeframeEndTime   = $timeframeData->{timeframe_end_time};

	$timeframeBeginDate && $timeframeEndDate
		or $timeframe->{error} = "Invalid date format supplied. Please specify a date by 'dd-mm-yyyy'.";

	# check if times have format 'HH:MM'
	foreach my $time ( $timeframeBeginTime, $timeframeEndTime ) {
		if ( $time !~ /^([01][0-9]|2[0-4]):[0-5][0-9]$/ ) {
			$timeframe->{error} = "Invalid time format supplied. Please specify a time by 'HH:MM'.";
		}
	}
	$timeframe->{begin} = "$timeframeBeginDate $timeframeBeginTime";
	$timeframe->{end}   = "$timeframeEndDate $timeframeEndTime";

	return $timeframe;
}

sub getUpdatedContent {
	my ( $config, $currentShift, $isNewEos ) = @_;
	
	my %updatedContent = ( contactLogUpdated => '', incidentLogUpdated => '', specialInterestUpdated => '', todoUpdated => '' );
	
	my $shifts = $config->{shifts};
	my $nowTime = mktime( localtime() );
	if ( !exists( $currentShift->{startTime} ) ) {
		foreach my $shift ( @{ $shifts->{'shift'} } ) {
			
			my ( $startTime, $endTime );
			my $startTimeCalc = time();
			my $endTimeCalc = time();
			
			if ( $shift->{start} > $shift->{end} ) {
				# shift ends next day
				if ( strftime( '%H%M', localtime() ) < $shift->{end} ) {
					# startdate is yesterday
					$startTimeCalc -= 86400
				} else {
					# enddate is tomorrow
					$endTimeCalc += 86400;
				}
			}
				
			$startTime = mktime( 0, substr( $shift->{start}, 2, 2 ), substr( $shift->{start}, 0, 2 ), [ localtime($startTimeCalc) ]->[3], [ localtime($startTimeCalc) ]->[4], [ localtime($startTimeCalc) ]->[5] );
			$endTime = mktime( 0, substr( $shift->{end}, 2, 2 ), substr( $shift->{end}, 0, 2 ), [ localtime($endTimeCalc) ]->[3], [ localtime($endTimeCalc) ]->[4], [ localtime($endTimeCalc) ]->[5] );
		
			if ( $startTime <= $nowTime && $endTime >= $nowTime ) {
				$currentShift = $shift;
				$currentShift->{startTime} = $startTime;
				$currentShift->{endTime} = $endTime;
			}
		}
	}
	
	if ( $isNewEos ) {
		$updatedContent{currentShift} = $currentShift;
		$updatedContent{currentDateStart} = strftime('%d-%m-%Y', localtime($currentShift->{startTime}) );
		$updatedContent{currentDateEnd} = strftime('%d-%m-%Y', localtime($currentShift->{endTime}) );
	}
	
	my $currentShiftStartFormatted = ( $isNewEos ) ? strftime('%Y%m%d %H%M', localtime($currentShift->{startTime}) ) : $currentShift->{startTime};
	my $currentShiftEndFormatted = ( $isNewEos ) ? strftime('%Y%m%d %H%M', localtime($currentShift->{endTime}) ) : $currentShift->{endTime};
	
	my $oTaranisPublication = Taranis::Publication->new( $config );
	my $oTaranisTemplate = Taranis::Template->new( config => $config );
	my $oTaranisUsers = Taranis::Users->new( $config );
	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( $config );
	my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( $config );
	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( $config );
	my $oTaranisReportToDo = Taranis::Report::ToDo->new( $config );

	### tab contact log
	my $contactLogs = $oTaranisReportContactLog->getContactLog( created => { '>' => $currentShiftStartFormatted } );
	$updatedContent{contactLogUpdated} = $oTaranisTemplate->processTemplate( 'write_eos_contact_log.tt', { contactLogEntries => $contactLogs }, 1 );

	### tab incident log
	my $incidentLogs = $oTaranisReportIncidentLog->getIncidentLog( 'ril.status' => [1,2] );
	$updatedContent{incidentLogUpdated} = $oTaranisTemplate->processTemplate( 'write_eos_incident_log.tt', { incidentLogEntries => $incidentLogs }, 1 );

	### tab to-do
	my $todos = $oTaranisReportToDo->getToDo( done_status => {'!=' => 100} );
	$updatedContent{todoUpdated} = $oTaranisTemplate->processTemplate( 'write_eos_todo.tt', { todos => $todos }, 1 );

	### tab special interests
	my $specialInterests = $oTaranisReportSpecialInterest->getSpecialInterest( date_start => { '<' => \'NOW()' }, date_end => { '>' => \'NOW()' } );
	$updatedContent{specialInterestUpdated} = $oTaranisTemplate->processTemplate( 'write_eos_special_interest.tt', { specialInterests => $specialInterests }, 1 );
	
	### tab done
	$oTaranisUsers->getUserActions( 
		startDate => $currentShiftStartFormatted,
		endDate => $currentShiftEndFormatted,
		action => [ { -like => 'delete report%' }, 'edit to-do done', 'edit incident log status' ]
	);
	
	my @userActions;
	while ( $oTaranisUsers->nextObject() ) {
		push @userActions, $oTaranisUsers->getObject();
	}
	my $vars;
	$vars->{actions} = \@userActions;
	
	$updatedContent{doneUpdated} = $oTaranisTemplate->processTemplate( 'write_eos_done.tt', $vars, 1 );
	my $eosTypeId = $oTaranisPublication->getPublicationTypeId(eos => 'email');
	
	# only add expired items in the first shift of the day
	if ( !$oTaranisPublication->{dbh}->checkIfExists( { type => $eosTypeId, status => 3, published_on => { '>' => \'CURRENT_DATE' } }, 'publication' ) ) {
		my $specialInterestsVars->{specialInterests} = $oTaranisReportSpecialInterest->getSpecialInterest( date_end => { '<' => \'NOW()',  '=' => \"(current_date - '1 second'::interval )" } );
		$updatedContent{doneUpdated} .= $oTaranisTemplate->processTemplate( 'write_eos_special_interest.tt', $specialInterestsVars, 1 );
	}
	
	return \%updatedContent;
}

1;
