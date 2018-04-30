#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config Database);
use Taranis::Template;
use Taranis::ImportPhoto;
use Taranis::SoftwareHardware;
use Taranis::Constituent_Group;
use Taranis::CsvBuilder;
use Taranis::Session qw(sessionGet);
use Text::CSV;
use strict;
use CGI::Simple;
use JSON;
use HTML::Entities qw(encode_entities);

my @EXPORT_OK = qw( 
	displayPhotoIssues searchPhotoIssues getIssueItemHtml openDialogPhotoIssueDetails
	resolveIssue issueReadyForReview acceptIssue closeIssue rejectIssue saveIssue 
	searchSoftwareHardwarePhotoManagement deletePhoto setOkToImport dontImport createIssue importPhoto
	openDialogImportPhoto getPhotoDetails loadImportFile exportEmptyPhoto deleteIssue exportAllPhotos
	exportAllProductsInUSe
);

sub photo_management_export {
	return @EXPORT_OK;
}

################### ISSUE TYPES ########################
# 1. Not in use by other constituents, search source
# 2. Duplicates found in Taranis
# 3. No match found
# 4. Inform constituent
# 5. Don't import

my %statusDictionary = ( 
	0 => 'pending',
	1 => 'readyforreview',
	3 => 'done',
);

sub displayPhotoIssues {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $ip = Taranis::ImportPhoto->new( Config );

	$vars->{issues} = $ip->getIssues();
	$vars->{filterButton} = 'btn-photo-issues-search';
	$vars->{page_bar} = $tt->createPageBar( 1, $ip->{result_count}, 100 );

	$vars->{write_right} = right("write");	
	$vars->{execute_right} = right("execute");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('photo_issues.tt', $vars, 1);
	
	if ( exists( $kvArgs{no_filters} ) && $kvArgs{no_filters} ) {
		return { content => $htmlContent };
	} else {
		my $htmlFilters = $tt->processTemplate('photo_issues_filters.tt', $vars, 1);
		my @js = ('js/photo_import.js', 'js/photo_issue.js');
		return { content => $htmlContent, filters => $htmlFilters, js => \@js };
	}
}

sub openDialogPhotoIssueDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $issueNr, $issue, $softwareHardwareId );

	my $writeRight = right("write"); 
	my $executeRight = right("execute");

	my $tt = Taranis::Template->new;
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$issueNr = $kvArgs{id};
		
		my $ip = Taranis::ImportPhoto->new( Config );
		my $sh = Taranis::SoftwareHardware->new( Config );
		
		$issue = $ip->getIssues( issueNr => $issueNr )->[0];

		if ( !$executeRight && $issue->{status} != '0' ) {
			die 403;
		}
		
		if ( $issue->{issuetype} =~ /^2$/ ) {
			( $vars->{duplicates}, $vars->{totalUsageCount} ) = 
				$ip->getDuplicates(
					producer => $issue->{producer},
					product => $issue->{name},
					type => $issue->{type}
				);
			
			for ( my $i = 0; $i < @{ $vars->{duplicates} }; $i++ ) {
				$vars->{duplicates}->[$i]->{constituentGroups} = $sh->getConstituentUsage( $vars->{duplicates}->[$i]->{id} );
			}

		} elsif ( $issue->{issuetype} =~ /^3$/ && $issue->{soft_hard_id} ) {
			$vars->{selectedSH} = $sh->getList( id => $issue->{soft_hard_id} );
		}

		if ( $issue->{issuetype} !~ /^4$/  ) {
			my $lookUpIssue = ( $issue->{followup_on_issue_nr} ) ? $issue->{followup_on_issue_nr} : $issueNr;
			$vars->{photoList} = $ip->getPhotosForIssue( 'ish.issue_nr' => $lookUpIssue );
		}

		# issue followup depth is max 2
		if ( $issue->{issuetype} =~ /^(1|4)$/ && $issue->{followup_on_issue_nr} ) {
			$issue->{followupIssues} = [];

			my $followupIssue = $ip->getIssues( issueNr => $issue->{followup_on_issue_nr} )->[0];
			push @{ $issue->{followupIssues} }, $followupIssue;

			if ( $followupIssue->{followup_on_issue_nr} ) {
				$followupIssue = $ip->getIssues( issueNr => $followupIssue->{followup_on_issue_nr} )->[0];
				push @{ $issue->{followupIssues} }, $followupIssue;
			}
			$vars->{selectedSH} = $sh->getList( id => $followupIssue->{soft_hard_id} );
		}

		$vars->{issue} = $issue;
		$softwareHardwareId = $issue->{sh_id};

		$vars->{write_right} = $writeRight;
		$tpl = 'photo_issue_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $isFollowupIssue = ( $issue->{followup_on_issue_nr} ) ? 1 : 0;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			executeRight => $executeRight,
			status => $issue->{status},
			issuetype => $issue->{issuetype},
			id => $issueNr,
			isFollowupIssue => $isFollowupIssue,
			softwareHardwareId => $softwareHardwareId
		}  
	};	
}

sub searchPhotoIssues {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $ip = Taranis::ImportPhoto->new( Config ); 

	my $startDate = ( $kvArgs{startdate} ) ? formatDateTimeString( $kvArgs{startdate} ) : "";
	my $endDate = ( $kvArgs{enddate} ) ? formatDateTimeString( $kvArgs{enddate} ) : "";
	
	my $pageNumber  = val_int $kvArgs{'hidden-page-number'} || 1;
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;
	my $offset = ( $pageNumber - 1 ) * $hitsperpage;

	my $search = $kvArgs{search};

	my @status = flat $kvArgs{status};

	$vars->{issues} = $ip->getIssues( 
		status => \@status, 
		search => $search,
		start_date => $startDate,
		end_date => $endDate,																			
		hitsperpage => $hitsperpage,
		offset => $offset
	);

	$vars->{execute_right} = right("execute");
	$vars->{filterButton} = 'btn-photo-issues-search';
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $ip->{result_count}, $hitsperpage );
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('photo_issues.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

sub getIssueItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ip = Taranis::ImportPhoto->new( Config );
	
	my $issueNr = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	my $issue = $ip->getIssues( issueNr => $issueNr )->[0];
 
	if ( $issue ) {

		$vars->{issue} = $issue;
		$vars->{write_right} = right("write");
		$vars->{execute_right} = right("execute");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'photo_issues_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Error: Could not find the issue...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $issueNr,
			issueStatus => lc( $statusDictionary{ $issue->{status} } )
		}
	};
}


