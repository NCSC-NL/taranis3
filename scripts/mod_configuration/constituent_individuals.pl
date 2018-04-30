#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Constituent_Individual;
use Taranis::Constituent_Group;
use Taranis::Database qw(withTransaction);
use Taranis::Template;
use Taranis::Publicationtype;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw( 
	displayConstituentIndividuals openDialogNewConstituentIndividual openDialogConstituentIndividualDetails
	saveNewConstituentIndividual saveConstituentIndividualDetails deleteConstituentIndividual
	searchConstituentIndividuals getConstituentIndividualItemHtml checkPublicationTypes openDialogConstituentInidividualSummary
);

sub constituent_individuals_export {
	return @EXPORT_OK;
}

sub displayConstituentIndividuals {
	my ( %kvArgs) = @_;
	my ( $vars, @constituentIndividuals, @constituentGroups );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
	my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );
	
	$oTaranisConstituentGroup->loadCollection();
	while ( $oTaranisConstituentGroup->nextObject ) {
		push( @constituentGroups, $oTaranisConstituentGroup->getObject );
	}	
	$vars->{groups} = \@constituentGroups; 	
	
	$oTaranisConstituentIndividual->loadCollection();
	while ( $oTaranisConstituentIndividual->nextObject ) {
		push( @constituentIndividuals, $oTaranisConstituentIndividual->getObject );
	}

	for ( my $i = 0; $i < @constituentIndividuals; $i++ ) {

  		$constituentIndividuals[$i]->{groups} = "";
  		$constituentIndividuals[$i]->{groups_temp_disabled} = "";

		$oTaranisConstituentIndividual->getGroups( $constituentIndividuals[$i]->{id} );
		while ( $oTaranisConstituentIndividual->nextObject ) {
			my $group = $oTaranisConstituentIndividual->getObject();
		
			if ( $group->{status} == "0" ) {
				$constituentIndividuals[$i]->{groups} .= $group->{name}.", ";
			} else {
				$constituentIndividuals[$i]->{groups_temp_disabled} .= $group->{name}.", ";
			}
		}
		$constituentIndividuals[$i]->{groups} =~ s/,.$//;
		$constituentIndividuals[$i]->{groups_temp_disabled} =~ s/,.$//;
	}

	@{ $vars->{roles} } = $oTaranisConstituentIndividual->getRoleByID();

	$vars->{constituentIndividuals} = \@constituentIndividuals;
	
	$vars->{numberOfResults} = scalar @constituentIndividuals;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('constituent_individuals.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('constituent_individuals_filters.tt', $vars, 1);
	
	my @js = ('js/constituent_individuals.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewConstituentIndividual {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {
		my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );
		my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );

		my @constituentRoles = $oTaranisConstituentIndividual->getRoleByID();
		$vars->{roles} = \@constituentRoles;

		my @constituentGroups;
		$oTaranisConstituentGroup->loadCollection();
		while ( $oTaranisConstituentGroup->nextObject() ) {
			push( @constituentGroups, $oTaranisConstituentGroup->getObject() );
		}

		$vars->{all_groups} = \@constituentGroups;
		
		$tpl = 'constituent_individuals_details.tt';
		
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

sub openDialogConstituentIndividualDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $individualId );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );
		my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
		my $oTaranisPublicationType = Taranis::Publicationtype->new( Config );
		
		$individualId = $kvArgs{id};

		$oTaranisConstituentIndividual->loadCollection( "ci.id" => $individualId );
		my $individual = $oTaranisConstituentIndividual->{dbh}->fetchRow();

		my @constituentRoles = $oTaranisConstituentIndividual->getRoleByID();
		$vars->{roles} = \@constituentRoles;

		my @constituentGroups;
		$oTaranisConstituentGroup->loadCollection();
		while ( $oTaranisConstituentGroup->nextObject() ) {
			push( @constituentGroups, $oTaranisConstituentGroup->getObject() );
		}

		my @groupIDs = $oTaranisConstituentIndividual->getGroupIds( $individualId );
		
		if ( @groupIDs ) {
			tie my %groupsNonMemberHASH, "Tie::IxHash";
			foreach my $i ( @constituentGroups ) { $groupsNonMemberHASH{ $i->{id} } = $i }		
			
			my @memberships;
			foreach my $id ( @groupIDs ) {
				if ( exists( $groupsNonMemberHASH{$id} ) ) {
					delete $groupsNonMemberHASH{$id};
				}
				
				for (my $i = 0; $i < @constituentGroups; $i++ ) {
				 	push @memberships, $constituentGroups[$i] if ( $constituentGroups[$i]->{id} eq $id );
				}			
			}
			$vars->{membership_groups} = \@memberships;
			
			my @groupsNonMemberARRAY;
			foreach my $nonMember ( values %groupsNonMemberHASH ) {
				push( @groupsNonMemberARRAY, $nonMember );
			}
	
			$vars->{all_groups} = \@groupsNonMemberARRAY;
		} else {
			$vars->{all_groups} = \@constituentGroups;
		}
		
		my @constituentTypes;
		if ( $individualId )	{
			$oTaranisPublicationType->getPublicationTypes( "cg.status" => [0,2], "ci.id" =>  $individualId );		
			while ( $oTaranisPublicationType->nextObject() ) {
				push( @constituentTypes, $oTaranisPublicationType->getObject() );
			}
		}
	
		my @typeIDs = $oTaranisPublicationType->getPublicationTypeIds( $individualId );
	
		if ( @typeIDs ) {
			tie my %typesNonSelectedHASH, "Tie::IxHash";
			foreach my $i ( @constituentTypes ) { $typesNonSelectedHASH{ $i->{id} } = $i }		
			
			my @selectedConstituentTypes;			
			foreach my $id ( @typeIDs ) {
				if ( exists( $typesNonSelectedHASH{$id} ) ) {
					delete $typesNonSelectedHASH{$id};
				}
				
				for (my $i = 0; $i < @constituentTypes; $i++ ) {
					push @selectedConstituentTypes, $constituentTypes[$i] if ( $constituentTypes[$i]->{id} eq $id );
				}
			}
			$vars->{selected_types} = \@selectedConstituentTypes;
			
			my @typesNonSelectedARRAY;
			foreach my $nonSelected ( values %typesNonSelectedHASH ) {
				push( @typesNonSelectedARRAY, $nonSelected );
			}
	
			$vars->{all_types} = \@typesNonSelectedARRAY;
		} else {
			$vars->{all_types} = \@constituentTypes;
		}

		$vars->{constituentIndividual} = $individual;
		$vars->{write_right} = $writeRight;
        
		$tpl = 'constituent_individuals_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $individualId
		}  
	};
}

sub saveNewConstituentIndividual {
	my ( %kvArgs) = @_;
	my ( $message, $individualId );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
		if ( !$oTaranisConstituentIndividual->{dbh}->checkIfExists({ 
					firstname => $kvArgs{firstname}, 
					lastname => $kvArgs{lastname}, 
					role => $kvArgs{role}, 
					status => { "!=", 1 }
				}, 
				"constituent_individual", "IGNORE_CASE"	)	
			) {
			
			withTransaction {
				if ( !$oTaranisConstituentIndividual->addObject(
					table => "constituent_individual",
					firstname => $kvArgs{firstname},
					lastname => $kvArgs{lastname},
					emailaddress => $kvArgs{emailaddress},
					tel_mobile => $kvArgs{tel_mobile},
					tel_regular => $kvArgs{tel_regular},
					role => $kvArgs{role},
					call247 => $kvArgs{call247},
					call_hh=> $kvArgs{call_hh},
					status => $kvArgs{status}
					) 
				) {
					$message = $oTaranisConstituentIndividual->{errmsg};										
				}

				$individualId = $oTaranisConstituentIndividual->{dbh}->getLastInsertedId( "constituent_individual" );
				
				my @newGroups = ( ref( $kvArgs{membership_groups} ) =~ /^ARRAY$/ )
					? @{ $kvArgs{membership_groups} }
					: $kvArgs{membership_groups};
				
				if ( @newGroups ) {
					for ( my $i = 0 ; $i < @newGroups ; $i++ ) {
						$oTaranisConstituentIndividual->addObject( table => "membership", group_id => $newGroups[$i], constituent_id => $individualId ) if ( $newGroups[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );
					}
				}

				my @newTypes = ( ref( $kvArgs{selected_types} ) =~ /^ARRAY$/ )
					? @{ $kvArgs{selected_types} }
					: $kvArgs{selected_types};

				if ( @newTypes ) {
					for ( my $i = 0 ; $i < @newTypes ; $i++ ) {
						$oTaranisConstituentIndividual->addObject( table => "constituent_publication", type_id => $newTypes[$i],	constituent_id => $individualId	) if ( $newTypes[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );
					}
				}
			};
		} else {
			$message = "A person with the same name with the selected role already exists.";
		}	
	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'add constituent individual', comment => "Added constituent individual '$kvArgs{firstname} $kvArgs{lastname}'");
	} else {
		setUserAction( action => 'add constituent individual', comment => "Got error '$message' while trying to add constituent individual '$kvArgs{firstname} $kvArgs{lastname}'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $individualId,
			insertNew => 1
		}
	};
}
 
