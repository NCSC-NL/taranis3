#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config Publication);
use Taranis::Dossier;
use Taranis::Dossier::Contributor;
use Taranis::Dossier::Item;
use Taranis::Dossier::Note;
use Taranis::Publication;
use Taranis::Tagging;
use Taranis::Template;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use Taranis::Screenshot::Phantomjs;
use Taranis::Mail ();

use CGI::Simple;
use Encode;
use File::Basename;
use HTML::Entities;
use JSON;
use Digest::MD5 qw(md5_base64);
use URI::Escape;
use strict;

use Data::Dumper;

my @EXPORT_OK = qw(
	displayDossiers displayMyDossiers openDialogNewDossier saveNewDossier 
	openDialogDossierDetails saveDossierDetails	getDossierItemHtml 
	openDialogDossierPublicationDetails openDialogExportDossier dossierExport
	openDialogJoinDossiers joinDossiers
);

my @js = (
	'js/jquery.timepicker.min.js',
	'js/jquery-textrange/jquery-textrange.js',
	'js/dossier.js',
	'js/dossier_pending.js'
);

sub dossier_export {
	return @EXPORT_OK;
}

sub displayDossiers {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
	
	$search{'dc.username'} = sessionGet('userid') if ( exists( $kvArgs{showMeMine} ) );
	$vars->{dossiers} = $oTaranisDossier->getDossiers( %search );
	
	foreach my $dossier ( @{ $vars->{dossiers} } ) {
		$dossier->{contributors} = $oTaranisDossierContributor->getContributors( dossier_id => $dossier->{id}, is_owner => 1 );
		$dossier->{latestActivity} = $oTaranisDossier->getDateLatestActivity( $dossier->{id} );
	}
	
	$vars->{page_title} = ( exists( $kvArgs{page_title} ) ) ? $kvArgs{page_title} : "All Dossiers";
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('dossier.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('dossier_filters.tt', $vars, 1);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub displayMyDossiers {
	my ( %kvArgs ) = @_;

	$kvArgs{showMeMine} = 1;
	$kvArgs{page_title} = 'My Dossiers';
	return displayDossiers( %kvArgs );
}

sub openDialogNewDossier {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$oTaranisUsers->getUsersList();
	
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @{ $vars->{reminderAccounts} }, { username => $user->{username}, fullname => $user->{fullname} };
			push @{ $vars->{users} }, { username => $user->{username}, fullname => $user->{fullname} }
		}
		
		$tpl = 'dossier_details.tt';
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

sub saveNewDossier {
	my ( %kvArgs) = @_;
	my ( $message, $dossierID );
	my $saveOk = 0;
	

	my $dossierUseractionText = '';
	
	if (
		right("write") 
		&& $kvArgs{tags} 
		&& $kvArgs{contributors} 
		&& $kvArgs{reminder_interval_amount} =~ /^\d+$/ 
		&& $kvArgs{reminder_interval_units} =~ /^(days|months)$/
		&& $kvArgs{reminder_account}
	) {

		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
		my $oTaranisTagging = Taranis::Tagging->new( Config );		
		
		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		$kvArgs{contributors} =~ s/&quot;/"/g;
		$kvArgs{tags} =~ s/,\s*$//;

		my @tags = split( ',', $kvArgs{tags} );

		$oTaranisDossier->{dbh}->startTransaction();
		
		# add new tags and/or get the ID from existing tags
		my ( @tagIDs, @allreadyAssignedTags );
		foreach my $tag ( @tags ) {
			$tag = trim( $tag );

			if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $tag }, "tag", "IGNORE_CASE" ) ) {
				$oTaranisTagging->addTag( $tag );
				push @tagIDs, $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
			} else {
				my $tagID = $oTaranisTagging->getTagId( $tag );
				if ( $oTaranisTagging->{dbh}->checkIfExists( { tag_id => $tagID, item_table_name => 'dossier' }, "tag_item", "IGNORE_CASE" ) ) {
					push @allreadyAssignedTags, $tag;
				} else {
					push @tagIDs, $tagID;
				}
			}
		}
		
		if ( !@allreadyAssignedTags ) {
		
			my %newDossier = ( 
				description => $kvArgs{description},
				reminder_account => $kvArgs{reminder_account},
				reminder_interval => $kvArgs{reminder_interval_amount} . ' ' . $kvArgs{reminder_interval_units}
			);
			
			# add dossier
			if ( $dossierID = $oTaranisDossier->addDossier( %newDossier ) ) {
				$dossierUseractionText .= "\nContributors:\n";
				
				# add contributors
				foreach my $contributor ( @{ from_json( $kvArgs{contributors} ) } ) {
					if ( $oTaranisDossierContributor->addContributor(
						username => $contributor->{username},
						is_owner => $contributor->{is_owner},
						dossier_id => $dossierID
					) ) {
						$dossierUseractionText .= "$contributor->{username}";
						$dossierUseractionText .= " --DOSSIER OWNER--" if ( $contributor->{is_owner} );
						$dossierUseractionText .= "\n";
					} else {
						$message = $oTaranisDossierContributor->{errmsg};
					}
				}
				
				$dossierUseractionText .= "\nTags: " . join(',', @tags);
				
				# add tags to dossier
				foreach my $tagID ( @tagIDs ) {
					if ( !$oTaranisTagging->setItemTag( $tagID, 'dossier', $dossierID ) ) {
						$message = $oTaranisTagging->{errmsg};
					}
				}
	
				my $userDescription = ( $user->{fullname} ) ? $user->{fullname} : $user->{username};
				my $noteText = "Dossier \"$kvArgs{description}\" created by $userDescription.\n$dossierUseractionText";
				my $noteID = $oTaranisDossierNote->addNote( text => $noteText );
				$oTaranisDossierItem->addDossierItem(
					dossier_id => $dossierID,
					note_id => $noteID,
					classification => 4
				);
	
			} else {
				$message = $oTaranisDossier->{errmsg};
			}
			
			if ( $message ) {
				 $oTaranisDossier->{dbh}->rollbackTransaction();
				 setUserAction( action => 'add dossier', comment => "Got error '$message' while trying to add dossier '$kvArgs{description}'");
			} else {
				$oTaranisDossier->{dbh}->commitTransaction();
				$saveOk = 1;
				setUserAction( action => 'add dossier', comment => "Added dossier '$kvArgs{description}'; $dossierUseractionText");
			}
		} else {
			$message = "Can't use tags '@allreadyAssignedTags'. These tags are set for other dossiers.";
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $dossierID,
			insertNew => 1
		}
	};
}