sub issueReadyForReview {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr );
	
	my $readyForReview = 0;

	my $ip = Taranis::ImportPhoto->new( Config );

	if ( $kvArgs{issueNr} =~ /^\d+$/ ) {
		$issueNr = $kvArgs{issueNr};
				
		my %update = ( comments => $kvArgs{comments}, status => 1 );
	
		if ( !$ip->setIssue( \%update, { id => $issueNr } ) ) {
			$message = $ip->{message};
			setUserAction( action => 'update photo issue', comment => "Got error '$message' while trying to set issue '#" . $issueNr . "' to Ready For Review");
		} else {
			setUserAction( action => 'update photo issue', comment => "Set issue '#" . $issueNr . "' to Ready For Review");
		}
	} else {
		$message = 'No permission.';
	}

	$readyForReview = 1 if ( !$message );
		
	return { 
		params => {
			message => $message,
			actionOk => $readyForReview,
			id => $issueNr
		}
	};
}

sub acceptIssue {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr, $newIssueNr );

	my $acceptOk = 0;

	my $ip = Taranis::ImportPhoto->new( Config );

	if ( $kvArgs{issueNr} =~ /^\d+$/ && right("execute") ) {
		$issueNr = $kvArgs{issueNr};
		
		my ( $groups, $groupIds, $softwareHardwareId, $issue, $softwareHardware, $softwareHardwareTypes );
		
		my %update = ( comments => $kvArgs{comments}, status => 3 );
	
		$update{resolved_by} = sessionGet('userid');
		$update{resolved_on} = \"NOW()";
												
		my $sh = Taranis::SoftwareHardware->new( Config );
		
		$issue = $ip->getIssue( id => $issueNr );
		
		if ( $issue->{followup_on_issue_nr} ) {
			my $originalIssue = $ip->getIssue( id => $issue->{followup_on_issue_nr} );
			$softwareHardwareId = $originalIssue->{soft_hard_id};
			$groups = $ip->getGroupsByIssueNr( $originalIssue->{id} );
		} elsif ( $issue->{soft_hard_id} ) {
			$softwareHardwareId = $issue->{soft_hard_id};
			$groups = $ip->getGroupsByIssueNr( $issueNr );
		} else {
			$groups = $ip->getGroupsByIssueNr( $issueNr );
		}

		$softwareHardwareTypes = $sh->getBaseTypes();
		
		if ( !$softwareHardwareId ) {

			my $importSoftwareHardware = $ip->getImportSoftwareHardware( 'issue_nr' => $issueNr )->[0];

			if ( $importSoftwareHardware->{cpe_id} ) {
				$softwareHardware = $sh->loadCollection( cpe_id => $importSoftwareHardware->{cpe_id}, deleted => 0 )->[0];
			} else {
				my $softwareHardwareTypes = $sh->getBaseTypes();
				foreach my $type ( keys( %$softwareHardwareTypes ) ) {
					$softwareHardwareTypes->{ lc( delete( $softwareHardwareTypes->{$type} ) ) } = lc( $type ); 
				} 	

				$softwareHardware = $sh->loadCollection(  
					producer => { -ilike => $importSoftwareHardware->{producer} },
					name => { -ilike => $importSoftwareHardware->{name} },
					type => $softwareHardwareTypes->{ lc( $importSoftwareHardware->{type} ) },																															
					deleted => 0, 
				)->[0];
			}
			
			$softwareHardwareId = $softwareHardware->{id};
		}
		
		withTransaction {
			if ( $ip->setIssue( \%update, { id => $issueNr } ) ) {

				foreach my $group ( @$groups ) {
								
					my $shType = ( exists( $softwareHardwareTypes->{ $softwareHardware->{type} } ) ) 
						? $softwareHardwareTypes->{ $softwareHardware->{type} } 
						: '';
								
					my $issueDescription = "Added $softwareHardware->{producer} $softwareHardware->{name} to the photo of constituent $group->{name}.";
					my $issueComments = "Constituent $group->{name} needs to be informed about the addition of $softwareHardware->{producer} $softwareHardware->{name} to their photo.";
								
					if ( 
						!$ip->importSoftwareHardware( $group->{id}, $softwareHardwareId )
						 || !( $newIssueNr = $ip->createIssue( $issueDescription, 4, $issueComments, $issueNr ) )
					) {
						$message = $ip->{errmsg};
					}
				} 
			} else {
				$message = $ip->{errmsg};
			}
		};
	} else {
		$message = 'No permission.';
	}
		
	$acceptOk = 1 if ( !$message );
	if ( $acceptOk ) {
		setUserAction( action => 'resolve photo issue', comment => "Resolved issue '#" . $issueNr . "'");
	} else {
		setUserAction( action => 'resolve photo issue', comment => "Got error '$message' while trying resolve issue '#" . $issueNr . "'");
	}

	return { 
		params => {
			message => $message,
			actionOk => $acceptOk,
			id => $issueNr,
			newIssueNr => $newIssueNr
		}
	};	
}

sub closeIssue {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr );
	
	my $closeOk = 0;
	my $ip = Taranis::ImportPhoto->new( Config );
	
	if ( $kvArgs{issueNr} =~ /^\d+$/ && right("execute") ) {
		$issueNr = $kvArgs{issueNr};
		
		my %update = ( 
			comments => $kvArgs{comments}, 
			status => 3,
			resolved_by => sessionGet('userid'),
			resolved_on => \"NOW()"
		);
	
		if ( !$ip->setIssue( \%update, { id => $issueNr } ) ) {
			$message = $ip->{message};
			setUserAction( action => 'resolve photo issue', comment => "Got error '$message' while trying resolve issue '#" . $issueNr . "'");
		} else {
			setUserAction( action => 'resolve photo issue', comment => "Resolved issue '#" . $issueNr . "'");
		}
	} else {
		$message = 'No permission.';
	}

	$closeOk = 1 if ( !$message );
		
	return { 
		params => {
			message => $message,
			actionOk => $closeOk,
			id => $issueNr
		}
	};	
};

