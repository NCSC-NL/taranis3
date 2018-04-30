#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Constituent_Group;
use Taranis::Constituent_Individual;
use Taranis::Database qw(withTransaction);
use Taranis::Template;
use Taranis::ImportPhoto;
use Taranis::SoftwareHardware;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use Taranis qw(:all);
use Tie::IxHash;
use strict;

my @EXPORT_OK = qw( 
	displayConstituentGroups openDialogNewConstituentGroup openDialogConstituentGroupDetails
	saveNewConstituentGroup saveConstituentGroupDetails deleteConstituentGroup
	searchConstituentGroups searchSoftwareHardwareConstituentGroup getConstituentGroupItemHtml
	checkMembership openDialogConstituentGroupSummary
);

sub constituent_group_export {
	return @EXPORT_OK;
}

sub displayConstituentGroups {
	my ( %kvArgs) = @_;
	my ( $vars );

	
	my $cg = Taranis::Constituent_Group->new( Config );
	my $ip = Taranis::ImportPhoto->new( Config );
	my $tt = Taranis::Template->new;
	
	my @groups;
	$cg->loadCollection();
	while ( $cg->nextObject ) {
		push( @groups, $cg->getObject );
	}

	foreach my $group ( @groups ) {
		my $issues = $ip->getIssuesSimple( { 'ip.group_id' => $group->{id}, 'ii.status' => [ 0, 1 ] } );
		$group->{hasIssues} = ( scalar @$issues > 0 ) ? 1 : 0;
	}

	$vars->{constituentGroups} = \@groups;

	my @constituentTypes = $cg->getTypeByID();
	$vars->{types} = \@constituentTypes;
	
	$vars->{numberOfResults} = scalar @groups;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('constituent_group.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_group_filters.tt', $vars, 1);
	
	my @js = ('js/constituent_group.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewConstituentGroup {
	my ( %kvArgs) = @_;
	my ( $vars, @allConstituentIndividuals, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {
		my $cg = Taranis::Constituent_Group->new( Config );
		my $ci = Taranis::Constituent_Individual->new( Config );
		
		my @constituentTypes = $cg->getTypeByID();
		$vars->{types} = \@constituentTypes;
	
		$ci->loadCollection();
		while ( $ci->nextObject() ) {
			push( @allConstituentIndividuals, $ci->getObject() );
		}
		$vars->{all_individuals} = \@allConstituentIndividuals;
	
		$vars->{hasImportPhotoRight} = getUserRights( 
			entitlement => "photo_import", 
			username => sessionGet('userid') 
		)->{photo_import}->{execute_right};
		
		$tpl = 'constituent_group_details.tt';
		
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};
	
}

sub openDialogConstituentGroupDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $groupId );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		my $cg = Taranis::Constituent_Group->new( Config );
		my $ci = Taranis::Constituent_Individual->new( Config );
		my $ip = Taranis::ImportPhoto->new( Config );
		
		$groupId = $kvArgs{id};
		
		$cg->loadCollection( "cg.id" => $groupId );
        my $constituentGroup = $cg->{dbh}->fetchRow();

		$vars->{constituentGroup} = $constituentGroup;

		$vars->{hasImportPhotoRight} = getUserRights( 
			entitlement => "photo_import", 
			username => sessionGet('userid') 
		)->{photo_import}->{execute_right};
		
		if ( $vars->{hasImportPhotoRight} ) {
			$vars->{issueList} = $ip->getIssuesSimple( { 'group_id' => $groupId, 'ii.status' => [ 0, 1 ] }  );
		} 

		my @constituentTypes = $cg->getTypeByID();
		$vars->{types} = \@constituentTypes;
		
		my @allConstituentIndividuals;
		$ci->loadCollection();
		while ( $ci->nextObject() ) {
			push( @allConstituentIndividuals, $ci->getObject() );
		}

        my @memberIDs = $cg->getMemberIds( $groupId );

		if ( @memberIDs ) {
			tie my %individualsNonMemberHASH, "Tie::IxHash";
			
			foreach my $i ( @allConstituentIndividuals ) { $individualsNonMemberHASH{ $i->{id} } = $i }
			
			my @members;
			foreach my $id ( @memberIDs ) {
				if ( exists( $individualsNonMemberHASH{ $id } ) ) {
					delete $individualsNonMemberHASH{ $id };
				}
				$ci->loadCollection( "ci.id" => $id );
				if ( $ci->nextObject() ) {
					push( @members, $ci->getObject() );
				}
			}

			$vars->{members} = \@members;

			my @individualsNonMemberARRAY;
			foreach my $nonMember ( values %individualsNonMemberHASH ) {
				push( @individualsNonMemberARRAY, $nonMember );
			}

			$vars->{all_individuals} = \@individualsNonMemberARRAY;
		} else {
			$vars->{all_individuals} = \@allConstituentIndividuals;
		}

        my @softwareHardwareIDs = $cg->getSoftwareHardwareIds( $groupId );
		if ( @softwareHardwareIDs ) {
			my @softwareHardware;
			my $sh = Taranis::SoftwareHardware->new( Config );
			
			foreach my $id ( @softwareHardwareIDs ) {
				push( @softwareHardware, $sh->getList( id => $id ) );
			}
			$vars->{sh_left_column} = \@softwareHardware;
		}

		$vars->{write_right} = $writeRight;
        
		$tpl = 'constituent_group_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $groupId
		}  
	};
}