sub openDialogDossierDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $writeRight = right("write");
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $dossier = $oTaranisDossier->getDossiers( id => $kvArgs{id} );
		$vars->{dossier} = $dossier->[0];
		$vars->{contributors} = $oTaranisDossierContributor->getContributors( dossier_id => $kvArgs{id} );

		my $tags = $oTaranisTagging->getTagsByItem( $kvArgs{id}, 'dossier' );
		$vars->{tags} = $tags;

		$oTaranisUsers->getUsersList();

		USER:
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @{ $vars->{reminderAccounts} }, { username => $user->{username}, fullname => $user->{fullname} };

			foreach my $contributor ( @{ $vars->{contributors} } ) {
				next USER if ( $contributor->{username} =~ /^$user->{username}$/ );
			}
			
			push @{ $vars->{users} }, { username => $user->{username}, fullname => $user->{fullname} }
		}

		my $statuses = $oTaranisDossier->getDossierStatuses();
		%{ $vars->{statuses} } = reverse %$statuses;
		$writeRight = 0 if ( $statuses->{ $dossier->[0]->{status} } =~ /^joined$/i );
		
		$tpl = 'dossier_details.tt';
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

sub saveDossierDetails {
	my ( %kvArgs) = @_;
	my ( $message, $dossierID );
	my $saveOk = 0;
	
	
	if ( 
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{tags}
		&& $kvArgs{contributors}
		&& $kvArgs{reminder_interval_amount} =~ /^\d+$/
		&& $kvArgs{reminder_interval_units} =~ /^(days|months)$/
		&& $kvArgs{reminder_account}
		&& $kvArgs{status} =~ /^(1|2|3)$/
	) {
		$dossierID = $kvArgs{id};

		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisTagging = Taranis::Tagging->new( Config );

		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		my $dossierUseractionText = '';

		$kvArgs{contributors} =~ s/&quot;/"/g;
		$kvArgs{tags} =~ s/,\s*$//;

		my @tags = split( ',', $kvArgs{tags} );

		my ( @allreadyAssignedTags );
		foreach my $tag ( @tags ) {
			$tag = trim( $tag );

			if ( $oTaranisTagging->{dbh}->checkIfExists( { name => $tag }, "tag", "IGNORE_CASE" ) ) {
				my $tagID = $oTaranisTagging->getTagId( $tag );
				if ( $oTaranisTagging->{dbh}->checkIfExists( { tag_id => $tagID, item_table_name => 'dossier', item_id => { '!=' => $dossierID } }, "tag_item", "IGNORE_CASE" ) ) {
					push @allreadyAssignedTags, $tag;
				}
			}
		}
		
		if ( !@allreadyAssignedTags ) {
			my $statuses = $oTaranisDossier->getDossierStatuses();
			
			$oTaranisTagging->{dbh}->startTransaction();
	
			my %dossierUpdate = ( 
				description => $kvArgs{description},
				reminder_account => $kvArgs{reminder_account},
				reminder_interval => $kvArgs{reminder_interval_amount} . ' ' . $kvArgs{reminder_interval_units},
				id => $dossierID,
				status => $kvArgs{status}
			);
			
			# edit dossier
			if ( $oTaranisDossier->setDossier( %dossierUpdate ) ) {
				$dossierUseractionText .= "\nDossier $kvArgs{description}\n";
				my @contributors = @{ from_json( $kvArgs{contributors} ) };
				
				$dossierUseractionText .= "\nStatus: " . $statuses->{ $kvArgs{status} } . "\n";
				
				# add/remove contributors
				CONTRIBUTOR:
				foreach my $contributor ( @contributors ) {
					my $isOwner = ( $contributor->{is_owner} ) ? "YES" : "NO";
					
					if ( $oTaranisDossierContributor->{dbh}->checkIfExists( { dossier_id => $dossierID, username => $contributor->{username}, is_owner => $contributor->{is_owner} }, 'dossier_contributor' ) ) {
						next CONTRIBUTOR;
					} elsif ( $oTaranisDossierContributor->{dbh}->checkIfExists( { dossier_id => $dossierID, username => $contributor->{username} }, 'dossier_contributor' ) ) {
						# edit contributor
						if ( $oTaranisDossierContributor->setContributor(
							username => $contributor->{username},
							dossier_id => $dossierID,
							is_owner => $contributor->{is_owner},
						) ) {
							$dossierUseractionText .= "Changed $contributor->{username} is owner: $isOwner\n";
						} else {
							$message = $oTaranisDossierContributor->{errmsg};
						}
					} else {
						# add contributor
						if ( $oTaranisDossierContributor->addContributor(
							username => $contributor->{username},
							is_owner => $contributor->{is_owner},
							dossier_id => $dossierID
						) ) {
							$dossierUseractionText .= "Added $contributor->{username} is owner: $isOwner\n";
						} else {
							$message = $oTaranisDossierContributor->{errmsg};
						}
					}
				}
	
				my @contributorsSQLAbstractNotEqual;
				push @contributorsSQLAbstractNotEqual, -and => { '!=' => pop( @contributors)->{username} };
				push @contributorsSQLAbstractNotEqual, { '!=' => $_->{username} } for @contributors;
				my $contributorsToDelete = $oTaranisDossierContributor->getContributors( dossier_id => $dossierID, 'dc.username' => [ \@contributorsSQLAbstractNotEqual ] );
				
				foreach my $contributor ( @$contributorsToDelete ) {
					# remove contributor
					if ( $oTaranisDossierContributor->removeContributor( dossier_id => $dossierID, username => $contributor->{username} ) ) {
						$dossierUseractionText .= "Removed $contributor->{username}\n";
					} else {
						$message = $oTaranisDossierContributor->{errmsg};
					}
				}
				
				$dossierUseractionText .= "\nTags: " . join(',', @tags);
				# add new tags and/or get the ID from existing tags
				TAG:
				foreach my $tag ( @tags ) {
					my $tagID;
					$tag = trim( $tag );
		
					if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $tag }, "tag", "IGNORE_CASE" ) ) {
						$oTaranisTagging->addTag( $tag );
						$tagID = $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
					} else {
						$tagID = $oTaranisTagging->getTagId( $tag );
						
						if ( $oTaranisTagging->{dbh}->checkIfExists( 
							{ tag_id => $tagID, item_table_name => 'dossier', item_id => $dossierID }, 
							"tag_item", 
							"IGNORE_CASE" 
						) ) {
							next TAG;
						}
					}
					
					if ( !$oTaranisTagging->setItemTag( $tagID, 'dossier', $dossierID ) ) {
						$message = $oTaranisTagging->{errmsg};
					}
				}
	
				if ( !$oTaranisTagging->removeItemTag( $dossierID, 'dossier', \@tags ) ) {
					$message = $oTaranisTagging->{errmsg};
				}
	
				$oTaranisTagging->cleanUp();
				
				my $userDescription = ( $user->{fullname} ) ? $user->{fullname} : $user->{username};
				my $noteText = "Dossier edited by $userDescription.\n$dossierUseractionText";
				my $noteID = $oTaranisDossierNote->addNote( text => $noteText );
				$oTaranisDossierItem->addDossierItem(
					dossier_id => $dossierID,
					note_id => $noteID,
					classification => 4
				);			
				
			} else {
				$message = $oTaranisDossier->{errmsg};
			}
			
			if ( $message ) {
				 $oTaranisTagging->{dbh}->rollbackTransaction();
				 setUserAction( action => 'edit dossier', comment => "Got error '$message' while trying to edit dossier '$kvArgs{description}'");
			} else {
				$oTaranisTagging->{dbh}->commitTransaction();
				$saveOk = 1;
				setUserAction( action => 'edit dossier', comment => "Edited dossier $dossierUseractionText");
			}
	
		} else {
			$message = "Can't use tags '@allreadyAssignedTags'. These tags are set for other dossiers.";
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $dossierID,
			insertNew => 0
		}
	};
}

