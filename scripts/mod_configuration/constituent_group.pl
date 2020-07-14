#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use Taranis qw(:all val_int val_string trim_text);
use Taranis::Constituent::Group;
use Taranis::Constituent::Individual;
use Taranis::Database qw(withTransaction);
use Taranis::Template;
use Taranis::ImportPhoto;
use Taranis::SoftwareHardware;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right sessionHasRight);
use Taranis::FunctionalWrapper qw(Config Database);

use List::MoreUtils  qw(part);

my @EXPORT_OK = qw(
	displayConstituentGroups openDialogNewConstituentGroup
	openDialogConstituentGroupDetails saveNewConstituentGroup
	saveConstituentGroupDetails deleteConstituentGroup
	searchConstituentGroups searchSoftwareHardwareConstituentGroup
	getConstituentGroupItemHtml checkMembership
	openDialogConstituentGroupSummary
);

sub constituent_group_export {
	return @EXPORT_OK;
}

sub displayConstituentGroups {
	my %kvArgs = @_;
	my $vars;

	my $cg = Taranis::Constituent::Group->new(Config);
	$vars->{constituentGroups} = [ $cg->searchGroups(inspect_photo => 1) ];
	$vars->{types}             = [ $cg->allConstituentTypes ];
	$vars->{write_right}       = right("write");
	$vars->{renderItemContainer} = 1;

	my $tt = Taranis::Template->new;
	my @js = ('js/constituent_group.js');
	my $htmlContent = $tt->processTemplate('constituent_group.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_group_filters.tt', $vars, 1);

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewConstituentGroup {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");

	if($writeRight) {
		my $cg = Taranis::Constituent::Group->new(Config);
		$vars->{types} = [ $cg->allConstituentTypes ];

		my $ci = Taranis::Constituent::Individual->new(Config);
		$vars->{all_individuals}     = [ $ci->searchIndividuals ];
		$vars->{hasImportPhotoRight} = sessionHasRight photo_import => 'x';
		$tpl = 'constituent_group_details.tt';

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

sub openDialogConstituentGroupDetails {
	my %kvArgs = @_;
	my $groupId = val_int $kvArgs{id};

	my ($vars, $tpl);

	my $writeRight = right("write");
	if($groupId) {
		my $cg = Taranis::Constituent::Group->new(Config);
		$vars->{constituentGroup} = $cg->getGroupById($groupId);
		$vars->{types} = [ $cg->allConstituentTypes ];
		$vars->{hasImportPhotoRight} = sessionHasRight photo_import => 'x';

		my $ci = Taranis::Constituent::Individual->new(Config);
		my @allIndividuals = $ci->searchIndividuals;

		if(my @hasMemberIds = $cg->getMemberIds($groupId)) {
			my %isMember = map +($_ => 1), @hasMemberIds;
			my ($members, $otherIndivuals) =
				part { $isMember{$_->{id}} ? 0 : 1 } @allIndividuals;

			$ci->mergeRoles($_) for @$members;
			$vars->{members}         = $members;
			$vars->{all_individuals} = $otherIndivuals;
		} else {
			$vars->{all_individuals} = \@allIndividuals;
		}

		if(my @swhwIds = $cg->getSoftwareHardwareIds($groupId)) {
			my $sh = Taranis::SoftwareHardware->new(Config);
			my @swhw = map $sh->getList(id => $_), @swhwIds;
			$vars->{sh_left_column} = \@swhw;
		}

		$vars->{write_right} = $writeRight;
		$tpl = 'constituent_group_details.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {
			writeRight => $writeRight,
			id => $groupId,
		}
	};
}

sub openDialogConstituentGroupSummary {
	my %kvArgs  = @_;
	my $groupId = val_int $kvArgs{id};

	my ($vars, $tpl);

	if($groupId) {
		my $cg = Taranis::Constituent::Group->new(Config);
		$vars->{group}      = my $group = $cg->getGroupById($groupId);
		delete $group->{notes}
			unless +($group->{notes} || '') =~ /\S/;

		my $gtype           = $cg->getConstituentTypeByID($group->{constituent_type});
		$vars->{group_type} = $gtype ? $gtype->{type_description} : 'NONE (error)';
		$vars->{members}    = [ $cg->getActiveMembers($groupId) ];
        $vars->{softwareHardware} = $cg->getSoftwareHardware($groupId);
		$tpl = 'constituent_group_members.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { dialog => $dialogContent };
}

sub saveNewConstituentGroup {
	my %kvArgs = @_;
	my $name = val_string $kvArgs{name};

	my ($message, $groupId);

	if( right("write") ) {
		my $has = Database->simple->getRecord(constituent_group => $name, 'name');
		if($has->{status}==1) {
			$message = "Group '$name' already exists (needs to be revived?)";
		} else {
			my $cg   = Taranis::Constituent::Group->new(Config);
			$groupId = $cg->addGroup(
				name    => $name,
				use_sh  => val_int $kvArgs{use_sh} || 0,
				call_hh => val_int $kvArgs{call_hh},
				any_hh  => val_int $kvArgs{any_hh},
				status  => val_int $kvArgs{status},
				notes   => $kvArgs{notes},
				constituent_type => $kvArgs{constituent_type},
				member_ids => [ flat $kvArgs{members} ],
				swhw_ids   => [ flat $kvArgs{sh_left_column} ],
			);
		}

		setUserAction( action => 'add constituent group',
			comment => "Added constituent group '$name'");

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $groupId,
			insertNew => 1,
		}
	};
}

sub saveConstituentGroupDetails {
	my %kvArgs = @_;
	my $groupId = val_int $kvArgs{id};

	my $message;

	if(right("write") && $groupId) {
		my $cg = Taranis::Constituent::Group->new(Config);
		my $group    = $cg->getGroupById($groupId);
		my $origName = $group->{name};
		my $name     = val_string $kvArgs{name};  # not for extern

		my $use_sh   = val_int $kvArgs{use_sh} || 0;
		my @swhw_ids = flat $kvArgs{sh_left_column};

		if($group->{external_ref}) {
			# There are very few things you can configure when the group
			# is maintained externally.
			$cg->updateGroup($groupId,
				use_sh   => $use_sh,
				swhw_ids => \@swhw_ids,
			);
		} elsif($name ne $origName
		   && Database->simple->getRecord(constituent_group => $name, 'name')) {
			$message .= "A group with the same name already exists.";
		} else {
			$cg->updateGroup($groupId,
				name     => $name,
				use_sh   => $use_sh,
				call_hh  => val_int $kvArgs{call_hh},
				any_hh   => val_int $kvArgs{any_hh},
				status   => val_int $kvArgs{status},
				notes    => trim_text $kvArgs{notes},
				constituent_type => $kvArgs{constituent_type},
				member_ids => [ flat $kvArgs{members} ],
				swhw_ids => \@swhw_ids,
			);

			setUserAction( action => 'edit constituent group',
				 comment => "Edited constituent group '$origName'");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $groupId,
			insertNew => 0,
		}
	};
}

sub deleteConstituentGroup {
	my %kvArgs = @_;
	my $groupId = val_int $kvArgs{id};
	my $message;

	if(right("write") && $groupId) {
		my $cg = Taranis::Constituent::Group->new(Config);
		my $group = $cg->getGroupById($groupId);

		$cg->deleteGroup($groupId);
		setUserAction( action => 'delete constituent group', comment => "Deleted constituent group '$group->{name}'");
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			deleteOk => !$message,
			message  => $message,
			id       => $groupId,
		}
	};
}

sub getConstituentGroupItemHtml {
	my %kvArgs = @_;
	my $groupId   = val_int $kvArgs{id};
	my $insertNew = val_int $kvArgs{insertNew};

	my ($vars, $tpl);
	my $cg = Taranis::Constituent::Group->new(Config);

	if(my $group = $cg->getGroupById($groupId)) {
		$cg->mergePhoto($group);
		$vars->{constituentGroup}    = $group;
		$vars->{write_right}         = right("write");
		$vars->{renderItemContainer} = $insertNew;
		$tpl = 'constituent_group_item.tt';

	} else {
		$vars->{message} = "Could not find group $groupId...";
		$tpl = 'empty_row.tt';
	}

	my $tt = Taranis::Template->new;
	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml  => $itemHtml,
			insertNew => $insertNew,
			id        => $groupId,
		}
	};
}