sub openDialogConstituentGroupSummary {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $groupId );

	my $tt = Taranis::Template->new;

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $cg = Taranis::Constituent_Group->new( Config );
		my $ci = Taranis::Constituent_Individual->new( Config );
		
		$groupId = $kvArgs{id};
		
		$vars->{group} = $cg->getGroupById( $groupId );

		my @members = $cg->getMembers( $groupId );

		if ( @members ) {
			for ( my $i = 0; $i < @members; $i++ ) {
				$members[$i]->{publication_types} = $ci->getPublicationTypesForIndividual( $members[$i]->{id} );
				$members[$i]->{role_description} = $ci->getRoleByID( $members[$i]->{role} )->{role_name};
			}
		}
	
		$vars->{members} = \@members;
        $vars->{softwareHardware} = $cg->getSoftwareHardware( $groupId );
		$tpl = 'constituent_group_members.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { dialog => $dialogContent };	
}

sub saveNewConstituentGroup {
	my ( %kvArgs) = @_;
	my ( $message, $groupId );
	my $saveOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") ) {
		if ( !$cg->{dbh}->checkIfExists( { name => $kvArgs{name}, status => { "!=", 1 } }, "constituent_group",	"IGNORE_CASE" ) ) {
			withTransaction {
				if ( !$cg->addObject(
					table => "constituent_group",
					name => $kvArgs{name},
					use_sh => $kvArgs{use_sh} || 0,
					call_hh => $kvArgs{call_hh},
					any_hh => $kvArgs{any_hh},
					status => $kvArgs{status},
					constituent_type => $kvArgs{constituent_type},
					notes => $kvArgs{notes} ) 
				) {
					$message = $cg->{errmsg};				            	
				}

				$groupId = $cg->{dbh}->getLastInsertedId( "constituent_group" );

				if ( $kvArgs{members} ) { 
					
					my @newMembers = ( ref( $kvArgs{members} ) =~ /^ARRAY$/ )
						? @{ $kvArgs{members} }
						: $kvArgs{members};

					for ( my $i = 0 ; $i < @newMembers ; $i++ ) {
						$cg->addObject(
							table => "membership",
							group_id => $groupId,
							constituent_id => $newMembers[$i]
						) if ( $newMembers[$i] );
						
						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}

				if ( $kvArgs{sh_left_column} ) { 
					my @newSoftwareHardware = ( ref( $kvArgs{sh_left_column} ) =~ /^ARRAY$/ )
						? @{ $kvArgs{sh_left_column} }
						: $kvArgs{sh_left_column};

					for ( my $i = 0 ; $i < @newSoftwareHardware ; $i++ ) {
						$cg->addObject(
							table => "soft_hard_usage",
							group_id => $groupId,
							soft_hard_id => $newSoftwareHardware[$i]
						) if ( $newSoftwareHardware[$i] );
						
						$message = $cg->{errmsg}
						if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}
			};
		} else {
			$message = "A group with the name '$kvArgs{name}' already exists.";
		}

	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'add constituent group', comment => "Added constituent group '$kvArgs{name}'");
	} else {
		setUserAction( action => 'add constituent group', comment => "Got error '$message' while trying to add constituent group '$kvArgs{name}'");
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $groupId,
			insertNew => 1
		}
	};
}

