#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Category;
use Taranis::Constituent::Group;
use Taranis::Entitlement;
use Taranis::Publication;
use Taranis::Role;
use Taranis::Template;
use POSIX;

my @EXPORT_OK = qw( 
	displayRoles openDialogNewRole openDialogRoleDetails
	saveNewRole saveRoleDetails deleteRole searchRoles 
	getRoleItemHtml 
);

sub roles_export {
	return @EXPORT_OK;
}

sub displayRoles {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $ro = Taranis::Role->new( Config );
	my $en = Taranis::Entitlement->new( Config );
	
	my @entitlements;
	$en->getEntitlement();
	while ( $en->nextObject() ) {
	    push @entitlements, $en->getObject();
	}
	$vars->{entitlements} = \@entitlements;

    my @roles;
    $ro->getRole();
    while ( $ro->nextObject ) {
        push @roles, $ro->getObject();
    }

	$vars->{roles} = \@roles;
	
	$vars->{numberOfResults} = scalar @roles;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('roles.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('roles_filters.tt', $vars, 1);
	
	my @js = ('js/roles.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };		
}

sub openDialogNewRole {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$vars = getEntitlementSettings();
		$tpl = 'roles_details.tt';
		
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

sub openDialogRoleDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};

		my $ro = Taranis::Role->new( Config );
		my ( @roles, %roleRights, @roleRightsList );

		$ro->getRoleRightsFromRole( role_id => $id );
		while ( $ro->nextObject ) {
			my $roleRight = $ro->getObject();
			$roleRights{ $roleRight->{entitlement_id} } = $roleRight;
			push @roleRightsList, $roleRight;
		}

		$vars = getEntitlementSettings( roleRights => \@roleRightsList );		
		$vars->{role_rights} = \%roleRights;

		$vars->{write_right} = $writeRight;

		$ro->getRole( id => $id );
		while ( $ro->nextObject ) {
			$vars->{role} = $ro->getObject();
		}
		
		$tpl = 'roles_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};	
}

sub saveNewRole {
	my ( %kvArgs) = @_;
	my ( $message, $id, $roleName );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $ro = Taranis::Role->new( Config );
		$roleName = $kvArgs{name};
		my $roleDescription = $kvArgs{description};
		
		withTransaction {
			if ( $ro->addRole( name => $roleName, 'description' => $roleDescription ) ) {

				$id = $ro->{dbh}->getLastInsertedId('role');
				
				my $particularizationsJson = $kvArgs{particularizations};
				$particularizationsJson =~ s/&quot;/"/g;
				my $particularizations = from_json( $particularizationsJson );

				my %roleRights;

				foreach my $entitlementId ( @{ $kvArgs{entitlementId} } ) {
					
					$ro->addRoleRight( entitlement_id => $entitlementId, role_id => $id );
					
					$roleRights{$entitlementId} = undef;
					
					if (my $eids = exists $kvArgs{$entitlementId}) {
						my @eids = flat $eids;
						$kvArgs{$entitlementId} = \@eids;
						my %rights = map { $_ => 1 } @eids;
						$roleRights{$entitlementId}->{read_right} = ( exists( $rights{R} ) ) ? 1 : 0;
						$roleRights{$entitlementId}->{write_right} = ( exists( $rights{W} ) ) ? 1 : 0;
						$roleRights{$entitlementId}->{execute_right} = ( exists( $rights{X} ) ) ? 1 : 0; 
					} else {
						$roleRights{$entitlementId}->{read_right} = 0;
						$roleRights{$entitlementId}->{write_right} = 0;
						$roleRights{$entitlementId}->{execute_right} = 0;
					}
				}

				foreach my $entitlementId ( keys %$particularizations ) {
					$roleRights{$entitlementId}->{particularization} =
						join ',', @{$particularizations->{$entitlementId}};
				}

				for ( keys %roleRights ) {

					$roleRights{ $_ }->{role_id} = $id;
					my $particularization = $roleRights{ $_ }->{particularization};
					$particularization =~ s/,+$/,/g;

					my %update = (
						'entitlement_id'    => $_ ,
						'read_right'        => $roleRights{ $_ }->{read_right},
						'role_id'           => $roleRights{ $_ }->{role_id},
						'execute_right'     => $roleRights{ $_ }->{execute_right},
						'write_right'       => $roleRights{ $_ }->{write_right},
						'particularization' => $particularization
					);
			
					if ( !$ro->setRoleRight( %update ) ) {
						$message = 'user role DB error ' . $ro->{errmsg};
					}
				}

			} else {
				$message = $ro->{errmsg};
			}
		};
	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'add user role', comment => "Added role '$roleName'");
	} else {
		setUserAction( action => 'add user role', comment => "Got error '$message' while trying to add role '$roleName'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};	
}

sub saveRoleDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id, $roleName );
	my $saveOk = 0;
	
	my $cg = Taranis::Constituent::Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};

		my $ro = Taranis::Role->new( Config );
		$roleName = $kvArgs{name};
		my $roleDescription = $kvArgs{description};
		
		withTransaction {
			if ( $ro->setRole( id => $id, name => $roleName, 'description' => $roleDescription ) ) {

				my $particularizationsJson = $kvArgs{particularizations};
				$particularizationsJson =~ s/&quot;/"/g;
				my $particularizations = from_json( $particularizationsJson );

				my %roleRights;

				foreach my $entitlementId ( @{ $kvArgs{entitlementId} } ) {
					
					$roleRights{$entitlementId} = undef;
					
					if(my $eids = $kvArgs{$entitlementId}) {
						my @eids = flat $eids;
						$kvArgs{$entitlementId} = \@eids;
						my %rights = map { $_ => 1 } @eids;
						$roleRights{$entitlementId}->{read_right} = ( exists( $rights{R} ) ) ? 1 : 0;
						$roleRights{$entitlementId}->{write_right} = ( exists( $rights{W} ) ) ? 1 : 0;
						$roleRights{$entitlementId}->{execute_right} = ( exists( $rights{X} ) ) ? 1 : 0; 
					} else {
						$roleRights{$entitlementId}->{read_right} = 0;
						$roleRights{$entitlementId}->{write_right} = 0;
						$roleRights{$entitlementId}->{execute_right} = 0;
					}
				}

				foreach my $entitlementId ( keys %$particularizations ) {
					$roleRights{$entitlementId}->{particularization} =
						join ',', @{$particularizations->{$entitlementId}};
				}

				for ( keys %roleRights ) {

					$roleRights{ $_ }->{role_id} = $id;
					my $particularization = $roleRights{ $_ }->{particularization};
					$particularization =~ s/,+$/,/g;

					my %update = (
						'entitlement_id'    => $_ ,
						'read_right'        => $roleRights{ $_ }->{read_right},
						'role_id'           => $roleRights{ $_ }->{role_id},
						'execute_right'     => $roleRights{ $_ }->{execute_right},
						'write_right'       => $roleRights{ $_ }->{write_right},
						'particularization' => $particularization
					);

					if ( !$ro->setRoleRight( %update ) ) {
						$message = 'user role DB error ' . $ro->{errmsg};
					}
				}

			} else {
				$message = $ro->{errmsg};
			}
		};
		
		
	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit user role', comment => "Edited role '$roleName'");
	} else {
		setUserAction( action => 'edit user role', comment => "Got error '$message' while trying to edit role '$roleName'");
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
}