sub getDossierItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
	
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $dossier = $oTaranisDossier->getDossiers( id => $id );
 
	if ( $dossier ) {
		$vars->{dossier} = $dossier->[0];

		$vars->{dossier}->{contributors} = $oTaranisDossierContributor->getContributors( dossier_id => $dossier->[0]->{id}, is_owner => 1 );

		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'dossier_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};	
}

sub openDialogDossierPublicationDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $writeRight = right('write');
	
	if ( $kvArgs{publicationid} =~ /^\d+$/ ) {
		my $oTaranisPublication = Publication;
		my $userId = sessionGet('userid');
		
		my $contentTypes = $oTaranisDossierItem->getContentTypes();
		my $contentTypeSettings = $contentTypes->{ $kvArgs{pubtype} };
		
		my $publication = $oTaranisPublication->getPublicationDetails( 
			table => $contentTypeSettings->{table},
			"$contentTypeSettings->{table}.publication_id" => $kvArgs{publicationid}
		);
		
		$vars->{created_by_name} = ( $publication->{created_by} ) ? $oTaranisUsers->getUser( $publication->{created_by}, 1 )->{fullname} : undef;
		$vars->{approved_by_name} = ( $publication->{approved_by} ) ? $oTaranisUsers->getUser( $publication->{approved_by}, 1 )->{fullname} : undef;
		$vars->{published_by_name} = ( $publication->{published_by} ) ? $oTaranisUsers->getUser( $publication->{published_by}, 1 )->{fullname} : undef; 

		$vars->{publication} = $publication;
		
		$tpl = 'dossier_publication_details.tt';
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

sub openDialogExportDossier {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $writeRight = right('write');
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $dossier = $oTaranisDossier->getDossiers( id => $kvArgs{id} );
		$vars->{dossier} = $dossier->[0];
		
		my @mailto_addressess = split( ";", Config->{maillist} ); 
			for ( my $i = 0; $i < @mailto_addressess; $i++ ) {
			$mailto_addressess[$i] = trim( $mailto_addressess[$i] );
		}

		$vars->{start_date} = $kvArgs{start_date};
		$vars->{end_date} = $kvArgs{end_date};
		$vars->{mailto} = \@mailto_addressess;
		
		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		$vars->{mailfrom_sender} = $user->{mailfrom_sender};
		$vars->{mailfrom_email}  = $user->{mailfrom_email};
		
		$tpl = 'dossier_export.tt';
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

sub dossierExport {
	my ( %kvArgs) = @_;
	my ( $vars, $message );

	my $oTaranisDossier = Taranis::Dossier->new( Config );
	my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
	my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
	my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $writeRight = right("write");

	my $dossier;

	if ( 
		$kvArgs{id} =~ /^\d+$/ 
		&& $kvArgs{include_comments} =~ /^(0|1)$/ 
		&& $kvArgs{export_format} =~ /^(txt|pdf)$/
		&& $kvArgs{export_content} =~ /^(all_content|titles_only)$/
		&& $kvArgs{export_to} =~ /^(download|email)$/
	) {
		my $dossierID  = $kvArgs{id};
		my $start_date = $kvArgs{start_date} =~ /^(\d\d)\-(\d\d)\-(\d\d\d\d)/ ? "$3$2$1" : '';
		my $end_date   = $kvArgs{end_date}   =~ /^(\d\d)\-(\d\d)\-(\d\d\d\d)/ ? "$3$2$1" : '';

		$vars->{start_date} = $kvArgs{start_date};
		$vars->{end_date}   = $kvArgs{end_date};

		$dossier = $oTaranisDossier->getDossiers( id => $dossierID )->[0];

		$vars->{dossier} = $dossier;
		$vars->{contributors} = $oTaranisDossierContributor->getContributors( dossier_id => $dossierID );

		my $tags = $oTaranisTagging->getTagsByItem( $dossierID, 'dossier' );
		$vars->{tags} = "@$tags";

		$oTaranisUsers->getUsersList();

		USER:
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			if ( $user->{username} eq $dossier->{reminder_account} ) {
				$vars->{reminder_user} = ( $user->{fullname} ) ? $user->{fullname} : $user->{username}; 
			}
			foreach my $contributor ( @{ $vars->{contributors} } ) {
				next USER if ( $contributor->{username} =~ /^$user->{username}$/ );
			}
		}
		
		my $contentTypes = $oTaranisDossierItem->getContentTypes();
		
		my $dossierItems = $oTaranisDossierItem->getDossierItemsFromDossier( $dossierID );

		# Remove items outside date range
		foreach my $dossierItemKey ( keys %$dossierItems ) {
			my $timestamp = $dossierItems->{$dossierItemKey}->{event_timestamp};
			my $date = $timestamp =~ m/^(\d\d\d\d)\-(\d\d)\-(\d\d)/ ? "$1$2$3" : '';
			delete $dossierItems->{$dossierItemKey}
				if +($start_date && $start_date gt $date)
				||  ($end_date   && $end_date   lt $date);
		}

		foreach my $dossierItemKey ( keys %$dossierItems ) {

			if ($kvArgs{include_comments}) {

				my $notes = $oTaranisDossierNote->getItemNotes( dossier_item_id => $dossierItems->{$dossierItemKey}->{dossier_item_id} );

				foreach my $note ( @$notes ) {
					$note->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $note->{id} );
					$note->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $note->{id} );
					$note->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $note->{id} );

					if ( $kvArgs{export_format} eq 'txt' ) {
						$note->{text} =~ s/\n/\n\t> /g;
						$note->{text} = decode_entities( $note->{text} );
						$note->{text} =~ s/<.*?>//g;
					}
				}
					
				$dossierItems->{$dossierItemKey}->{notes} = $notes;
			}

			if ($kvArgs{export_format} =~ /^txt$/) {
				$dossierItems->{$dossierItemKey}->{text} = decode_entities($dossierItems->{$dossierItemKey}->{text});
			}
		}
		
		$vars->{ticketURL} = Config->{rt_ticket_url};

		$vars->{dossierItems} = $dossierItems;
		$vars->{export_content} = $kvArgs{export_content};
		
		setUserAction( action => 'export dossier', comment => "Exported dossier '$dossier->{description}'." );
		
	} else {
		$vars->{error} = 'No permission';
	}
	
	my %mailSettings;
	if ( $kvArgs{export_to} =~ /^email/ ) {
		my $user = $oTaranisUsers->getUser( sessionGet('userid') );
		
		$mailSettings{mailfrom_sender} = $user->{mailfrom_sender};
		$mailSettings{mailfrom_email}  = $user->{mailfrom_email};
		$mailSettings{subject} = ( $kvArgs{subject} ) ? $kvArgs{subject} : '';
		$mailSettings{addresses} = [ flat $kvArgs{mailto} ];
	}
	
	if ( $kvArgs{export_format} eq 'txt' ) {
		
		my $dossierText = $oTaranisTemplate->processTemplate( 'dossier_export_txt.tt', $vars, 1 );
		
		if ( $kvArgs{export_to} eq 'download' ) {
			return dossierExportPerDownload( content => $dossierText, export_format => 'txt' );
		} else {
			return dossierExportPerEmail( content => $dossierText, export_format => 'txt', mailSettings => \%mailSettings );
		}
	} else {
		
		$vars->{absroot} = normalizePath('./webinterface/');
		my $html = $oTaranisTemplate->processTemplate( 'dossier_export_pdf.tt', $vars, 1 );

		my $phantom = Taranis::Screenshot::Phantomjs->new;
		my $dossierPDF = $phantom->createPDF(
			refhtml => \$html,
			pdfname => "dossier: $dossier->{description}",
		);

		if ( $kvArgs{export_to} eq 'download' ) {
			return dossierExportPerDownload( content => $dossierPDF, export_format => 'pdf' );
		} else {
			return dossierExportPerEmail( content => $dossierPDF, export_format => 'pdf', mailSettings => \%mailSettings );
		}
	}
}

