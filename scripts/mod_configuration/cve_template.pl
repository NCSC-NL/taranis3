#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Configuration::CVETemplate;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use strict;

my @EXPORT_OK = qw( 
	displayCVETemplates openDialogCVETemplateDetails saveCVETemplateDetails	getCVETemplateItemHtml
	openDialogNewCVETemplate saveNewCVETemplate deleteCVETemplate 
);

sub cve_template_export {
	return @EXPORT_OK;
}

sub	displayCVETemplates {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
	
	my $cveTemplates = $oTaranisConfigCVETemplate->getCVETemplates();
	$vars->{cveTemplates} = $cveTemplates;
	$vars->{numberOfResults} = scalar( @$cveTemplates );
	$vars->{write_right} = right("write");

	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('cve_template.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('cve_template_filters.tt', $vars, 1);
	
	my @js = ('js/cve_template.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewCVETemplate {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'cve_template_details.tt';
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

sub saveNewCVETemplate {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && trim( $kvArgs{description} ) ) {
		my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
		
		if ( !$oTaranisConfigCVETemplate->{dbh}->checkIfExists( { description => $kvArgs{description} }, "cve_template", "IGNORE_CASE" ) ) {
			if ( $id = $oTaranisConfigCVETemplate->addCVETemplate( description => $kvArgs{description}, template => $kvArgs{template} ) ) {
				setUserAction( action => 'add cve template', comment => "Added CVE template '$kvArgs{description}'");
			} else {
				$message = $oTaranisConfigCVETemplate->{errmsg};
				setUserAction( action => 'add cve template', comment => "Got error '$message' while trying to add CVE template '$kvArgs{description}'");
			}
		} else {
			$message = "A template with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
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

sub openDialogCVETemplateDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
		$id = $kvArgs{id};

		my $cveTemplate = $oTaranisConfigCVETemplate->getCVETemplates( id => $id );
		$vars->{cve_template} = ( $cveTemplate ) ? $cveTemplate->[0] : undef;

		$tpl = 'cve_template_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};	
}

sub saveCVETemplateDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ && trim( $kvArgs{description} ) ) {

		my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
		$id = $kvArgs{id};
		
		my %update = (
			id => $id,
			description => $kvArgs{description},
			template => $kvArgs{template}
		);
		
		if ( !$oTaranisConfigCVETemplate->setCVETemplate( %update ) ) {
			$message = $oTaranisConfigCVETemplate->{errmsg};
			setUserAction( action => 'edit cve template', comment => "Got error '$message' while trying to edit cve template '$kvArgs{description}'");
		} else {
			setUserAction( action => 'edit cve template', comment => "Edited cve template '$kvArgs{description}'");
		}

		$saveOk = 1 if ( !$message );
	} else {
		$message = 'No permission';
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

sub getCVETemplateItemHtml {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $cveTemplate = $oTaranisConfigCVETemplate->getCVETemplates( id => $id );
 
	if ( $cveTemplate ) {
		$vars->{cveTemplate} = $cveTemplate->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'cve_template_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}

sub deleteCVETemplate {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my $cveTemplates = $oTaranisConfigCVETemplate->getCVETemplates( id => $id );
		
		if ( $cveTemplates && ref( $cveTemplates ) =~ /^ARRAY$/ ) {
			my $templateDescription = $cveTemplates->[0]->{description};
	
			if ( !$oTaranisConfigCVETemplate->deleteCVETemplate( $kvArgs{id} ) ) {
				$message = $oTaranisConfigCVETemplate->{errmsg};
				setUserAction( action => 'delete cve template', comment => "Got error '$message' while deleting CVE template '$templateDescription'");
			} else {
				$deleteOk = 1;
				setUserAction( action => 'delete cve template', comment => "Deleted CVE template '$templateDescription'");
			}
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $id
		}
	};
}

1;
