#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use List::MoreUtils      qw(part);

use Taranis              qw(val_int val_string flat);
use Taranis::Constituent::Group;
use Taranis::Publicationtype;
use Taranis::Template;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::Config;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Config Database);

my @EXPORT_OK = qw(
	displayConstituentTypes openDialogNewConstituentType openDialogConstituentTypeDetails
	saveNewConstituentType saveConstituentTypeDetails deleteConstituentType getConstituentTypeItemHtml
);

sub constituent_types_export {
	return @EXPORT_OK;
}

sub displayConstituentTypes {
	my %kvArgs = @_;
	my $vars;

	my $cg = Taranis::Constituent::Group->new(Config);
	my $tt = Taranis::Template->new;

	my @constituentTypes = $cg->allConstituentTypes;
	foreach my $type (@constituentTypes) {
		if ( ! Database->checkIfExists( { constituent_type => $type->{id}, status => 0 }, "constituent_group") ) {
			$type->{status} = 1;
		} else {
			$type->{status} = 0;
		}
	}

	$vars->{constituentTypes} = \@constituentTypes;
	$vars->{numberOfResults}  = @constituentTypes;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $htmlContent = $tt->processTemplate('constituent_types.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_types_filters.tt', $vars, 1);

	my @js = ('js/constituent_types.js');

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}


sub deleteConstituentType {
	my %kvArgs = @_;
	my $type_id = val_int $kvArgs{id};

	my $message;
	if( right("write") && $type_id) {
		my $cg = Taranis::Constituent::Group->new(Config);
		my $constituentType = $cg->getConstituentTypeByID($type_id);
		$cg->deleteConstituentType($type_id);

		setUserAction( action => 'delete constituent type', comment => "Deleted constituent type '$constituentType->{type_description}'");
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			deleteOk => !$message,
			message  => $message,
			id       => $type_id,
		}
	};
}

sub openDialogNewConstituentType {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");

	if ( $writeRight ) {
		my $pt = Taranis::Publicationtype->new(Config);
		$vars->{allPublicationTypes} = [ $pt->allPublicationTypes ];
		$tpl = 'constituent_types_details.tt';

	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub saveNewConstituentType {
	my %kvArgs = @_;
	my $description = val_string $kvArgs{description};

	my ($message, $typeId);

	if(right("write")) {
		my $cg  = Taranis::Constituent::Group->new(Config);
		$typeId = $cg->addConstituentType(
			description => $description,
			pubtype_ids => [ flat $kvArgs{selected_types} ],
		);
		setUserAction( action => 'add constituent type', comment => "Added constituent type '$description'");
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk  => !$message,
			message => $message,
			id      => $typeId,
			insertNew => 1,
		}
	};
}

sub openDialogConstituentTypeDetails {
	my %kvArgs = @_;
	my $constituentTypeId = val_int $kvArgs{id};

	my ($vars, $tpl);
	my $writeRight = right("write");

	if($constituentTypeId) {
		my $cg = Taranis::Constituent::Group->new(Config);
		my $constituentType = $cg->getConstituentTypeByID($constituentTypeId);

		my $pt = Taranis::Publicationtype->new(Config);
		my @hasPubtypes = $pt->getPublicationTypesForCT($constituentTypeId);
		my @allPubtypes = $pt->allPublicationTypes;

		if(@hasPubtypes) {
			my %has = map +($_->{id} => 1), @hasPubtypes;
			my ($has, $missing) = part { $has{$_->{id}} ? 0 : 1 } @allPubtypes;
			$vars->{selectedPublicationTypes} = $has;
			$vars->{allPublicationTypes}      = $missing;
		} else {
			$vars->{allPublicationTypes}      = \@allPubtypes;
		}

		$vars->{type_description} = $constituentType->{type_description};
		$vars->{id} = $constituentTypeId;
		$tpl = 'constituent_types_details.tt';

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
			id => $constituentTypeId,
		}
	};
}

sub saveConstituentTypeDetails {
	my %kvArgs = @_;
	my $typeId = val_int $kvArgs{id};

	my $message;

	if(right("write") && $typeId) {
		my $cg   = Taranis::Constituent::Group->new(Config);
		my $orig = $cg->getConstituentTypeByID($typeId);

		$cg->updateConstituentType($typeId,
			pubtype_ids => [ flat $kvArgs{selected_types} ],
			description => val_string $kvArgs{description},
		);

		setUserAction( action => 'edit constituent type', comment => "Edited constituent type '$orig->{type_description}'");

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $typeId,
			insertNew => 0,
		}
	};
}

sub getConstituentTypeItemHtml {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $constituentTypeId = val_int $kvArgs{id};
	my $insertNew         = $kvArgs{insertNew};

	my $cg = Taranis::Constituent::Group->new(Config);
 	my $constituentType   = $cg->getConstituentTypeByID($constituentTypeId);

	if ( $constituentType ) {
		if ( !$insertNew && Database->checkIfExists( { constituent_type => $constituentTypeId, status => 0 }, "constituent_group") ) {
			$constituentType->{status} = 0;
		} else {
			$constituentType->{status} = 1;
		}

		$vars->{constituentType} = $constituentType;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		$tpl = 'constituent_types_item.tt';

	} else {
		$vars->{message} = 'Could not find the item...';
		$tpl = 'empty_row.tt';
	}

	my $tt = Taranis::Template->new;
	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $constituentTypeId,
		}
	};
}

1;