sub deleteRole {
	my ( %kvArgs) = @_;
	my ( $message, $role );
	my $deleteOk = 0;
	
	my $ro = Taranis::Role->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$ro->getRole( id => $kvArgs{id} );
		$role = $ro->{dbh}->fetchRow();

		withTransaction {
			if ( !$ro->deleteRole( id => $kvArgs{id} ) ) {
				$message = $ro->{errmsg};
			} else {
				$deleteOk = 1;
			}
		};
	} else {
		$message = 'No permission';
	}
	
	if ( $deleteOk ) {
		setUserAction( action => 'delete user role', comment => "Deleted role '$role->{name}'");
	} else {
		setUserAction( action => 'delete user role', comment => "Got error '$message' while trying to delete role '$role->{name}'");
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $kvArgs{id}
		}
	};	
}

sub searchRoles {
	my ( %kvArgs) = @_;
	my ( $vars, %search, @roles );

	
	my $tt = Taranis::Template->new;
	my $ro = Taranis::Role->new( Config );
	
	$search{name} = $kvArgs{search};
	$search{entitlement_id} = $kvArgs{entitlement};
	
	if ( $ro->getRolesWithEntitlement( %search ) ) {
		while ( $ro->nextObject ) {
			push @roles, $ro->getObject();
		}
	}
	
	$vars->{roles} = \@roles;
	$vars->{numberOfResults} = scalar @roles;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('roles.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

sub getRoleItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ro = Taranis::Role->new( Config );
	
	my $insertNew = $kvArgs{insertNew};
	
	my $id = $kvArgs{id};
	$ro->getRole( id => $id );
	my $role = $ro->{dbh}->fetchRow();
 
	if ( $role ) {
		$vars->{role} = $role;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'roles_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Error: Could not find the role...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};	
}

#TODO: translate to EN
#	analysis				: conf analyze_status_options
#	item_analysis			: not in use (set to disable)
#	items					: table category
#	membership				: NOT IN USE
#	publication				: publication.conf --> xxxxxx (email)
#	publication_template	: publication.conf all
#	soft_hard_usage			: NOT IN USE
#	sources_items			: table category
#	sources_stats			: table category

# NOTE:
#	membership	Rechten op de groepslidmaatschappen van
#				Constituent Individuals. Via een particularization
#				kunnen rechten op lidmaatschappen voor een
#				bepaalde Constituent Group worden gespecificeerd.

#	soft_hard_usage Rechten op het koppelen van hard- en software aan
#					Constituent Groups (‘onderhouden foto’). Via een
#					particularization kunnen rechten op het koppelen van
#					een hard- en software aan een specifieke Constituent
#					Group worden gespecificeerd.

#	item_analysis 	Rechten op de koppeling tussen een item en een
#					analyse. Via een particularization kunnen rechten op
#					het koppelen van items van een bepaalde categorie
#					worden gespecificeerd.
sub getEntitlementSettings {
	my ( %kvArgs) = @_;
	my ( @analysisStatusOptions, @publicationTypes, @assessCategoryNames, @entitlements );
	my $roleRights = $kvArgs{roleRights};	
	my $ro = Taranis::Role->new( Config );
	my $en = Taranis::Entitlement->new( Config );
	my $ca = Taranis::Category->new( Config );
	my $pu = Publication;
	
	my $vars;

	foreach my $status ( split( ",", Config->{analyze_status_options} ) ) {
		push @analysisStatusOptions, trim( lc( $status ) );
	}

	foreach my $assessCategory ( $ca->getCategory( 'is_enabled' => 1 ) ) {
		push @assessCategoryNames, lc( $assessCategory->{name} );
	}

	foreach my $type ( $pu->getDistinctPublicationTypes() ) {
		push @publicationTypes, lc( $type );
	}
		
	$vars->{sourceCategories} = \@assessCategoryNames;
	$vars->{publicationTypes} = \@publicationTypes;
	$vars->{analysisStatusOptions} = \@analysisStatusOptions;
		
	my %particularizations = ( 
		analysisStatusOptions => \@analysisStatusOptions,
		sourceCategories => \@assessCategoryNames,
		publicationTypes => \@publicationTypes
	);

	my %particularizationEntitlementSettings = ( 
		analysis => 'analysisStatusOptions',
	#	item_analysis => '',
		items => 'sourceCategories',
	#	membership => '',
		publication => 'publicationTypes',
		publication_template => 'publicationTypes',
	#	soft_hard_usage => ''
		sources_items => 'sourceCategories',
		sources_stats => 'sourceCategories'
	);

	$en->getEntitlement();
	while ( $en->nextObject() ) {
		my $record = $en->getObject();
		my %entitlement;
		
		$entitlement{id} = $record->{id};
		$entitlement{name} = $record->{name} ;
		$entitlement{description} = $record->{description};
		$entitlement{particularization} = $record->{particularization};
		
		if ( $record->{particularization} && $particularizationEntitlementSettings{ $entitlement{name} } ) {
			$entitlement{all_particularizations} = $particularizations{ $particularizationEntitlementSettings{ $entitlement{name} } };
			foreach my $roleRight ( @$roleRights ) {
				if ( $roleRight->{entitlement_id} == $record->{id} ) {
					foreach my $particularization ( split( ',', $roleRight->{particularization} ) ) {
						push @{ $entitlement{particularizations} }, trim( lc( $particularization ) );
					}
				}
			}
		}
		push @entitlements, \%entitlement;
	}

	$vars->{entitlements} = \@entitlements;
	
	return $vars;
	
} 
1;