sub rejectIssue { 
	my ( %kvArgs) = @_;
	my ( $message, $issueNr );
	
	my $rejectOk = 0;
	my $ip = Taranis::ImportPhoto->new( Config );
	
	if ( $kvArgs{issueNr} =~ /^\d+$/ && right("execute") ) {
		$issueNr = $kvArgs{issueNr};
		
		my %update = ( comments => $kvArgs{comments}, status => 0 );
	
		if ( !$ip->setIssue( \%update, { id => $issueNr } ) ) {
			$message = $ip->{message};
			setUserAction( action => 'reject photo issue', comment => "Got error '$message' while trying reject issue '#" . $issueNr . "'");
		} else {
			setUserAction( action => 'reject photo issue', comment => "Rejected issue '#" . $issueNr . "'");
		}
	} else {
		$message = 'No permission.';
	}

	$rejectOk = 1 if ( !$message );
		
	return { 
		params => {
			message => $message,
			actionOk => $rejectOk,
			id => $issueNr
		}
	};	
}

# sub resolveIssue is for issues of type 2 and 3
sub resolveIssue {
	my ( %kvArgs) = @_;
	my ( $newIssueNr, $message );

	my $writeRight = right("write"); 
	my $executeRight = right("execute");
	my $resolveOk = 0;
	

	if ( !$executeRight ) {
		die 403;
	}
				
	my $issueNr = $kvArgs{issueNr};
	my $comments = $kvArgs{comments};
	my $issueType = $kvArgs{type};
	my $softwareHardwareId = $kvArgs{soft_hard_id};
	my $createNewIssue = ( $kvArgs{create_new_issue} ) ? $kvArgs{create_new_issue} : 0;

	my ( $otherSoftwareHardwareIds_json, $otherSoftwareHardwareIds);
	if ( $issueType =~ /^2$/ ) {
		$otherSoftwareHardwareIds_json = $kvArgs{other_sh_ids};
		$otherSoftwareHardwareIds_json =~ s/\&quot;/"/g;
		$otherSoftwareHardwareIds = from_json( $otherSoftwareHardwareIds_json );
	}

	my $ip = Taranis::ImportPhoto->new( Config );
	my $sh = Taranis::SoftwareHardware->new( Config );
								
	my $groups = $ip->getGroupsByIssueNr( $issueNr );
				
	my $softwareHardwareDetails = $sh->loadCollection( id => $softwareHardwareId )->[0];
	my $softwareHardwareTypes = $sh->getBaseTypes();
				
	withTransaction {
		# save issue
		if ( $ip->setIssue( { 
				comments => $comments, 
				soft_hard_id => $softwareHardwareId,
				status => 3,
				resolved_by => sessionGet('userid'),
				resolved_on => \"NOW()",
				create_new_issue => $createNewIssue
			}, 
			{ id => $issueNr } ) 
		) {

			if ( $issueType =~ /^2$/ ) {
				# for all constituents which have one of the duplicates in their existing
				# photo, the selected software/hardware will be set
		
				foreach my $oldId ( @$otherSoftwareHardwareIds ) {
					if ( 
						$ip->{dbh}->checkIfExists( { soft_hard_id => $oldId }, 'soft_hard_usage' ) 
						&& !$ip->setConstituentUsage( oldId => $oldId, newId => $softwareHardwareId ) 
					) {
						$message = $ip->{errmsg};
					}
				}
			}

			if ( $createNewIssue ) {
					
				my $issueDescription = "Not in use by constituents (search for new source?)";
				my $issueComments = "";
		
				if ( $ip->createIssue( $issueDescription, 1, $issueComments, $issueNr ) ) {
					$newIssueNr = $ip->{dbh}->getLastInsertedId( 'import_issue' );
				} else {
					$message = $ip->{errmsg};
				} 
			} else {

				foreach my $group ( @$groups ) {
					# check if there is a open import for group
					if ( 
						!$ip->{dbh}->checkIfExists( { group_id => $group->{id}, imported_on => undef }, 'import_photo' )
						&& !$sh->countUsage( group_id => $group->{id}, soft_hard_id => $softwareHardwareId ) 
					) {
					
						my $shType = ( exists( $softwareHardwareTypes->{ $softwareHardwareDetails->{type} } ) ) 
							? $softwareHardwareTypes->{ $softwareHardwareDetails->{type} } 
							: '';
				
						my $issueDescription = "Added $softwareHardwareDetails->{producer} $softwareHardwareDetails->{name} to the photo of constituent $group->{name}.";
						my $issueComments = "Constituent $group->{name} needs to be informed about the addition of '$softwareHardwareDetails->{producer} $softwareHardwareDetails->{name}' to their photo.";
			
						if ( 
							!$ip->importSoftwareHardware( $group->{id}, $softwareHardwareId ) 
							|| !( $newIssueNr = $ip->createIssue( $issueDescription, 4, $issueComments, $issueNr ) )	
						) {
							$message = $ip->{errmsg};
						}
					}
				}
			}
		} else {
			$message = $ip->{errmsg};					
		}
	};
	
	$resolveOk = 1 if ( !$message );
	if ( $resolveOk ) {
		setUserAction( action => 'resolve photo issue', comment => "Resolved issue '#" . $issueNr . "'");
	} else {
		setUserAction( action => 'resolve photo issue', comment => "Got error '$message' while trying resolve issue '#" . $issueNr . "'");
	}
		
	return {
		params => {
			message => $message,
			actionOk => $resolveOk,
			id => $issueNr,
			newIssueNr => $newIssueNr
		}
	};
}

sub saveIssue {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr );
	
	my $saveOk = 0;
	my $ip = Taranis::ImportPhoto->new( Config );
	
	if ( $kvArgs{issueNr} =~ /^\d+$/) {
		$issueNr = $kvArgs{issueNr};
		my $comments = $kvArgs{comments};

		my $softwareHardwareId = ( $kvArgs{soft_hard_id} ) ? $kvArgs{soft_hard_id} : undef;

		my $createNewIssue = ( $kvArgs{create_new_issue} ) ? $kvArgs{create_new_issue} : 0;

		my $ip = Taranis::ImportPhoto->new( Config );

		if ( !$ip->setIssue( { 
				comments => $comments, 
				soft_hard_id => $softwareHardwareId,
				create_new_issue => $createNewIssue 
			}, 
			{ id => $issueNr } ) 
		) {
			$message = $ip->{errmsg};
			setUserAction( action => 'edit photo issue', comment => "Got error '$message' while editing issue '#" . $issueNr . "'");
		} else {
			setUserAction( action => 'edit photo issue', comment => "Edited issue '#" . $issueNr . "'");
		}
	} else {
		$message = 'No permission.';
	}
	
	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			id => $issueNr
		}
	};
}

