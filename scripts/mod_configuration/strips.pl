#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Config::XMLGeneric ();
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis qw(:all);

use strict;

my @EXPORT_OK = qw(
	displayStrips openDialogNewStrips openDialogStripsDetails
	saveNewStrips saveStripsDetails deleteStrips
	searchStrips getStripsItemHtml
);

sub strips_export {
	return @EXPORT_OK;
}

sub _config() {
	my $fn = find_config(Config->{stripsconfig});
	Taranis::Config::XMLGeneric->new($fn, "hostname", "strips" );
}

sub displayStrips {
	my %kvArgs = @_;
	my $strips = _config->loadCollection || [];
	my @strips = sort { $a->{hostname} cmp $b->{hostname} } @$strips;

	my $vars;
	$vars->{stripsList} = \@strips;
	$vars->{numberOfResults} = scalar @strips;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $tt = Taranis::Template->new;
	my $htmlContent = $tt->processTemplate('strips.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('strips_filters.tt', $vars, 1);

	my @js = ('js/strips.js');
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewStrips {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");
	if($writeRight) {
		$tpl = 'strips_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;

	return {
		dialog => $tt->processTemplate($tpl, $vars, 1),
		params => { writeRight => $writeRight },
	};
}

sub openDialogStripsDetails {
	my %kvArgs = @_;
    my $id         = $kvArgs{id};
	my $writeRight = right("write");

	my ($vars, $tpl);
	if($id) {
		$vars->{strips}      = _config->getElement($id);
		$vars->{write_right} = $writeRight;
		$tpl = 'strips_details.tt';
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $tt = Taranis::Template->new;

	+{
		dialog => $tt->processTemplate($tpl, $vars, 1),
		params => {
			writeRight => $writeRight,
			id => $id,
		}
	};
}

sub saveNewStrips {
	my %kvArgs = @_;
	my $hostname = $kvArgs{hostname};

	my ($message, $id );
	if(right("write") && $hostname) {
		$id = sanitizeInput("xml_primary_key", $hostname);

		my $sp = _config;
		if($sp->checkIfExists($id)) {
			$message = "A strip with the same name already exists.";
		} elsif($sp->addElement(
				hostname => $id,
				strip0 => $kvArgs{strip0},
				strip1 => $kvArgs{strip1},
				strip2 => $kvArgs{strip2},
			)) {
				setUserAction( action => 'add strip', comment => "Added strip for '$hostname'");
		} else {
			$message = $sp->{errmsg};
			setUserAction( action => 'add strip', comment => "Got error '$message' while trying to add strip for '$hostname'");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk  => !$message,
			message => $message,
			id      => $id,
		}
	};
}

sub saveStripsDetails {
	my %kvArgs = @_;
	my $hostname = $kvArgs{hostname};
	my $oldhost  = $kvArgs{originalId};

	my ($message, $id, $originalId );

	if(right("write") && $hostname && $oldhost) {
		($id, $originalId) = sanitizeInput("xml_primary_key", $hostname, $oldhost);

		my $sp = _config;
		if(lc $id eq lc $originalId || !$sp->checkIfExists($id) ) {
			if($sp->setElement(
					hostname => $id,
					strip0 => $kvArgs{strip0},
					strip1 => $kvArgs{strip1},
					strip2 => $kvArgs{strip2},
					orig_hostname => $originalId,
				)) {
				setUserAction( action => 'edit strip', comment => "Edited strip for '$originalId'");
			} else {
				$message = $sp->{errmsg};
				setUserAction( action => 'edit strip', comment => "Got error '$message' while trying to edit strip for '$originalId'");
			}
		} else {
			$message = "A strip with the same name already exists.";
		}

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			saveOk  => !$message,
			message => $message,
			id      => $id,
			originalId => $originalId,
		}
	};
}

sub deleteStrips {
	my %kvArgs = @_;
	my ($message, $id);

	if(right("write") && $kvArgs{id}) {
		$id = sanitizeInput("xml_primary_key", $kvArgs{id} );

		my $sp = _config;
		if($sp->deleteElement($id)) {
			setUserAction( action => 'delete strip', comment => "Deleted strip for '$id'");
		} else {
			$message = $sp->{errmsg};
			setUserAction( action => 'delete strip', comment => "Got error '$message' while trying to delete strip for '$id'");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			deleteOk => !$message,
			message  => $message,
			id       => $id,
		}
	};
}

sub searchStrips {
	my %kvArgs = @_;

	my $unsortedStrips = _config->loadCollection( $kvArgs{search_hostname} ) || [];
	my @strips = sort { $a->{hostname} cmp $b->{hostname} } @$unsortedStrips;

	my $vars;
	$vars->{stripsList} = \@strips;
	$vars->{numberOfResults} = scalar @strips;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $tt = Taranis::Template->new;
	my $htmlContent = $tt->processTemplate('strips.tt', $vars, 1);

	return { content => $htmlContent };
}

sub getStripsItemHtml {
	my %kvArgs = @_;
	my $insertNew = $kvArgs{insertNew};
 	my ($id, $originalId) = sanitizeInput("xml_primary_key", $kvArgs{id}, $kvArgs{originalId} );

	my ($vars, $tpl);
	if(my $strips = _config->getElement($id)) {
		$vars->{strips} = $strips;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		$tpl = 'strips_item.tt';
	} else {
		$vars->{message} = 'Could not find the item...';
		$tpl = 'empty_row.tt';
	}

	my $tt = Taranis::Template->new;
	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml   => $itemHtml,
			insertNew  => $insertNew,
			id         => $id,
			originalId => $originalId,
		}
	};
}

1;