sub saveConstituentIndividualDetails {
	my ( %kvArgs) = @_;
	my ( $message, $individualId, $constituentIndividualOriginal );
	my $saveOk = 0;
	
	my $oTaranisConstituentGroup = Taranis::Constituent_Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
		my $oTaranisPublicationType = Taranis::Publicationtype->new( Config );
		
		$individualId = $kvArgs{id};
		
		my ( %newGroupIDsHASH,  @newGroups, %groupIDsHASH, @deleteGroups );

		## create an array and a hash containing the id's of current memberships stored in database
		my @groupIDs = $oTaranisConstituentIndividual->getGroupIds( $individualId );

		foreach my $id ( @groupIDs ) {
			$groupIDsHASH{$id} = $id;
		}

		## create a hash containing the id's of the groups visible in left column (which may or may not be stored in database)
		## also create an array of the id's of the new groups (memberships) that are not yet stored in database

		my @selectedGroups = ( ref( $kvArgs{membership_groups} ) =~ /^ARRAY$/ )
			? @{ $kvArgs{membership_groups} }
			: $kvArgs{membership_groups};

		foreach my $id ( @selectedGroups ) {
			$newGroupIDsHASH{$id} = $id;
			if ( !exists( $groupIDsHASH{$id} ) ) {
				push( @newGroups, $id );
			}
		}

		## create an array of id's of the groups who had this individual as member, but not anymore
		foreach my $id ( @groupIDs ) {
			if ( !exists( $newGroupIDsHASH{$id} ) ) { push( @deleteGroups, $id ) }
		}

		my ( %typeIDsHASH, %newTypeIDsHASH, @newTypes, @deleteTypes );
		my @typeIDs = $oTaranisPublicationType->getPublicationTypeIds( $individualId );
		
		foreach my $id ( @typeIDs ) {
			$typeIDsHASH{$id} = $id;
		}

		my @selectedTypes = ( ref( $kvArgs{selected_types} ) =~ /^ARRAY$/ )
			? @{ $kvArgs{selected_types} }
			: $kvArgs{selected_types};

		foreach my $id ( @selectedTypes ) {
			$newTypeIDsHASH{$id} = $id;
			if ( !exists( $typeIDsHASH{$id} ) ) {
				push( @newTypes, $id );
			}
		}
		
		foreach my $id ( @typeIDs ) {
			if ( !exists( $newTypeIDsHASH{$id} ) ) { push( @deleteTypes, $id ) }
		}
	
		my %constituentIndividualUpdate = (
			table => "constituent_individual",
			id => $kvArgs{id},
			firstname => $kvArgs{firstname},
			lastname => $kvArgs{lastname},
			tel_mobile => $kvArgs{tel_mobile},
			tel_regular => $kvArgs{tel_regular},
			emailaddress => $kvArgs{emailaddress},
			call247 => $kvArgs{call247},
			status => $kvArgs{status},
			role => $kvArgs{role},
			call_hh => $kvArgs{call_hh}
		);

		$oTaranisConstituentIndividual->loadCollection( "ci.id" => $individualId );
		$constituentIndividualOriginal = $oTaranisConstituentIndividual->{dbh}->fetchRow();
		
		my %checkData     = (
			firstname => $kvArgs{firstname},
			lastname  => $kvArgs{lastname},
			role      => $kvArgs{role},
			status    => { "!=", 1 }
		);

		if ( 
  			( 
				lc( $constituentIndividualOriginal->{firstname} ) eq lc( $kvArgs{firstname} )  
				&& lc( $constituentIndividualOriginal->{lastname} ) eq lc( $kvArgs{lastname} ) 
				&& $constituentIndividualOriginal->{role} eq $kvArgs{role} 
			)
			|| ( !$oTaranisConstituentIndividual->{dbh}->checkIfExists( { %checkData }, "constituent_individual", "IGNORE_CASE" ) )
		) {
			withTransaction {
				if ( !$oTaranisConstituentIndividual->setObject( %constituentIndividualUpdate ) ) {
					$message = $oTaranisConstituentIndividual->{errmsg};
				}

				if ( @newGroups ) {
					for ( my $i = 0 ; $i < @newGroups ; $i++ ) {
						$oTaranisConstituentIndividual->addObject( table => "membership", constituent_id => $individualId, group_id => $newGroups[$i] ) if ( $newGroups[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );					
					}
				}

				if ( @deleteGroups ) {
					for ( my $i = 0 ; $i < @deleteGroups ; $i++ ) {
						$oTaranisConstituentIndividual->deleteObject( table => "membership", constituent_id => $individualId, group_id => $deleteGroups[$i] ) if ( $deleteGroups[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );
					}
				}
				
				if ( @newTypes ) {
					for ( my $i = 0 ; $i < @newTypes ; $i++ ) {
						$oTaranisConstituentIndividual->addObject( table => "constituent_publication", constituent_id => $individualId, type_id => $newTypes[$i] ) if ( $newTypes[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );					
					}
				}

				if ( @deleteTypes ) {
					for ( my $i = 0 ; $i < @deleteTypes ; $i++ ) {
						$oTaranisConstituentIndividual->deleteObject( table => "constituent_publication",	constituent_id => $individualId,	type_id => $deleteTypes[$i] ) if ( $deleteTypes[$i] );
						$message = $oTaranisConstituentIndividual->{errmsg} if ( $message !~ /$oTaranisConstituentIndividual->{errmsg}/g && $oTaranisConstituentIndividual->{errmsg} ne "" );
					}
				}
			};
		} else {
			$message = "A person with the same name with the selected role already exists.";
		}

	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit constituent individual', comment => "Edited constituent individual '$constituentIndividualOriginal->{firstname} $constituentIndividualOriginal->{lastname}'");
	} else {
		setUserAction( action => 'edit constituent individual', comment => "Got error '$message' while trying to edit constituent individual '$constituentIndividualOriginal->{firstname} $constituentIndividualOriginal->{lastname}'");
	}
		
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $individualId,
			insertNew => 0
		}
	};
}
 
