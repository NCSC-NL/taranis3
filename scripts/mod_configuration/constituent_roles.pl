#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Constituent_Individual;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw( :all);
use Tie::IxHash;
use strict;

my @EXPORT_OK = qw( 
	displayConstituentRoles openDialogNewConstituentRole openDialogConstituentRoleDetails 
	saveNewConstituentRole saveConstituentRoleDetails deleteConstituentRole getConstituentRoleItemHtml
);

sub constituent_roles_export {
	return @EXPORT_OK;
}

sub displayConstituentRoles {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $ci = Taranis::Constituent_Individual->new( Config );
	my $tt = Taranis::Template->new;

	my @constituentRoles = $ci->getRoleByID();
	if ( $constituentRoles[0] ) {
		for (my $i = 0; $i < @constituentRoles; $i++ ) {
			if ( !$ci->{dbh}->checkIfExists( { role => $constituentRoles[$i]->{id}, status => { "!=" => 1 } }, "constituent_individual") ) {
				$constituentRoles[$i]->{status} = 1;
			} else {
				$constituentRoles[$i]->{status} = 0;
			}
		}
	} else {
		undef @constituentRoles;
	}
	
	$vars->{constituentRoles} = \@constituentRoles;
	$vars->{numberOfResults} = scalar @constituentRoles;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('constituent_roles.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_roles_filters.tt', $vars, 1);
	
	my @js = ('js/constituent_roles.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}


sub deleteConstituentRole {
	my ( %kvArgs) = @_;
	my ( $message, $roleId );
	my $deleteOk = 0;
	
	my $ci = Taranis::Constituent_Individual->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$roleId = $kvArgs{id};
		my $constituentRole = $ci->getRoleByID( $roleId );
		
		if ( !$ci->deleteRole( $kvArgs{id} ) ) {
			$message = $ci->{errmsg};
			setUserAction( action => 'delete constituent role', comment => "Got error '$message' while deleting constituent role '$constituentRole->{role_name}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete constituent role', comment => "Deleted constituent role '$constituentRole->{role_name}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $roleId
		}
	};
}

sub openDialogNewConstituentRole {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'constituent_roles_details.tt';
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

sub saveNewConstituentRole {
	my ( %kvArgs) = @_;
	my ( $message, $constituentRoleId );
	my $saveOk = 0;
	
	my $ci = Taranis::Constituent_Individual->new( Config );

	if ( right("write") ) {
		
		if ( !$ci->{dbh}->checkIfExists( {role_name => $kvArgs{role_name} }, "constituent_role", "IGNORE_CASE" ) ) {
			if ( $ci->addObject( table => "constituent_role", role_name => $kvArgs{role_name} ) ) {
				$constituentRoleId = $ci->{dbh}->getLastInsertedId(	"constituent_role" );
				setUserAction( action => 'add constituent role', comment => "Added constituent role '$kvArgs{role_name}'");
			} else {
				$message = $ci->{errmsg};
				setUserAction( action => 'add constituent role', comment => "Got error '$message' while trying to add constituent role '$kvArgs{role_name}'");
			} 
		} else {
			$message .= "A role description with this description already exists.";
		}		
		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $constituentRoleId,
			insertNew => 1
		}
	};
}

sub openDialogConstituentRoleDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $constituentRoleId );

	my $tt = Taranis::Template->new;
	my $ci = Taranis::Constituent_Individual->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$constituentRoleId = $kvArgs{id};
		my $constituentRole = $ci->getRoleByID( $constituentRoleId );
		
		$vars->{role_name} = $constituentRole->{role_name};
		$vars->{id} = $constituentRoleId;

		$tpl = 'constituent_roles_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $constituentRoleId
		}  
	};	
}

sub saveConstituentRoleDetails {
	my ( %kvArgs) = @_;
	my ( $message, $constituentRoleId );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$constituentRoleId = $kvArgs{id};
		my $ci = Taranis::Constituent_Individual->new( Config );

		my %constituentRoleUpdate = ( table => "constituent_role", id => $constituentRoleId, role_name => $kvArgs{role_name} );

		my $originaleConstituentRole = $ci->getRoleByID( $constituentRoleId );

		if ( 
			!$ci->{dbh}->checkIfExists( { role_name => $kvArgs{role_name} } , "constituent_role", "IGNORE_CASE" ) 
			|| lc( $kvArgs{role_name} ) eq lc( $originaleConstituentRole->{role_name} ) 
		) {		
			
			if ( $ci->setObject( %constituentRoleUpdate ) ) {
				setUserAction( action => 'edit constituent role', comment => "Edited constituent role '$originaleConstituentRole->{role_name}' to '$kvArgs{role_name}'");
			} else {
				$message = $ci->{errmsg};
				setUserAction( action => 'edit constituent role', comment => "Got error '$message' while trying to edit constituent role '$originaleConstituentRole->{role_name}' to '$kvArgs{role_name}'");
			}
		} else {
			$message = "A role description with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $constituentRoleId,
			insertNew => 0
		}
	};	
}

sub getConstituentRoleItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ci = Taranis::Constituent_Individual->new( Config );
	
	my $constituentRoleId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $constituentRole = $ci->getRoleByID( $constituentRoleId );
 
	if ( $constituentRole ) {

		if ( !$insertNew && $ci->{dbh}->checkIfExists( { role => $constituentRoleId, status => { "!=" => 1 } }, "constituent_individual") ) {
			$constituentRole->{status} = 0;
		} else {
			$constituentRole->{status} = 1;
		}

		$vars->{constituentRole} = $constituentRole;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'constituent_roles_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $constituentRoleId
		}
	};
}

1;