sub searchSoftwareHardwarePhotoManagement {
	my ( %kvArgs) = @_;
	my ( $message, $id );

	my $sh = Taranis::SoftwareHardware->new( Config );
	my $search = $kvArgs{search};
	
	$sh->searchSH( search => $search, not_type => [ 'w' ] );
				
	my @sh_data;
	while ( $sh->nextObject() ) {
		my $record = $sh->getObject();
		$record->{version} = '' if ( !$record->{version} );
		push( @sh_data, $record );
	}
	
	$id = $kvArgs{id} if ( $kvArgs{id} =~ /^\d+$/ );
	
	return {
		params => {
			data => \@sh_data,
			id => $id
		}
	};
}

# preconditions: 
#	- only issuetypes 1,2 en 3
#	- cannot be a followupissue
sub deleteIssue {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr );

	my $deleteOk = 0;

	my $ip = Taranis::ImportPhoto->new( Config );

	if ( $kvArgs{issueNr} =~ /^\d+$/ && right("execute") ) {
		$issueNr = $kvArgs{issueNr};
		
		my $groups = $ip->getGroupsByIssueNr( $issueNr );

		my $softwareHardware = $ip->getImportSoftwareHardware( 'issue_nr' => $issueNr )->[0];
		
		withTransaction {
			# create inform issues for imported photos with relation to issue
			foreach my $group ( @$groups ) {

				my $issueDescription = "Deleted issue which relates to the photo import of constituent $group->{name}.";
				my $issueComments = "Constituent $group->{name} needs to be informed about not including $softwareHardware->{producer} $softwareHardware->{name} in their photo.";
									
				if ( !$ip->createIssue( $issueDescription, 4, $issueComments ) ) {
					$message = $ip->{errmsg};
				}
			}

			if ( !$ip->unlinkFromIssue( $issueNr ) ) {
				$message = $ip->{errmsg};
			}
			
			if ( !$ip->deleteIssue( id => $issueNr ) ) {
				$message = $ip->{errmsg};
			}
		};
		
	} else {
		$message = 'No permission.';
	}
		
	$deleteOk = 1 if ( !$message );
	if ( $deleteOk ) {
		setUserAction( action => 'delete photo issue', comment => "Deleted issue '#" . $issueNr . "'");
	} else {
		setUserAction( action => 'delete photo issue', comment => "Got error '$message' while trying to delete issue '#" . $issueNr . "'");
	}

	return { 
		params => {
			message => $message,
			deleteOk => $deleteOk
		}
	};	
}

sub deletePhoto {
	my ( %kvArgs) = @_;
	my ( $message, $photoId, $groupId, $photoDetails );
	
	my $deleteOk = 0;
	
	if ( $kvArgs{id} =~ /^\d+$/ && $kvArgs{groupid} =~ /^\d+$/ && right("execute") ) {
		$photoId = $kvArgs{id};
		$groupId = $kvArgs{groupid};

		my $ip = Taranis::ImportPhoto->new( Config );
		$photoDetails = $ip->getPhotoDetails( $photoId );
		
		withTransaction {
			if (
					!$ip->unlinkSoftwareHardware( 'photo_id' => $photoId )
					|| !$ip->deleteImportPhoto( 'id' => $photoId ) 
			) {
				$message = $ip->{errmsg};
			}
		};

	} else {
		$message = 'No permission.';
	}

	$deleteOk = 1 if ( !$message );
	if ( $deleteOk ) {
		setUserAction( action => 'delete photo', comment => "Deleted import photo for '$photoDetails->{name}'" );
	} else {
		setUserAction( action => 'delete photo', comment => "Got error '$message' while trying to delete photo for '$photoDetails->{name}'" );
	}
	
	return { 
		params => {
			message => $message,
			deleteOk => $deleteOk,
			id => $photoId,
			groupid => $groupId
		}
	};	
}

sub setOkToImport {
	my ( %kvArgs) = @_;
	my ( $message, $softwareHardwareId );
	
	my $importOk = 0;

	if ( $kvArgs{photo_id} =~ /^\d+$/ && $kvArgs{sh_id} =~ /^\d+$/ && right("execute") ) {
		$softwareHardwareId = $kvArgs{sh_id};
		my $ip = Taranis::ImportPhoto->new( Config );
		
		my $softwareHardware = $ip->getImportSoftwareHardware( id => $softwareHardwareId )->[0];
		
		my $okToImport = $softwareHardware->{producer} . ' ' . $softwareHardware->{name};
		$okToImport .= ' ' . $softwareHardware->{version} if ( $softwareHardware->{version} );
		$okToImport .= ' ' . $softwareHardware->{cpe_id} if ( $softwareHardware->{cpe_id} );
		
		if ( !$ip->setOkToImport( $kvArgs{photo_id}, $kvArgs{sh_id}, 1 ) ) {
			$message = $ip->{errmsg};
			setUserAction( action => 'update photo', comment => "Got error '$message' while trying to set '$okToImport' to OK to import" );
		} else {
			setUserAction( action => 'update photo', comment => "Marked '$okToImport' OK to import" );
		}

	} else {
		$message = 'No permission.';
	}

	$importOk = 1 if ( !$message );
		
	return { 
		params => {
			message => $message,
			importOk => $importOk,
			id => $softwareHardwareId
		}
	};
}

