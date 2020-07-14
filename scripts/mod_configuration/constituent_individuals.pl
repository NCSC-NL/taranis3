#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use List::MoreUtils   qw(part);

use Taranis::Constituent::Individual;
use Taranis::Constituent::Group;
use Taranis::Database qw(withTransaction);
use Taranis::Template;
use Taranis::Publicationtype;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw(:all);

my @EXPORT_OK = qw(
	displayConstituentIndividuals openDialogNewConstituentIndividual openDialogConstituentIndividualDetails
	saveNewConstituentIndividual saveConstituentIndividualDetails deleteConstituentIndividual
	searchConstituentIndividuals getConstituentIndividualItemHtml checkPublicationTypes openDialogConstituentIndividualSummary
);

sub constituent_individuals_export {
	return @EXPORT_OK;
}

sub displayConstituentIndividuals {
	my %kvArgs = @_;
	my $vars;

	my $cg = Taranis::Constituent::Group->new(Config);
	$vars->{groups} = [ $cg->searchGroups ];

	my $ci = Taranis::Constituent::Individual->new(Config);
	my @individuals = $ci->searchIndividuals(
		include_roles  => 1,
		include_groups => 1,
	);

	$vars->{individuals} = \@individuals;
	$vars->{roles}       = [ $ci->allConstituentRoles ];
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my @js = ('js/constituent_individuals.js');
	my $tt = Taranis::Template->new;
	my $htmlContent = $tt->processTemplate('constituent_individuals.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_individuals_filters.tt', $vars, 1);

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewConstituentIndividual {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");
	if($writeRight) {
		my $ci = Taranis::Constituent::Individual->new(Config);
		$vars->{all_roles}  = [ $ci->allConstituentRoles ];

		my $cg = Taranis::Constituent::Group->new(Config);
		$vars->{all_groups} = [ $cg->searchGroups ];
		$tpl = 'constituent_individuals_details.tt';

	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight },
	};
}

sub openDialogConstituentIndividualDetails {
	my %kvArgs = @_;
	my $indivId    = val_int $kvArgs{id};

	my ($vars, $tpl);
	my $writeRight = 0;

	if ($indivId) {
		my $ci = Taranis::Constituent::Individual->new(Config);
		$vars->{individual} = my $individual = $ci->getIndividualById($indivId);

		my $cg = Taranis::Constituent::Group->new(Config);
		my @allGroups  = $cg->searchGroups;

		if(my @hasGroupIDs = $ci->getGroupIDs($individual)) {
			my %has = map +($_ => 1), @hasGroupIDs;
			my ($member, $other) = part { exists $has{$_->{id}} ? 0 : 1 } @allGroups;

			$vars->{membership_groups} = $member;
			$vars->{all_groups} = $other;
		} else {
			$vars->{all_groups} = \@allGroups;
		}

		my $pt = Taranis::Publicationtype->new(Config);
		my @mayHaveTypes = $pt->getPublicationTypesIndividual($indivId);

		if(my @hasTypeIDs = $pt->getPublicationTypeIds($indivId)) {
			my %has = map +($_ => 1), @hasTypeIDs;
			my ($selected, $other) = part { exists $has{$_->{id}} ? 0 : 1 }
				@mayHaveTypes;

			$vars->{selected_types} = $selected;
			$vars->{all_types}      = $other;
		} else {
			$vars->{all_types}      = \@mayHaveTypes;
		}

		my %hasRoleIds = map +($_->{id} => $_), $ci->getRolesForIndividual($indivId);
		$vars->{selected_roles}     = \%hasRoleIds;
		$vars->{all_roles}          = [ $ci->allConstituentRoles ];

		$writeRight    = $individual->{external_ref} ? 0 : right("write");
		$vars->{write_right} = $writeRight;

		$tpl = 'constituent_individuals_details.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {
			writeRight => $writeRight,
			id => $indivId,
		}
	};
}

sub saveNewConstituentIndividual {
	my %kvArgs    = @_;
	my $firstname = val_string $kvArgs{firstname};
	my $lastname  = val_string $kvArgs{lastname};

	my ($message, $indivId);
	if(right("write") && $firstname && $lastname) {
		my $ci = Taranis::Constituent::Individual->new(Config);
		$indivId = $ci->addIndividual(
			firstname    => $firstname,
			lastname     => $lastname,
			emailaddress => val_string $kvArgs{emailaddress},
			tel_mobile   => val_string $kvArgs{tel_mobile},
			tel_regular  => val_string $kvArgs{tel_regular},
			call247      => val_int $kvArgs{call247},
			call_hh      => val_int $kvArgs{call_hh},
			status       => val_int  $kvArgs{status},
			group_ids       => [ flat $kvArgs{membership_groups} ],
			publication_ids => [ flat $kvArgs{selected_types} ],
			role_ids        => [ flat $kvArgs{individual_roles} ],
		);

		setUserAction( action => 'add constituent individual',
			comment => "Added constituent individual '$firstname $lastname'");
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $indivId,
			insertNew => 1,
		}
	};
}

