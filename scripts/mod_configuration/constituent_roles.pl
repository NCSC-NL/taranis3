#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use Taranis::Constituent::Individual;
use Taranis::Template;
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis qw( :all);

my @EXPORT_OK = qw(
	displayConstituentRoles openDialogNewConstituentRole openDialogConstituentRoleDetails
	saveNewConstituentRole saveConstituentRoleDetails deleteConstituentRole getConstituentRoleItemHtml
);

sub constituent_roles_export {
	return @EXPORT_OK;
}

sub displayConstituentRoles {
	my %kvArgs = @_;
	my $vars;

	my $ci = Taranis::Constituent::Individual->new(Config);
	my @allConstituentRoles = $ci->allConstituentRoles;
	foreach my $role (@allConstituentRoles) {
		if ( ! Database->checkIfExists( { role => $role->{id}, status => { "!=" => 1 } }, "constituent_individual") ) {
			$role->{status} = 1;   # in use
		} else {
			$role->{status} = 0;
		}
	}

	$vars->{constituentRoles}    = \@allConstituentRoles;
	$vars->{numberOfResults}     = @allConstituentRoles;
	$vars->{write_right}         = right("write");
	$vars->{renderItemContainer} = 1;

	my @js = ('js/constituent_roles.js');
	my $tt = Taranis::Template->new;
	my $htmlContent = $tt->processTemplate('constituent_roles.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_roles_filters.tt', $vars, 1);

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub deleteConstituentRole {
	my %kvArgs = @_;
	my $roleId = val_int $kvArgs{id};

	my $message;

	if ( right("write") && $roleId) {
		my $ci   = Taranis::Constituent::Individual->new(Config);
		my $name = $ci->getRoleName($roleId);

		if($ci->deleteRole($roleId)) {
			setUserAction( action => 'delete constituent individual role',
				comment => "Deleted constituent role '$name'");
		} else {
			$message = $ci->{errmsg};
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			deleteOk => !$message,
			message  => $message,
			id       => $roleId,
		}
	};
}

sub openDialogNewConstituentRole {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");

	if ( $writeRight ) {
		$tpl = 'constituent_roles_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight },
	};
}

sub saveNewConstituentRole {
	my %kvArgs = @_;
	my $roleName = val_string $kvArgs{role_name};

	my ($message, $roleId);

	if ( right("write") && $roleName) {
		my $db = Database->simple;
		if($db->recordExists(constituent_role => { role_name => $roleName })) {
			$message = "A role description with this description already exists.";
		} else {
			$roleId = $db->addRecord(constituent_role => { role_name => $roleName });
			setUserAction(action => 'add constituent role',
				comment => "Added constituent role '$roleName' ($roleId)");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $roleId,
			insertNew => 1,
		}
	};
}

sub openDialogConstituentRoleDetails {
	my %kvArgs = @_;
	my $roleId = val_int $kvArgs{id};

	my ($vars, $tpl);
	my $writeRight = right("write");

	if($roleId) {
		my $ci = Taranis::Constituent::Individual->new( Config );
		$vars->{role_name} = $ci->getRoleName($roleId);
		$vars->{id}        = $roleId;
		$tpl = 'constituent_roles_details.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return {
		dialog => $dialogContent,
		params => {
			writeRight => $writeRight,
			id => $roleId,
		}
	};
}

sub saveConstituentRoleDetails {
	my %kvArgs = @_;
	my $roleId   = val_int $kvArgs{id};
	my $roleName = val_string $kvArgs{role_name};

	my $message;

	if ( right("write") && $roleId) {
		my $ci = Taranis::Constituent::Individual->new(Config);
		my $origName = $ci->getRoleName($roleId);

		my $db = Database->simple;
		if($roleName eq $origName) {
			# not changed
		} elsif($db->recordExists(constituent_role => { role_name => $roleName })) {
			$message = "A role description with the same description already exists.";
		} else {
			$db->setRecord(constituent_role => $roleId, { role_name => $roleName });
			setUserAction( action => 'edit constituent role', comment => "Edited constituent role '$origName' to '$roleName'");
		}

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $roleId,
			insertNew => 0,
		}
	};
}

sub getConstituentRoleItemHtml {
	my %kvArgs = @_;
	my $roleId    = val_int $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	my ($vars, $tpl);
	my $ci = Taranis::Constituent::Individual->new( Config );

	if(my $role = $ci->getRoleByID($roleId)) {

		if ( !$insertNew && Database->checkIfExists( { role => $roleId, status => { "!=" => 1 } }, "constituent_individual") ) {
			$role->{status} = 0;
		} else {
			$role->{status} = 1;
		}

		$vars->{constituentRole}     = $role;
		$vars->{renderItemContainer} = $insertNew;
		$vars->{write_right}         = right("write");
		$tpl = 'constituent_roles_item.tt';

	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $tt = Taranis::Template->new;
	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $roleId,
		}
	};
}

1;