sub dontImport {
	my ( %kvArgs) = @_;
	my ( $message, $photoId, $issueNr, $softwareHardwareId, $softwareHardware, $photoDetails );
	
	my $noImportOk = 0;

	if ( $kvArgs{photo_id} =~ /^\d+$/ && $kvArgs{sh_id} =~ /^\d+$/ && right("execute") ) {
		my $ip = Taranis::ImportPhoto->new( Config );
		
		my $photoId = $kvArgs{photo_id};
		$softwareHardwareId = $kvArgs{sh_id};

		$softwareHardware = $ip->getImportSoftwareHardware( id => $softwareHardwareId )->[0];
		$photoDetails = $ip->getPhotoDetails( $photoId );

		my $issueDescription = "Do not import '$softwareHardware->{producer} $softwareHardware->{name}' for $photoDetails->{name}"; 
		my $issueComments = "Constituent: " . $photoDetails->{name}
			. "\nProducer: " . $softwareHardware->{producer}
			. "\nProduct: " . $softwareHardware->{name}
			. "\nType: " . $softwareHardware->{type}
			. "\nCPE: " . $softwareHardware->{cpe_id};
				
		withTransaction {
			$ip->setOkToImport( $photoId, $softwareHardwareId, 0 )
			&& ( $issueNr = $ip->createIssue( $issueDescription, 5, $issueComments ) )
		} or $message = $ip->{errmsg};
	} else {
		$message = 'No permission.';
	}
	
	my $dontImport = $softwareHardware->{producer} . ' ' . $softwareHardware->{name};
	$dontImport .= ' ' . $softwareHardware->{version} if ( $softwareHardware->{version} );
	$dontImport .= ' ' . $softwareHardware->{cpe_id} if ( $softwareHardware->{cpe_id} );
	
	$noImportOk = 1 if ( !$message );
	if ( $noImportOk ) {
		setUserAction( action => 'update photo', comment => "Removed '$dontImport' from photo import for '$photoDetails->{name}'" );
	} else {
		setUserAction( action => 'update photo', comment => "Got error '$message' while trying to remove '$dontImport' from photo import for '$photoDetails->{name}'" );
	}

	return { 
		params => {
			message => $message,
			noImportOk => $noImportOk,
			id => $issueNr,
			softwareHardwareId => $softwareHardwareId
		}
	};
}

sub createIssue {
	my ( %kvArgs) = @_;
	my ( $message, $issueNr, $description, $issueType, $softwareHardwareId );
	
	my $createOk = 0;

	if ( right("execute") ) {
		my $ip = Taranis::ImportPhoto->new( Config );

		$description = $kvArgs{description};
		$softwareHardwareId = $kvArgs{sh_id};
		$issueType = $kvArgs{type};
		withTransaction {
			if ( $issueNr = $ip->createIssue( $description, $issueType )	) {
				if ( !$ip->linkToIssue( $issueNr, $softwareHardwareId ) ) {
					$message = $ip->{errmsg};
				}
			} else {
				$message = $ip->{errmsg};
			}
		};

	} else {
		$message = 'No permission.';
	}

	$createOk = 1 if ( !$message );
	if ( $createOk ) {
		setUserAction( action => 'create photo issue', comment => "Created photo issue '#" . $issueNr . "'" );
	} else {
		setUserAction( action => 'create photo issue', comment => "Got error '$message' while trying to create photo issue '#" . $issueNr . "'" );
	}
	
	return { 
		params => {
			message => $message,
			createOk => $createOk,
			id => $issueNr,
			description => $description,
			softwareHardwareId => $softwareHardwareId
		}
	};
}