sub saveConstituentIndividualDetails {
	my %kvArgs   = @_;
	my $indivId  = val_int $kvArgs{id};

	my $message;
	if(right("write") && $indivId) {
		my $ci   = Taranis::Constituent::Individual->new(Config);
		my $orig = $ci->getIndividualById($indivId);
		my $origName = "$orig->{firstname} $orig->{lastname}";

		$ci->updateIndividual($indivId,
			firstname    => val_string $kvArgs{firstname},
			lastname     => val_string $kvArgs{lastname},
			tel_mobile   => val_string $kvArgs{tel_mobile},
			tel_regular  => val_string $kvArgs{tel_regular},
			emailaddress => val_string $kvArgs{emailaddress},
			call247      => val_int $kvArgs{call247},
			call_hh      => val_int $kvArgs{call_hh},
			status       => val_int $kvArgs{status},
			role_ids        => [ flat $kvArgs{individual_roles} ],
			group_ids       => [ flat $kvArgs{membership_groups} ],
			publication_ids => [ flat $kvArgs{selected_types} ],
		);

		setUserAction(action => 'edit constituent individual',
			 comment => "Edited constituent individual '$origName'");
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $indivId,
			insertNew => 0,
		}
	};
}

sub deleteConstituentIndividual {
	my %kvArgs  = @_;
	my $indivId = val_int $kvArgs{id};

	my $message;
	my $ci = Taranis::Constituent::Individual->new(Config);
	my $individual = $indivId ? $ci->getIndividualById($indivId) : undef;

	if(! $individual) {
		$message = "Cannot find individual $indivId";
	} elsif(! right("write")) {
		$message = 'No permission';
	} elsif($individual->{external_ref}) {
		$message = 'Individual controled by external source';
	} else {
		$ci->deleteIndividual($indivId);
	}

	return {
		params => {
			deleteOk => ! $message,
			message  => $message,
			id       => $indivId,
		}
	};
}

sub searchConstituentIndividuals {
	my %kvArgs = @_;
	my $vars;

	my $ci = Taranis::Constituent::Individual->new(Config);
	my @individuals = $ci->searchIndividuals(
		status    => val_int    $kvArgs{status},
		firstname => val_string $kvArgs{firstname},
		lastname  => val_string $kvArgs{lastname},
		group_id  => val_int    $kvArgs{group},
		role_id   => val_int    $kvArgs{role},

		include_groups => 1,
		include_roles  => 1,
	);

	$vars->{individuals} = \@individuals;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $oTaranisTemplate = Taranis::Template->new;
	my $htmlContent = $oTaranisTemplate->processTemplate('constituent_individuals.tt', $vars, 1);

	return { content => $htmlContent };
}

sub getConstituentIndividualItemHtml {
	my %kvArgs = @_;
	my $indivId    = val_int $kvArgs{id};
	my $insertNew  = val_int $kvArgs{insertNew};

	my ($vars, $tpl);
	my $ci = Taranis::Constituent::Individual->new(Config);

	if(my $individual = $ci->getIndividualById($indivId)) {
		$ci->mergeGroups($individual)->mergeRoles($individual);
		$vars->{individual}  = $individual;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer}   = $insertNew;

		$tpl = 'constituent_individuals_item.tt';
	} else {
		$vars->{message} = 'Error: Could not find the new constituent individual...';
		$tpl = 'empty_row.tt';
	}

	my $oTaranisTemplate = Taranis::Template->new;
	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml  => $itemHtml,
			insertNew => $insertNew,
			id        => $indivId,
		}
	};
}

sub checkPublicationTypes {
	my %kvArgs = @_;
	my $message;

	my $jsonGroups = $kvArgs{groups};
	$jsonGroups =~ s/&quot;/"/g;
	my $groups = from_json $jsonGroups;

	my $pt = Taranis::Publicationtype->new(Config);
	my @publicationTypes = $pt->getPublicationTypesGroups(@$groups);
	$_->{id} .= "" for @publicationTypes;   # Javascript is typed :(

	return { params => { publicationTypes => \@publicationTypes } };
}

sub openDialogConstituentIndividualSummary {
	my %kvArgs  = @_;
	my $indivId = val_int $kvArgs{id};

	my ($vars, $tpl);

	if($indivId) {
		my $ci = Taranis::Constituent::Individual->new(Config);
		my $individual = $ci->getIndividualById($indivId);
		$ci	->mergeGroups($individual)
			->mergeRoles($individual)
			->mergePublicationTypes($individual);

		$vars->{individual} = $individual;
		$tpl = 'constituent_individuals_summary.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
	};
}

1;