sub saveConstituentGroupDetails {
	my ( %kvArgs) = @_;
	my ( $message, $groupId, $originalGroupName );
	my $saveOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$groupId = $kvArgs{id};
		
		## create an array and a hash containing the id's of current members stored in the database
		my ( @deleteMembers, %memberIDsHASH, %newMemberIDsHASH, @newMembers );
		my @memberIDs = $cg->getMemberIds( $groupId );

		foreach my $id ( @memberIDs ) {
			$memberIDsHASH{$id} = $id;
		}

		## create a hash containing the id's of the members visible in left column (which may or may not be stored in database)
		## also create an array of the id's of the new members that are not yet stored in database
		my @selectedMembers = ( ref( $kvArgs{members} ) =~ /^ARRAY$/ )
			? @{ $kvArgs{members} }
			: $kvArgs{members};
		
		foreach my $id ( @selectedMembers ) {
			$newMemberIDsHASH{$id} = $id;
			if ( !exists( $memberIDsHASH{$id} ) ) {
				push( @newMembers, $id );
			}
		}

		## create an array of id's of individuals who were a member, but are not anymore
		foreach my $id ( @memberIDs ) {
			if ( !exists( $newMemberIDsHASH{$id} ) ) { push( @deleteMembers, $id ) }
		}

		my @softwareraHardwareIDs = $cg->getSoftwareHardwareIds( $groupId );
		my ( @deleteSoftwareHardware, %softwarerHardwareIDsHASH, %newSoftwareHardwareIDsHASH, @newSoftwareHardware );

		foreach my $id ( @softwareraHardwareIDs ) {
			$softwarerHardwareIDsHASH{$id} = $id;
		}
		
		my @selectedSoftwareHardware = ( ref( $kvArgs{sh_left_column} ) =~ /^ARRAY$/ )
			? @{ $kvArgs{sh_left_column} }
			: $kvArgs{sh_left_column};
	
		foreach my $id ( @selectedSoftwareHardware ) {
			$newSoftwareHardwareIDsHASH{$id} = $id;
			if ( !exists( $softwarerHardwareIDsHASH{$id} ) ) {
				push( @newSoftwareHardware, $id );
			}
		}

		foreach my $id ( @softwareraHardwareIDs ) {
			if ( !exists( $newSoftwareHardwareIDsHASH{$id} ) ) { push( @deleteSoftwareHardware, $id ) }
		}

		my %consituentGroupUpdate = (
			table => "constituent_group",
			id => $groupId,
			name => $kvArgs{name},
			use_sh => $kvArgs{use_sh} || 0,
			call_hh => $kvArgs{call_hh},
			any_hh => $kvArgs{any_hh},
			status => $kvArgs{status},
			constituent_type => $kvArgs{constituent_type},
			notes => $kvArgs{notes}
		);

		$cg->loadCollection( "cg.id" => $groupId );
		$originalGroupName = $cg->{dbh}->fetchRow()->{name};

		if (
			lc( $kvArgs{name} ) eq lc( $originalGroupName )
			|| ( !$cg->{dbh}->checkIfExists({ name => $kvArgs{name}, status => { "!=", 1 } }, "constituent_group", "IGNORE_CASE" ) )
		) {
			withTransaction {
				if ( !$cg->setObject( %consituentGroupUpdate ) ) {
					$message = $cg->{errmsg};	
				}

				if ( @newMembers && !$message ) {
					for ( my $i = 0 ; $i < @newMembers ; $i++ ) {
						$cg->addObject(
							table => "membership",
							group_id => $groupId,
							constituent_id => $newMembers[$i]
						) if ( $newMembers[$i] );

						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}

				if ( @deleteMembers && !$message ) {
					for ( my $i = 0 ; $i < @deleteMembers ; $i++ ) {
						if ( $deleteMembers[$i] ) {
							$cg->deleteObject(
								table => "membership",
								group_id => $groupId,
								constituent_id => $deleteMembers[$i]
							);
							$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );

							$cg->deleteConstituentPublication( individual_id => $deleteMembers[$i] );
							$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );		                    																	
						}
					}
				}

				if ( @newSoftwareHardware && !$message ) {
					for ( my $i = 0 ; $i < @newSoftwareHardware ; $i++ ) {
						$cg->addObject(
							table => "soft_hard_usage",
							group_id => $groupId,
							soft_hard_id => $newSoftwareHardware[$i]
						) if ( $newSoftwareHardware[$i] );

						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}

				if ( @deleteSoftwareHardware && !$message ) {
					for ( my $i = 0 ; $i < @deleteSoftwareHardware ; $i++ ) {
						$cg->deleteObject(
							table => "soft_hard_usage",
							group_id => $groupId,
							soft_hard_id => $deleteSoftwareHardware[$i]
						) if ( $deleteSoftwareHardware[$i] );

						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}

				$cg->deleteConstituentPublication();
			};
		} else {
			$message .= "A group with the same name already exists.";
		}
	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit constituent group', comment => "Edited constituent group '$originalGroupName'");
	} else {
		setUserAction( action => 'edit constituent group', comment => "Got error '$message' while trying to edit constituent group '$originalGroupName'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $groupId,
			insertNew => 0
		}
	};
}