sub importPhoto {
	my ( %kvArgs) = @_;
	my ( $message, $photoId, $issueNr, @closedIssues, $photoDetails );

	my $importOk = 0;
	if ( right("execute") && $kvArgs{id} =~ /^\d+$/ ) {
		my $ip = Taranis::ImportPhoto->new( Config );
		my $sh = Taranis::SoftwareHardware->new( Config );
		my $cg = Taranis::Constituent_Group->new( Config );
		my $csv = Taranis::CsvBuilder->new();
		
		$photoId = $kvArgs{id};
				
		my $photo = $ip->getNewPhoto( 'ip.id' => $photoId );
		$photoDetails = $ip->getPhotoDetails( $photoId );

		my $oldPhoto = $cg->getSoftwareHardware( $photoDetails->{group_id} );
		my $sortedPhoto = $ip->sortNewPhoto( $photo, $photoDetails->{group_id}, $photoId );				
		my $deleteList 	= $ip->getDeleteList( $sortedPhoto, $oldPhoto );
				
		my $softwareHardwareWithOpenIssues = $ip->getImportSoftwareHardwareWithOpenIssues( photo_id => $photoId );
				
		my $dontImportList = $ip->getNewPhoto( ok_to_import => 0, photo_id => $photoId );

		my $issueListStatus2 = $ip->getIssues( status => [2], photo_id => $photoId );
				
		my @closeIssueList;
		foreach my $issue ( @$issueListStatus2 ) {
			if ( $ip->countOpenImports( $issue->{ii_id} ) == 1 ) {
				push @closeIssueList, $issue->{ii_id};						
			}
		}

		my $softwareHardwareTypes = $sh->getBaseTypes();
		
		foreach my $type ( keys( %$softwareHardwareTypes ) ) {
			$softwareHardwareTypes->{ lc( delete( $softwareHardwareTypes->{$type} ) ) } = lc( $type ); 
		} 	

		my ( @shWithCpe, @shNoCpe, @shWithSoftHardId );

		my $doRollBack = 0;
		my %softwareHardwareIDs;				
		IMPORT: {

#		1. sort sh_items in three categories, namely 
#			 ones whith issue type 2 or 3 ( with status 2 or 3 ),
#			 ones with exact match on cpe_id
#			 ones with exact match but not on cpe_id

#TODO:	1.1 foreach issue of type 2 or 3 check if the soft_hard_id still exists
			SOFTWAREHARDWARE:
			foreach my $softwareHardware ( @$sortedPhoto ) {
				if ( defined( $softwareHardware->{alreadyInPhoto} ) ) {
					$softwareHardwareIDs{ $softwareHardware->{soft_hard_id} } = 1;
					next SOFTWAREHARDWARE;
				}
				
				if ( 
					 ( defined( $softwareHardware->{inUse} ) && $softwareHardware->{inUse} =~ /^0$/ )
					 || defined( $softwareHardware->{hasDuplicates} )
					 || defined( $softwareHardware->{noMatch} )
				) {
					$message = "Cannot import photo, because import list still has unresolved issues.";
					last IMPORT;
				}
				
				if ( defined( $softwareHardware->{hasClosedIssue} ) && $softwareHardware->{issueType} =~ /^(2|3)$/ ) {
					push @shWithSoftHardId, $softwareHardware;
				} elsif ( defined( $softwareHardware->{hasClosedIssue} ) ) {
					
					if ( 	
						$softwareHardware->{cpe_id} 
						&& $ip->{dbh}->checkIfExists( { cpe_id => $softwareHardware->{cpe_id} }, 'software_hardware', "IGNORE_CASE" ) 
					) {
						push @shWithCpe, $softwareHardware;
					} else {
						push @shNoCpe, $softwareHardware;
					}
					
				} elsif ( defined( $softwareHardware->{exactMatch} ) && defined( $softwareHardware->{noCpe} ) ) {
						
					push @shNoCpe, $softwareHardware;
				
				} elsif ( defined( $softwareHardware->{exactMatch} ) ) {

					push @shWithCpe, $softwareHardware;
						
				} else {
					$message .= "Cannot import photo. There's a problem with importing $softwareHardware->{producer} $softwareHardware->{name}. (1)";
					last IMPORT;
				}
			}

#		2. fetch all the soft_hard_id for all categories

			foreach my $softwareHardware ( @shNoCpe ) {
			
				my $noCpeSearch = $sh->loadCollection(   
					producer => { -ilike => $softwareHardware->{producer} } , 
					name => { -ilike => $softwareHardware->{name} },
					type => $softwareHardwareTypes->{ lc( $softwareHardware->{type} ) }, 
					deleted  => 0 
				 );

				if ( scalar( @$noCpeSearch ) != 1 ) {
					$message = "Cannot import photo. Could not find exact match for $softwareHardware->{producer} $softwareHardware->{name}. ";
					last IMPORT;
				}
				
				$softwareHardware->{soft_hard_id} = $noCpeSearch->[0]->{id};
			}
				
			foreach my $softwareHardware ( @shWithCpe ) {
				
				my $cpeSearch = $sh->loadCollection(   
					cpe_id => $softwareHardware->{cpe_id},
					deleted => 0 
				);

				$softwareHardware->{soft_hard_id} = $cpeSearch->[0]->{id};
			}					
				
			$ip->{dbh}->startTransaction();

#		3. import all new
			
			foreach my $softwareHardware ( @shWithSoftHardId, @shNoCpe, @shWithCpe ) {
				if ( !exists( $softwareHardwareIDs{ $softwareHardware->{soft_hard_id} } ) ) {
					$softwareHardwareIDs{ $softwareHardware->{soft_hard_id} } = 1;
					if ( !$ip->importSoftwareHardware( $photoDetails->{group_id}, $softwareHardware->{soft_hard_id} ) ) {
						$message .= "Cannot import photo. There's a problem with importing $softwareHardware->{producer} $softwareHardware->{name}. (2) " . $ip->{errmsg};
						$doRollBack = 1;		
						last IMPORT;							
					}
				}
			}

#		4. delete all from delete list

			$csv->addLine( "Producer", "Product", "CPE", "Type" );
				
			DELETELIST:
			foreach my $softwareHardware ( @$deleteList ) {
				next DELETELIST if ( !$softwareHardware );
				next DELETELIST if ( exists( $softwareHardwareIDs{ $softwareHardware->{id} } ) );
				
				if ( !$ip->removeSoftwareHardwareUsage( $photoDetails->{group_id}, $softwareHardware->{id} ) ) {
					$message .= "Cannot import photo. There's a problem with remove $softwareHardware->{producer} $softwareHardware->{name} from old photo. " . $ip->{errmsg};
					$doRollBack = 1;		
					last IMPORT;							
				}
			
				$csv->addLine( $softwareHardware->{producer}, $softwareHardware->{name}, $softwareHardware->{cpe_id}, $softwareHardware->{description} );
			}
			my $csvDeleteList = $csv->print_csv();

#		5. create new 'inform' issue with delete list, ignore list and issue list as info
			$csv->clear_csv();
			$csv->addLine( "Producer", "Product", "CPE", "Type" );
			
			my $checkString = "";
			foreach my $softwareHardware ( @$dontImportList ) {
				$csv->addLine( $softwareHardware->{producer}, $softwareHardware->{name}, $softwareHardware->{cpe_id}, $softwareHardware->{type} );
				$checkString .= $softwareHardware->{producer} . $softwareHardware->{name} . $softwareHardware->{cpe_id} . $softwareHardware->{type};
			}
				
			foreach my $softwareHardware ( @$softwareHardwareWithOpenIssues ) {
				
				if ( $checkString !~ /$softwareHardware->{producer}$softwareHardware->{name}$softwareHardware->{cpe_id}$softwareHardware->{type}/ ) {
					$csv->addLine( $softwareHardware->{producer}, $softwareHardware->{name}, $softwareHardware->{cpe_id}, $softwareHardware->{type} );
				}
			}
				
			my $cvsDontImportList = $csv->print_csv();
			my $dateTimeNow = substr( nowstring(7), 0, -3 );
			my $issueDescription = "Photo import for $photoDetails->{name} done on $dateTimeNow.";
			
			my $issueComments = "Deleted items from old photo in CSV: \n\n== BEGIN ==\n\n" . $csvDeleteList . "\n== END ==\n\n"
				. "Items that are not imported in Taranis: \n\n== BEGIN ==\n\n" . $cvsDontImportList . "\n== END ==\n\n";
				
			if ( !( $issueNr = $ip->createIssue( $issueDescription, 4, $issueComments )	) ) {
				$message .= "Cannot import photo. Could not create 'Inform constiuent' issue: " . $ip->{errmsg};
				$doRollBack = 1;		
				last IMPORT;
			}

#		6. close issues that have no links to other photo imports

			foreach my $issue ( @closeIssueList ) {
				push @closedIssues, $issue;

				if ( !$ip->setIssue( { status => 3 }, { id => $issue } ) ) {
					$message .= "Cannot import photo. There was a problem closing issue #" . $issue . ": " . $ip->{errmsg};
					$doRollBack = 1;
					last IMPORT;
				}
			}

#		7. update photoImport with imported_by and imported_on
					
			if ( 
				!$ip->setImportPhoto( 
					{ imported_by => sessionGet('userid'), imported_on => \"NOW()" },
					{ id => $photoId }																		  
				) 
			) {
				$message .= "Cannot import photo. There was a problem updating the photo details: " . $ip->{errmsg};
				$doRollBack = 1;		
				last IMPORT;
			}
				
			$ip->{dbh}->commitTransaction();
				
		} # END IMPORT BLOCK
			
		if ( $message && $doRollBack	) {
			$ip->{dbh}->{db_error_msg} = $message;
			$ip->{dbh}->rollbackTransaction();
		} else {
			$importOk = 1;
		}
	}

	if ( $importOk ) {
		setUserAction( action => 'import photo', comment => "Imported photo for '$photoDetails->{name}'" );
	} else {
		setUserAction( action => 'import photo', comment => "Got error '$message' while trying to import photo for '$photoDetails->{name}'" );
	}
	
	return { 
		params => {
			message => $message,
			importOk => $importOk,
			id => $issueNr,
			photoId => $photoId,
			closedIssues => \@closedIssues
		}
	};
}