sub dossierExportPerEmail {
	my ( %kvArgs) = @_;
	
	my $message;
	my $mailSettings = $kvArgs{mailSettings};
	
	my $subject = HTML::Entities::decode( $mailSettings->{subject} );
	$subject    =~ s/\s+/ /g;
	my $from    = HTML::Entities::decode( $mailSettings->{mailfrom_sender});

	my ($text, $pdf);
	if($kvArgs{export_format} eq 'pdf') {
		$text = 'Taranis Dossier export to PDF';
		$pdf  = Taranis::Mail->attachment(
			filename    => 'Taranis_dossier.pdf',
			mime_type   => 'application/pdf',
			data        => $kvArgs{content},
			description => 'pdfexport',
		);
	} else {
		$text = $kvArgs{content};
	}

	foreach my $address ( @{ $mailSettings->{addresses} } ) {

		my $msg = Taranis::Mail->build(
			From       => "$from <$mailSettings->{mailfrom_email}>",
			To         => $address,
			Subject    => $subject,
			plain_text => $text,
			attach     => $pdf,
		);
		$msg->send;

		$message .= "E-mail to $address sent!<br>";
	}

	my $dialogContent = '<div class="dialog-form-wrapper block">' . $message . '</div>';
	return { dialog => $dialogContent };
}

