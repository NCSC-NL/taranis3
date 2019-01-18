#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(rightOnParticularization);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Assess;
use JSON;
use strict;

my @EXPORT_OK = qw( openDialogAssessItemScreenshot );

sub assess_dialogs_export {
	return @EXPORT_OK; 
}

sub openDialogAssessItemScreenshot {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $as = Taranis::Assess->new( Config );
	my $tt = Taranis::Template->new;

	my $digest = $kvArgs{digest};

	my $item = $as->getItem( $digest );
	
	# if item is not found, try to find in the archive 
	if ( !$item ) {
		$item = $as->getItem( $digest, 1 );
	}
	
	if ( rightOnParticularization( $item->{category} ) ) {
		$vars->{item} = $item;
		$vars->{screenshot_details} = to_json( { object_id => $item->{screenshot_object_id}, file_size => $item->{screenshot_file_size} } );
		
		$tpl = "assess_screenshot_item.tt";
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = "No rights...";
	}

	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return { 
		dialog => $dialogContent 
	};
}

1;