sub searchConstituentGroups {
	my %kvArgs = @_;
	my $vars;

	my $cg = Taranis::Constituent::Group->new(Config);
	my @groups = $cg->searchGroups(
		group_type_id => val_int $kvArgs{type},
		status        => val_int $kvArgs{status},
		name          => val_string $kvArgs{search},
		inspect_photo => 1,
	);

	$vars->{constituentGroups} = \@groups;
	$vars->{write_right}       = right("write");
	$vars->{renderItemContainer} = 1;

	my $tt = Taranis::Template->new;
	my $htmlContent = $tt->processTemplate('constituent_group.tt', $vars, 1);

	return { content => $htmlContent }
}

sub searchSoftwareHardwareConstituentGroup {
	my %kvArgs  = @_;
	my $search  = $kvArgs{search};
	my $groupId = val_int $kvArgs{id};

	my $sh = Taranis::SoftwareHardware->new(Config);
	$sh->searchSH( search => $search, not_type => [ 'w' ] );

	my @sh_data;
	while(my $record = $sh->nextObject) {
		$record->{version} ||= '';
		push @sh_data, $record;
	}

	return {
		params => {
			softwareHardware => \@sh_data,
			id => $groupId,
		}
	};
}

sub checkMembership {
	my %kvArgs   = @_;
	my $groupId  = val_int $kvArgs{id};

	my $jsonMembers = $kvArgs{members};
	$jsonMembers    =~ s/&quot;/"/g;
	my $members     = from_json $jsonMembers;

	my $ci      = Taranis::Constituent::Individual->new(Config);

	my %groupsPerMember;
	foreach my $member (@$members) {
		foreach my $group ($ci->getGroupsForIndividual($member)) {
			push @{$groupsPerMember{$member}}, $group->{name}
				if $group->{id} != $groupId;   #XXX ?
		}
	}

	return {
		params => {
			individual => \%groupsPerMember,
			id => $groupId,
		}
	}
}

1;
