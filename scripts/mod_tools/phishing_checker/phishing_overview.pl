#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use CGI::Simple;
use JSON;
use URI  ();

use Taranis qw(val_int nowstring trim);
use Taranis::Config;
use Taranis::Database;
use Taranis::Template;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(CGI Config Database);

my @EXPORT_OK = qw(
	displayPhishingOverview deletePhishingItem addPhishingItem loadImage
	openDialogPhishingDetails savePhishingDetails openDialogPhishingScreenshot
);

sub phishing_overview_export {
	return @EXPORT_OK;
}

sub _show_date($) {
	$_[0] =~ /^(....)(..)(..)(..)(..)(..)$/ ? "$3-$2-$1 $4:$5:$6" : $_[0];
}

sub displayPhishingOverview {
	my %kvArgs = @_;

	my $sites  = Database->simple->query('SELECT * FROM phish ORDER BY datetime_added');
	my @items;
	while(my $site = $sites->hash) {
		my $status = ($site->{hash} // '') eq '' ? 'uninitialized' : 'online';
		my $last   = $site->{datetime_added};

		my $prev_hash_change = $site->{datetime_hash_change} // '';
		if($prev_hash_change ne '' && $site->{counter_hash_change} >= 2) {
			$status = 'hashchange';
			$last   = $prev_hash_change;
		}

		my $prev_down = $site->{datetime_down} // '';
		if($prev_down ne '' && $site->{counter_down} >= 2) {
			$status = 'offline';
			$last   = $prev_down;
		}

		my %item    = %$site;
		$item{status}        = $status;
		$item{dt_laststatus} = _show_date $last;
		$item{dt_added}      = _show_date $site->{datetime_added};

		push @items, \%item;
	}

	my %vars = (
		phishingItems        => \@items,
		renderItemContainer  => 1,
		referenceIsMandatory => Config->isEnabled('phishreferencemandatory'),
	);

	my $tt = Taranis::Template->new;

	return {
		content => $tt->processTemplate('phishing_overview.tt', \%vars, 1),
		filters => $tt->processTemplate('phishing_filters.tt', \%vars, 1),
		js      => [ 'js/phishing.js', 'js/taranis.phishing.timer.js' ],
	};
}

sub openDialogPhishingDetails {
	my %kvArgs  = @_;
	my $phishId = val_int $kvArgs{id};

	my $db      = Database->simple;
	my (%vars, $tpl);

	if(my $site = $db->getRecord(phish => $phishId)) {
		%vars = %$site;
		$vars{referenceIsMandatory} = Config->isEnabled('phishreferencemandatory');
		$vars{site}   = URI->new($site->{url})->authority;
		$vars{images} = [ $db->query( <<'_GET_IMAGES', $phishId )->hashes ];
SELECT *, to_char(timestamp, 'DD-MM-YYYY HH24:MI') AS timestamp_string
  FROM phish_image
 WHERE phish_id = ?
 ORDER BY timestamp DESC
_GET_IMAGES

		$tpl = 'phishing_details.tt';

	} else {
		$vars{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	return {
		dialog => Taranis::Template->new->processTemplate($tpl, \%vars, 1),
		params => {
			id         => $phishId,
			writeRight => right("write"),
		}
	};
}

sub savePhishingDetails {
	my %kvArgs  = @_;
	my $phishId   = val_int $kvArgs{id};
	my $reference = trim $kvArgs{reference};
	my $campaign  = trim $kvArgs{campaign};

	my $db        = Database->simple;
	my $site      = $db->getRecord(phish => $phishId);
	my $message;

	my $refIsMandatory = Config->isEnabled('phishreferencemandatory');
	my $refPattern     = Config->{phishreferencepattern} || '.+';

	if($refIsMandatory && ( !$reference || $reference !~ /^$refPattern$/ )) {
		$message = "Invalid reference; should match '$refPattern'";

	} elsif ( ! right("write") ) {
		$message = 'No permission';
	} elsif ( ! $site) {
		$message = "Cannot find phishId $phishId";
	} else {
		$db->setRecord(phish => $phishId,
			{reference => $reference, campaign => $campaign} );

		setUserAction( action => 'edit phishing site',
			comment => "Edited phishing site '$site->{url}'");
	}

	return {
		params => {
			saveOk    => !$message,
			message   => $message,
			id        => $phishId,
			reference => $reference,
			campaign  => $campaign,
			insertNew => 0,
		}
	};
}

sub addPhishingItem {
	my %kvArgs = @_;
	my $reference = trim $kvArgs{reference};
	my $campaign  = trim $kvArgs{campaign};
	my $url       = trim $kvArgs{url};

	my ($message, $itemHtml);
	my $db     = Database->simple;
	my $config = Config;

	my $refIsMandatory = $config->isEnabled('phishreferencemandatory');
	my $refPattern     = $config->{phishreferencepattern} || '.+';

	if( ! $config->{phishfrom} || ! $config->{phishto}) {
		$message = "Please first configure 'phishfrom' and 'phishto'";
	}
	elsif($refIsMandatory && ( !$reference || $reference !~ /^$refPattern$/ ) ) {
		$message = "Invalid reference; should match '$refPattern'";

	} elsif($db->recordExists(phish => { url => $url })) {
		$message = "URL already exists!";

	} else {
		my $now     = nowstring(2);

		my $phishId = $db->addRecord(phish => {
			url       => $url,
			reference => $reference,
			campaign  => $campaign,
			datetime_added => $now,
			counter_down   => 0,
			counter_hash_change => 0,
		});

		my $added = _show_date $now;

		my %vars;
		$vars{renderItemContainer} = 1;
		$vars{phishingItem} = {
			id            => $phishId,
			url           => $url,
			reference     => $reference,
			campaign      => $campaign,
			dt_added      => $added,
			dt_laststatus => $added,
			status        => 'uninitialized',
		};

		$itemHtml = Taranis::Template->new->processTemplate('phishing_item.tt', \%vars, 1);

		setUserAction(action => 'add phishing site', comment => "Added phishing site '$url'");
	}

	return {
		params => {
			message  => $message,
			addOk    => !$message,
			itemHtml => $itemHtml,
		}
	};
}

sub deletePhishingItem {
	my %kvArgs  = @_;
	my $phishId = val_int $kvArgs{id};
	my $message;

	my $db      = Database->simple;
	my $site    = $db->getRecord(phish => $phishId);

	if(right("write") && $site) {
		my $guard = $db->beginWork;
		$db->deleteRecord(phish_image => $phishId, 'phish_id');
		$db->deleteRecord(phish => $phishId);
		$db->commit($guard);

		setUserAction( action => 'delete phishing site',
			comment => "Deleted phishing site '$site->{url}'");
	} else {
		$message = "No permission!";
	}

	return {
		params => {
			message  => $message,
			deleteOk => !$message,
			id       => $phishId,
		}
	};
}
 sub openDialogPhishingScreenshot {
	my %kvArgs = @_;
	my $phishId = val_int $kvArgs{phishid};
	my $imgId   = val_int $kvArgs{objectid};
	my (%vars, $tpl);

	if($phishId && $imgId) {
		my $details = Database->simple->query(<<'__SCREENSHOT', $imgId, $phishId)->hash;
SELECT *, to_char(timestamp, 'DD-MM-YYYY HH24:MI') AS timestamp_string
  FROM phish_image
 WHERE object_id = ? AND phish_id = ?
__SCREENSHOT

		$vars{screenshot_details} = to_json +{ tool => 'phishing_checker',
			object_id => $imgId, file_size => $details->{file_size} };
		$vars{timestamp_string} = $details->{timestamp_string};
		$tpl = 'phishing_screenshot.tt';

	} else {
		$vars{message} = "Does not compute...";
		$tpl = 'dialog_no_right.tt';
	}

	return {
		dialog => Taranis::Template->new->processTemplate($tpl, \%vars, 1),
	};
}

sub loadImage {
	my %kvArgs = @_;
	my $objectId = val_int $kvArgs{object_id};
	my $fileSize = val_int $kvArgs{file_size};

	print CGI->header(
		-type => 'image/png',
		-content_length => $fileSize,
	);

	binmode STDOUT;
	print Database->simple->getBlob($objectId, $fileSize);
}

1;