sub dossierExportPerDownload {
	my ( %kvArgs) = @_;

	if ( $kvArgs{export_format} =~ /^txt$/ ) {
		print CGI->header(
			-content_disposition => 'attachment; filename="Taranis_dossier.txt"',
			-type => 'text/plain',
		);

		# Replace \n with \r\n so Windows/Notepad can read the txt file
		$kvArgs{content} =~ s/\n/\r\n/g;

		print $kvArgs{content};
	} else {
		print CGI->header(
			-content_disposition => 'attachment; filename="Taranis_dossier.pdf"',
			-type => 'application/pdf',
		);
		print $kvArgs{content};
	}
	return {};
}

sub openDialogJoinDossiers {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if (ref $kvArgs{ids} eq 'ARRAY' && $writeRight ) {
		my @ids = $kvArgs{ids};   #XXX ref ref ids?
		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisTagging = Taranis::Tagging->new( Config );

		$vars->{dossiers} = $oTaranisDossier->getDossiers( id => \@ids );

		my %contributors;
		foreach my $dossier ( @{ $vars->{dossiers} } ) {
			my $dossierContributors = $oTaranisDossierContributor->getContributors( dossier_id => $dossier->{id} );
			
			foreach my $contributor ( @$dossierContributors ) {
				$contributors{ $contributor->{username} } = $contributor;
			}
		}

		@{ $vars->{contributors} } = values( %contributors );
		
		$oTaranisUsers->getUsersList();
	
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @{ $vars->{reminderAccounts} }, { username => $user->{username}, fullname => $user->{fullname} };
			if ( !exists( $contributors{ $user->{username} } ) ) {
				push @{ $vars->{users} }, { username => $user->{username}, fullname => $user->{fullname} };
			}
		}
		
		my $tagsPerDossier = $oTaranisTagging->getTagsByItemBulk( item_id => \@ids, item_table_name => 'dossier' );
		
		$vars->{tags} = [];
		foreach my $tags ( values %$tagsPerDossier ) {
			push @{ $vars->{tags} }, @$tags;
		}
		
		$tpl = 'dossier_join.tt';
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

sub joinDossiers {
	my ( %kvArgs) = @_;
	my ( $message, $newDossierID );
	
	my $saveOk = 0;
	my $dossierUseractionText = 'Dossiers: ';
	
	
	if ( 
		right("write")
		&& ref $kvArgs{ids} eq 'ARRAY'
		&& $kvArgs{tags}
		&& $kvArgs{contributors}
		&& $kvArgs{reminder_interval_amount} =~ /^\d+$/
		&& $kvArgs{reminder_interval_units} =~ /^(days|months)$/
		&& $kvArgs{reminder_account}
		&& $kvArgs{description}
	) {
		my $oTaranisDossier = Taranis::Dossier->new( Config );
		my $oTaranisDossierItem = Taranis::Dossier::Item->new( Config );
		my $oTaranisDossierNote = Taranis::Dossier::Note->new( Config );
		my $oTaranisDossierContributor = Taranis::Dossier::Contributor->new( Config );
		my $oTaranisTagging = Taranis::Tagging->new( Config );
		my $oTaranisUsers = Taranis::Users->new( Config );

		my $contentTypes = $oTaranisDossierItem->getContentTypes();
		my %dossierStatuses = reverse %{ $oTaranisDossier->getDossierStatuses() };
		
		my $title = ( trim( $kvArgs{description_alternative} ) ) ? trim( $kvArgs{description_alternative} ) : $kvArgs{description};
		$kvArgs{contributors} =~ s/&quot;/"/g;
		
		# get dossiers, dossier items and linked notes from selected dossiers
		my $joinedDossiers = $oTaranisDossier->getDossiers( id => $kvArgs{ids} );
		foreach my $joinedDossier ( @$joinedDossiers ) {
			$joinedDossier->{items} = [];
			my $dossierItems = $oTaranisDossierItem->getDossierItemsFromDossier( $joinedDossier->{id} );
			foreach my $dossierItemKey ( keys %$dossierItems ) {
				my $dossierItem = $dossierItems->{$dossierItemKey};
				
				my $notes = $oTaranisDossierNote->getItemNotes( dossier_item_id => $dossierItem->{dossier_item_id} );
				foreach my $note ( @$notes ) {
					$note->{urls} = $oTaranisDossierNote->getNoteUrls( note_id => $note->{id} );
					$note->{tickets} = $oTaranisDossierNote->getNoteTickets( note_id => $note->{id} );
					$note->{files} = $oTaranisDossierNote->getNoteFiles( note_id => $note->{id} );
				}
				$dossierItem->{notes} = $notes;
				push @{ $joinedDossier->{items} }, $dossierItem;
			}
			
			$dossierUseractionText .= "dossier $joinedDossier->{description}, ";
			
		}

		$dossierUseractionText =~ s/, $//;
		$dossierUseractionText .= " into dossier $title";
		
		my @notDossierID;
		push @notDossierID, -and => { '!=' => pop( @{ $kvArgs{ids} } ) };
		push @notDossierID, { '!=' => $_ } for @{ $kvArgs{ids} };

		$oTaranisDossier->{dbh}->startTransaction();

		$kvArgs{tags} =~ s/,\s*$//;
		my @tags = split( ',', $kvArgs{tags} );
		
		# add new tags and/or get the ID from existing tags
		my ( @tagIDs, @allreadyAssignedTags );
		foreach my $tag ( @tags ) {
			$tag = trim( $tag );

			if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $tag }, "tag", "IGNORE_CASE" ) ) {
				$oTaranisTagging->addTag( $tag );
				push @tagIDs, $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
			} else {
				my $tagID = $oTaranisTagging->getTagId( $tag );

				if ( $oTaranisTagging->{dbh}->checkIfExists({
						tag_id => $tagID,
						item_table_name => 'dossier',
						item_id => [ \@notDossierID ]
					},
					"tag_item"
				)) {
					push @allreadyAssignedTags, $tag;
				} else {
					push @tagIDs, $tagID;
				}
			}
		}

		if ( !@allreadyAssignedTags ) {
		
			my %newDossier = ( 
				description => $title,
				reminder_account => $kvArgs{reminder_account},
				reminder_interval => $kvArgs{reminder_interval_amount} . ' ' . $kvArgs{reminder_interval_units}
			);
			
			# add dossier
			if ( $newDossierID = $oTaranisDossier->addDossier( %newDossier ) ) {
				
				my $user = $oTaranisUsers->getUser( sessionGet('userid') );
				my $userDescription = ( $user->{fullname} ) ? $user->{fullname} : $user->{username};
				$dossierUseractionText .= " by $userDescription";
				
				my $newNoteID = $oTaranisDossierNote->addNote( text => $dossierUseractionText );
				$oTaranisDossierItem->addDossierItem(
					dossier_id => $newDossierID,
					note_id => $newNoteID,
					classification => 4
				);
				
				# add contributors to new dossier
				foreach my $contributor ( @{ from_json( $kvArgs{contributors} ) } ) {
					if ( !$oTaranisDossierContributor->addContributor(
						username => $contributor->{username},
						is_owner => $contributor->{is_owner},
						dossier_id => $newDossierID
					) ) {
						$message = $oTaranisDossierContributor->{errmsg};
					}
				}
				
				my %itemsHashList;
				foreach my $joinedDossier ( @$joinedDossiers ) {
					
					foreach my $dossierItem ( @{ $joinedDossier->{items} } ) {
						
						my $contentTypeSettings = $contentTypes->{ $dossierItem->{dossier_item_type} };
						my $itemHash = md5_base64( $dossierItem->{product_id} . $dossierItem->{dossier_item_type} );
						my $newDossierItemID;
						
						if ( exists( $itemsHashList{ $itemHash } ) ) {
							$newDossierItemID = $itemsHashList{ $itemHash }->{itemID};
							#TODO: doe iets met de classification van een dubbel item
						} else {
							if ( 
								$newDossierItemID = $oTaranisDossierItem->addDossierItem(
									dossier_id => $newDossierID,
									event_timestamp => $dossierItem->{event_timestamp},
									classification => $dossierItem->{classification},
									$contentTypeSettings->{dossier_item_column} => $dossierItem->{product_id}
							) ) {
								$itemsHashList{ $itemHash } = { itemID => $newDossierItemID, classification => $dossierItem->{classification} };
							} else {
								$message = $oTaranisDossierItem->{errmsg};
							}
						}

						foreach my $note ( @{ $dossierItem->{notes} } ) {
							
							delete $note->{id};
							$note->{dossier_item_id} = $newDossierItemID;

							my $urls = delete $note->{urls};
							my $tickets = delete $note->{tickets};
							my $files = delete $note->{files};

							if ( my $newDossierItemNoteID = $oTaranisDossierNote->addNote( %$note ) ) {
								
								foreach my $url ( @$urls ) {
									delete $url->{id};
									$url->{note_id} = $newDossierItemNoteID; 
									if ( !$oTaranisDossierNote->addNoteUrl( %$url ) ) {
										$message = $oTaranisDossierNote->{errmsg};
									}
								}
								foreach my $ticket ( @$tickets ) {
									delete $ticket->{id};
									$ticket->{note_id} = $newDossierItemNoteID; 
									if ( !$oTaranisDossierNote->addNoteTicket( %$ticket ) ) {
										$message = $oTaranisDossierNote->{errmsg};
									}
								}
								foreach my $file ( @$files ) {
									delete $file->{id};
									$file->{note_id} = $newDossierItemNoteID; 
									if ( !$oTaranisDossierNote->copyNoteFile( %$file ) ) {
										$message = $oTaranisDossierNote->{errmsg};
									}
								}
							}
						}
					}
					# remove tags from joined dossiers
					if ( !$oTaranisTagging->removeItemTag( $joinedDossier->{id}, 'dossier' ) ) {
						$message = $oTaranisTagging->{errmsg};
					}
			
					# set joined dossiers to 'JOINED' status
					if ( !$oTaranisDossier->setDossier( id => $joinedDossier->{id}, status => $dossierStatuses{JOINED} ) ) {
						$message = $oTaranisDossier->{errmsg};
					}
				}

				# link/create tags to dossier
				foreach my $tagID ( @tagIDs ) {
					if ( !$oTaranisTagging->setItemTag( $tagID, 'dossier', $newDossierID ) ) {
						$message = $oTaranisTagging->{errmsg};
					}
				}
			} else {
				$message = $oTaranisDossier->{errmsg};
			}
		} else {
			$message = "Can't use tags '@allreadyAssignedTags'. These tags are set for other dossiers.";
		}

		if ( $message ) {
			 $oTaranisDossier->{dbh}->rollbackTransaction();
			 setUserAction( action => 'joined dossier', comment => "Got error '$message' while trying to $dossierUseractionText");
		} else {
			$oTaranisDossier->{dbh}->commitTransaction();
			$saveOk = 1;
			setUserAction( action => 'add dossier', comment => "$dossierUseractionText");
		}
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message
		}
	};
}