sub openDialogImportPhoto {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $issueNr );

	my $writeRight = right("write"); 

	my $tt = Taranis::Template->new;
	
	if ( right("execute") ) {

		my $cg = Taranis::Constituent_Group->new( Config );
		my $ip = Taranis::ImportPhoto->new( Config );
		
		my $importList = $ip->getImportList();

		$cg->loadCollection();
		my @constituentGroups;
		
		GROUP:
		while ( $cg->nextObject() ) {
			my $group = $cg->getObject();
			push @constituentGroups, { name => $group->{name}, id => $group->{id} };
		}
			
		$vars->{constituentGroups} = \@constituentGroups;
		$vars->{importList} = $importList;

		$vars->{write_right} = $writeRight;
		$tpl = 'photo_import.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};	
}

sub loadImportFile {
	my ( %kvArgs) = @_;
	my ( $message, $tpl, $vars, $photoId, $filename );
	
	my $loadFileOK = 0;
	my $writeRight = right("write"); 

	my $tt = Taranis::Template->new;
	
	if ( right("execute") && $kvArgs{constituentGroup} =~ /^\d+$/ ) {	
		my $constituentId = $kvArgs{constituentGroup};
		my $separator = ( $kvArgs{separator} =~ /^.$/ ) ? $kvArgs{separator} : ',';
		$filename = scalarParam("csv_file");
		my $fh = CGI->upload($filename);

		my $csv = Text::CSV->new({sep_char => $separator});
		my $ip = Taranis::ImportPhoto->new( Config );
		my $cg = Taranis::Constituent_Group->new( Config );
			
		if ( $fh ) {
				
			$ip->{dbh}->startTransaction();
				
			if ( !$ip->addImportPhoto( group_id => $constituentId ) ) {
				$message = $ip->{errmsg};
			} else {				

				$photoId = $ip->{dbh}->getLastInsertedId( 'import_photo' );
				my %sh_ids;
				my $importCount = 0;

				CSVENTRY:
				while (<$fh>) {
					
					if ( $csv->parse($_) ) {

						my @fields = $csv->fields();

						# remove all starting and trailing spaces
						for ( my $i = 0; $i < @fields; $i++ ) {
							$fields[$i] = trim( $fields[$i] );
							$fields[$i] = encode_entities( $fields[$i] ) if ( $fields[$i] );
						}
						
						my $sh_id;
						if ( !$ip->{dbh}->checkIfExists(
							 {
								producer => $fields[0],
								name => $fields[1],
								cpe_id => $fields[2],
								type => $fields[3]
							 },
							 'import_software_hardware'
							)
						) {

							if ( 
								!$ip->addImportSoftwareHardware(
									producer => $fields[0],
									name => $fields[1],
									cpe_id => $fields[2],
									type => $fields[3]
								) 
							) {
								$message = $ip->{errmsg};
							} else {
								$sh_id = $ip->{dbh}->getLastInsertedId( 'import_software_hardware' );
							}

						} else {
							$sh_id = $ip->getImportSoftwareHardware( 
								producer => $fields[0],
								name => $fields[1],
								cpe_id => $fields[2],
								type => $fields[3]																														
							)->[0]->{id};
						}
							
						if ( exists( $sh_ids{ $sh_id } ) ) {
							# ignore duplicate entry in CSV 
							next CSVENTRY;
						} else {
							$sh_ids{ $sh_id } = 1;
						}
							
						if ( 
							!$ip->addImportPhotoEntry( 
								photo_id => $photoId,
								import_sh => $sh_id
							) 
						) {
							$message = $ip->{errmsg};
						} else {
							$importCount++;
						}

					} else {
						$message = "Failed to parse line: " . $csv->error_input;
					}
				}
				
				if ( $importCount ) {
					$ip->{dbh}->commitTransaction();
					
					my $photo = $ip->getNewPhoto( group_id => $constituentId, imported_on => undef );
					
					my $sortedPhoto = $ip->sortNewPhoto( $photo, $constituentId, $photoId );
	
					$vars->{photoDetails} = $ip->getPhotoDetails( $photoId );
	
					$vars->{importList} = $sortedPhoto;
					
					my $oldPhoto = $cg->getSoftwareHardware( $constituentId );
					
					$vars->{deleteList} = $ip->getDeleteList( $sortedPhoto, $oldPhoto );
					$vars->{issueList} = $ip->getIssues( photo_id => $photoId );
					$tpl = 'photo_import_details.tt';
				} else {
					$ip->{dbh}->{db_error_msg} = 'No photo imports, do rollback!';
					$ip->{dbh}->rollbackTransaction();
					
					$tpl = 'dialog_no_right.tt';
					$message = 'Import failed, maybe the CSV file uses an other separator?';
					$vars->{message} = $message;
				}					
			}
		} else {
			$message = "ERROR: " . $!;
		}
		
	} else {
		$message = 'Invalid input supplied';
		$vars->{message} = $message;
		$tpl = 'dialog_no_right.tt';		
	}

	$loadFileOK = 1 if ( !$message );
	if ( $loadFileOK ) {
		setUserAction( action => 'load photo file', comment => "Loaded file '$filename'" );
	} else {
		setUserAction( action => 'load photo file', comment => "Got error '$message' while trying to load file '$filename'" );
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { 
			loadFileOk => $loadFileOK,
			message => $message,
			id => $photoId
		}  
	};
}