sub deleteConstituentIndividual {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$oTaranisConstituentIndividual->loadCollection( "ci.id" => $kvArgs{id} );
		my $individual = $oTaranisConstituentIndividual->{dbh}->fetchRow();
		
		withTransaction {
			if ( !$oTaranisConstituentIndividual->deleteIndividual( $kvArgs{id} ) ) {
				$message = $oTaranisConstituentIndividual->{errmsg};
				setUserAction( action => 'delete constituent individual', comment => "Got error '$message' while deleting constituent individual '$individual->{firstname} $individual->{lastname}'");
			} else {
				$deleteOk = 1;
				setUserAction( action => 'delete constituent individual', comment => "Deleted constituent individual '$individual->{firstname} $individual->{lastname}'");
			}
		};
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

sub searchConstituentIndividuals {
	my ( %kvArgs) = @_;
	my ( $vars, @individuals, %search );

	
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	
	$search{"ci.status"} = $kvArgs{status} if ( $kvArgs{status} =~ /^(0|2)$/ );
	$search{firstname} = $kvArgs{firstname} if ( $kvArgs{firstname} );
	$search{lastname} = $kvArgs{lastname} if ( $kvArgs{lastname} );
	$search{"cg.id"} = $kvArgs{group} if ( $kvArgs{group} =~ /^\d+$/);
	$search{role} = $kvArgs{role} if ( $kvArgs{role} =~ /^\d+$/ );

	$oTaranisConstituentIndividual->loadCollection( %search );
	while ( $oTaranisConstituentIndividual->nextObject ) {
		push( @individuals, $oTaranisConstituentIndividual->getObject );
	}

	for ( my $i = 0; $i < @individuals; $i++ ) {

		$individuals[$i]->{groups} = "";
		$individuals[$i]->{groups_temp_disabled} = "";

		$oTaranisConstituentIndividual->getGroups( $individuals[$i]->{id} );
		while ( $oTaranisConstituentIndividual->nextObject ) {
			my $group = $oTaranisConstituentIndividual->getObject();

			if ( $group->{status} == "0" ) {
				$individuals[$i]->{groups} .= $group->{name}.", ";
			} else {
				$individuals[$i]->{groups_temp_disabled} .= $group->{name}.", ";
			}
		}
		$individuals[$i]->{groups} =~ s/,.$//;
		$individuals[$i]->{groups_temp_disabled} =~ s/,.$//;
	}

	$vars->{constituentIndividuals} = \@individuals;
	$vars->{numberOfResults} = scalar @individuals;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('constituent_individuals.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub getConstituentIndividualItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
	
	my $individualId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	$oTaranisConstituentIndividual->loadCollection( "ci.id" => $individualId );
	my $constituentIndividual = $oTaranisConstituentIndividual->{dbh}->fetchRow();
 
	if ( $constituentIndividual ) {

		$constituentIndividual->{groups} = "";
		$constituentIndividual->{groups_temp_disabled} = "";
		
		$oTaranisConstituentIndividual->getGroups( $individualId );
		while ( $oTaranisConstituentIndividual->nextObject ) {
			my $group = $oTaranisConstituentIndividual->getObject();
		
			if ( $group->{status} == "0" ) {
				$constituentIndividual->{groups} .= $group->{name}.", ";
			} else {
				$constituentIndividual->{groups_temp_disabled} .= $group->{name}.", ";
			}
		}
		
		$constituentIndividual->{groups} =~ s/,.$//;
		$constituentIndividual->{groups_temp_disabled} =~ s/,.$//;

		$vars->{constituentIndividual} = $constituentIndividual;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'constituent_individuals_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Error: Could not find the new constituent individual...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $individualId
		}
	};	
}

sub checkPublicationTypes {
	my ( %kvArgs) = @_;
	my ( $message );

	my $oTaranisPublicationType = Taranis::Publicationtype->new( Config );

	my $jsonGroups = $kvArgs{groups};
	$jsonGroups =~ s/&quot;/"/g;

	my $groups = from_json( $jsonGroups );
	$oTaranisPublicationType->getPublicationTypes( "cg.id" => \@$groups, "cg.status" => [0,2] );

	my @publicationTypes;
	while ( $oTaranisPublicationType->nextObject() ) {
		my $publicationType = $oTaranisPublicationType->getObject();
		$publicationType->{id} = "$publicationType->{id}";
		push @publicationTypes, $publicationType;
	}

	return { params => { publicationTypes => \@publicationTypes } };
}

sub openDialogConstituentInidividualSummary {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $individualId );

	my $oTaranisTemplate = Taranis::Template->new;

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		my $oTaranisConstituentIndividual = Taranis::Constituent_Individual->new( Config );
		
		$individualId = $kvArgs{id};

		$oTaranisConstituentIndividual->loadCollection( "ci.id" => $individualId );
		my $individual = $oTaranisConstituentIndividual->{dbh}->fetchRow();
		
		$vars->{constituentIndividual} = $individual;
		$vars->{publicationTypes} = $oTaranisConstituentIndividual->getPublicationTypesForIndividual( $individualId );
		
		my @groups;
		$oTaranisConstituentIndividual->getGroups( $individualId );
		while ( $oTaranisConstituentIndividual->nextObject() ) {
			push @groups, $oTaranisConstituentIndividual->getObject();
		}

		$vars->{groups} = \@groups;
		
		$tpl = 'constituent_individuals_summary.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
	};

}

1;