sub deleteConstituentGroup {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$cg->loadCollection( "cg.id" => $kvArgs{id} );
		my $constituentGroup = $cg->{dbh}->fetchRow();

		if ( !$cg->deleteGroup( $kvArgs{id} ) ) {
			$message = $cg->{errmsg};
			setUserAction( action => 'delete constituent group', comment => "Got error '$message' while deleting constituent group '$constituentGroup->{name}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete constituent group', comment => "Deleted constituent group '$constituentGroup->{name}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $kvArgs{id}
		}
	};
}

sub getConstituentGroupItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $cg = Taranis::Constituent_Group->new( Config );
	
	my $groupId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	$cg->loadCollection( "cg.id" => $groupId );
	my $constituentGroup = $cg->{dbh}->fetchRow();
 
	if ( $constituentGroup ) {
		my $ip = Taranis::ImportPhoto->new( Config );
		my $issues = $ip->getIssuesSimple( { 'ip.group_id' => $groupId, 'ii.status' => [ 0, 1 ] } );
		$constituentGroup->{hasIssues} = ( scalar @$issues > 0 ) ? 1 : 0;

		$vars->{constituentGroup} = $constituentGroup;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'constituent_group_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $groupId
		}
	};	
}

sub searchConstituentGroups {
	my ( %kvArgs) = @_;
	my ( $vars, @groups, %search );

	
	my $cg = Taranis::Constituent_Group->new( Config );
	my $ip = Taranis::ImportPhoto->new( Config );
	my $tt = Taranis::Template->new;
	
	$search{name} = $kvArgs{search} if ( $kvArgs{search} );
	$search{'ct.id'} = $kvArgs{type} if ( $kvArgs{type} =~ /^\d+$/ );
	$search{status} = $kvArgs{status} if ( $kvArgs{status} =~ /^(0|2)$/ );
	
	$cg->loadCollection( %search );
	while ( $cg->nextObject ) {
		push( @groups, $cg->getObject );
	}

	foreach my $group ( @groups ) {
		my $issues = $ip->getIssuesSimple( { 'ip.group_id' => $group->{id}, 'ii.status' => [ 0, 1 ] } );
		$group->{hasIssues} = ( scalar @$issues > 0 ) ? 1 : 0;
	}

	$vars->{constituentGroups} = \@groups;
	
	$vars->{numberOfResults} = scalar @groups;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('constituent_group.tt', $vars, 1);
	
	return { content => $htmlContent }	
}

sub searchSoftwareHardwareConstituentGroup {
	my ( %kvArgs ) = @_;
	
	
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	my $search = $kvArgs{search};
	
	$sh->searchSH( search => $search, not_type => [ 'w' ] );

	my @sh_data;
	while ( $sh->nextObject() ) {
		my $record = $sh->getObject();
		$record->{version} = '' if ( !$record->{version} );
		push( @sh_data, $record );
	}	
	
	return { 
		params => { 
			softwareHardware => \@sh_data,
			id => $kvArgs{id}
		}
	};
}

sub checkMembership {
	my ( %kvArgs ) = @_;
	
	my $ci = Taranis::Constituent_Individual->new( Config );
			
	my $groupId = $kvArgs{id};
			
	my $jsonMembers = $kvArgs{members};
	$jsonMembers =~ s/&quot;/"/g;

	my $members = from_json( $jsonMembers );
			
	my @collection;
	my %groupsPerMember;
	foreach my $member ( @$members ) {
				
		$ci->getGroups( $member );
				
		GROUP:
		while ( $ci->nextObject() ) {
			my $group = $ci->getObject();
			next GROUP if ( $group->{id} == $groupId );
								
			push @{ $groupsPerMember{$member} }, $group->{name};
		}
	}

	return {
		params => { 
			individual => \%groupsPerMember,
			id => $groupId
		}
	}	
}
1;