sub getPhotoDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $photoId );

	my $writeRight = right("write"); 

	my $tt = Taranis::Template->new;
	my $importDone = 0;
	
	if ( right("execute") && $kvArgs{id} =~ /^\d+$/ ) {
		$photoId = $kvArgs{id};
		my $ip = Taranis::ImportPhoto->new( Config );
		my $cg = Taranis::Constituent_Group->new( Config );
		
		my $photoDetails = $ip->getPhotoDetails( $photoId );

		if ( $photoDetails->{imported_on} ) {
			$vars->{photoDetails} = $photoDetails;
			$importDone = 1;
			$tpl = 'photo_import_done.tt';
		} else {
			my $photo = $ip->getNewPhoto( 'ip.id' => $photoId );

			my $sortedPhoto = $ip->sortNewPhoto( $photo, $photoDetails->{group_id}, $photoId );

			$vars->{photoDetails} = $photoDetails;
			$vars->{importList} = $sortedPhoto;

			$vars->{dontImportList} = $ip->getNewPhoto( ok_to_import => 0, photo_id => $photoId );

			my $oldPhoto = $cg->getSoftwareHardware( $photoDetails->{group_id} );
			
			$vars->{deleteList} = $ip->getDeleteList( $sortedPhoto, $oldPhoto );
			$vars->{issueList} = $ip->getIssues( photo_id => $photoId );
			$tpl = 'photo_import_details.tt';
		}
	
		$vars->{write_right} = $writeRight;
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { 
			id => $photoId,
			importDone => $importDone 
		}  
	};
}

sub exportEmptyPhoto {
	my ( %kvArgs) = @_;

	my $dbh = Database;	
	
	my $csv = Taranis::CsvBuilder->new( quote_all => 0 );
	$csv->addLine( "Leverancier", "Product", "CPE", "Type" );

	my ( $stmnt, @bind ) = $dbh->{sql}->select( "software_hardware sh", "producer, name, cpe_id, description", { deleted => 0, 'sht.base' => { '!=' => 'w' } }, "producer, name, cpe_id" );
	my %join = ( "JOIN soft_hard_type AS sht" => {"sh.type" => "sht.base"} );
	$stmnt = $dbh->sqlJoin( \%join, $stmnt );
		
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( @bind );
	while ( $dbh->nextRecord() ) {
		my $record = $dbh->getRecord();
		$csv->addLine( $record->{producer}, $record->{name}, $record->{cpe_id}, $record->{description} );
	}

	setUserAction( action => 'export photo', comment => "Exported empty photo" );

	print CGI->header(
		-content_disposition => 'attachment; filename="taranis.photo.csv"',
		-type => 'text/plain',
	);
	print $csv->print_csv();
	
	return {};
}

sub exportAllPhotos {
	my ( %kvArgs) = @_;

	my $dbh = Database;	
	
	my $csv = Taranis::CsvBuilder->new( quote_all => 0 );
	$csv->addLine( "Leverancier", "Product", "CPE", "Type", "Constituent" );

	my $select = "sh.producer, sh.name AS product_name, sh.cpe_id, sht.description, cg.name AS group_name"; 
	my ( $stmnt, @bind ) = $dbh->{sql}->select( "software_hardware sh", $select , { 'sh.deleted' => 0, 'sht.base' => { '!=' => 'w' } }, "cg.name, sh.producer, sh.name, sh.cpe_id" );
	tie my %join, 'Tie::IxHash';
	%join = ( 
		"JOIN soft_hard_usage AS shu" => {"shu.soft_hard_id" => "sh.id"},
		"JOIN constituent_group AS cg" => {"cg.id" => "shu.group_id"},		
		"JOIN soft_hard_type AS sht" => {"sh.type" => "sht.base"} 
	);

	$stmnt = $dbh->sqlJoin( \%join, $stmnt );
		
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( @bind );
	while ( $dbh->nextRecord() ) {
		my $record = $dbh->getRecord();
		$csv->addLine( $record->{producer}, $record->{product_name}, $record->{cpe_id}, $record->{description}, $record->{group_name} );
	}

	setUserAction( action => 'export photo', comment => "Exported all photos" );

	print CGI->header(
		-content_disposition => 'attachment; filename="taranis.all.photos.csv"',
		-type => 'text/plain',
	);
	print $csv->print_csv();
	
	return {};	
}

sub exportAllProductsInUSe {
	my ( %kvArgs) = @_;

	my $dbh = Database;	
	
	my $csv = Taranis::CsvBuilder->new( quote_all => 0 );
	$csv->addLine( "Leverancier", "Product", "CPE", "Type" );

	my $select = "sh.producer, sh.name AS product_name, sh.cpe_id, sht.description"; 
	my ( $stmnt, @bind ) = $dbh->{sql}->select( "software_hardware sh", $select , { 'sh.deleted' => 0 }, "sh.producer, sh.name, sh.cpe_id" );
	tie my %join, 'Tie::IxHash';
	%join = ( 
		"JOIN soft_hard_usage AS shu" => {"shu.soft_hard_id" => "sh.id"},
		"JOIN constituent_group AS cg" => {"cg.id" => "shu.group_id"},		
		"JOIN soft_hard_type AS sht" => {"sh.type" => "sht.base"} 
	);

	$stmnt = $dbh->sqlJoin( \%join, $stmnt );
	$stmnt =~ s/(ORDER.*)/ GROUP BY producer, product_name, cpe_id, description $1/i;
	
	$dbh->prepare( $stmnt );
	$dbh->executeWithBinds( @bind );
	while ( $dbh->nextRecord() ) {
		my $record = $dbh->getRecord();
		$csv->addLine( $record->{producer}, $record->{product_name}, $record->{cpe_id}, $record->{description} );
	}

	setUserAction( action => 'export photo', comment => "Exported all products in use" );

	print CGI->header(
		-content_disposition => 'attachment; filename="taranis.photo.in.use.csv"',
		-type => 'text/plain',
	);
	print $csv->print_csv();
	
	return {};	
}

1;
