#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis::Configuration::CVE;
use Taranis::Configuration::CVEFile;
use Taranis::Configuration::CVETemplate;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use Taranis qw(flat);

my @EXPORT_OK = qw( displayCVEs openDialogCVEDetails saveCVEDetails getCVEItemHtml searchCVE openDialogCVEFiles saveCVEFiles applyCVETemplate );

sub cve_export {
	return @EXPORT_OK;
}

sub	displayCVEs {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConfigCVE = Taranis::Configuration::CVE->new( Config );
	
	my $cveList = $oTaranisConfigCVE->getCVE( limit => '100', offset => '0' );
	my $cveCount = $oTaranisConfigCVE->getCVECount();
	$vars->{cveList} = $cveList;
	$vars->{write_right} = right("write");
	$vars->{filterButton} = 'btn-cve-search';
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( 1, $cveCount, 100 );
	$vars->{renderItemContainer} = 1;
	
	$vars->{is_admin} = getUserRights(
			entitlement => "admin_generic", 
			username => sessionGet('userid')
		)->{admin_generic}->{write_right};

	my $htmlContent = $oTaranisTemplate->processTemplate('cve.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('cve_filters.tt', $vars, 1);
	
	my @js = ('js/cve.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogCVEDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $cveID );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^CVE-\d{4}-\d+$/ ) {
		
		my $oTaranisConfigCVE = Taranis::Configuration::CVE->new( Config );
		my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );
		$cveID = $kvArgs{id};

		my $cve = $oTaranisConfigCVE->getCVE( identifier => $cveID );
		$vars->{cve} = ( $cve ) ? $cve->[0] : undef;

		$vars->{cveTemplates} = $oTaranisConfigCVETemplate->getCVETemplates();

		$tpl = 'cve_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $cveID
		}  
	};	
}

sub saveCVEDetails {
	my ( %kvArgs) = @_;
	my ( $message, $cveID );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^CVE-\d{4}-\d+$/ ) {

		my $oTaranisConfigCVE = Taranis::Configuration::CVE->new( Config );
		$cveID = $kvArgs{id};

		if ( !$oTaranisConfigCVE->setCVE(	custom_description => $kvArgs{custom_description}, identifier => $cveID ) ) {
			$message = $oTaranisConfigCVE->{errmsg};
			setUserAction( action => 'edit cve description', comment => "Got error '$message' while trying to edit cve description for '$cveID'");
		} else {
			setUserAction( action => 'edit cve description', comment => "Edited cve description for '$cveID'");
		}

		$saveOk = 1 if ( !$message );
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $cveID,
			insertNew => 0
		}
	};	
}

sub getCVEItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConfigCVE = Taranis::Configuration::CVE->new( Config );
		
	my $cveID = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $cve = $oTaranisConfigCVE->getCVE( identifier => $cveID );
 
	if ( $cve ) {
		$vars->{cve} = $cve->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'cve_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $cveID
		}
	};
}

sub searchCVE {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisConfigCVE = Taranis::Configuration::CVE->new( Config );
	
	if ( exists( $kvArgs{search} ) && trim( $kvArgs{search} ) ) {
		$search{identifier} = { '-ilike' => '%' . trim( $kvArgs{search} ) . '%'	};
	}
	
	my $resultCount = $oTaranisConfigCVE->getCVECount( %search );

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	my $offset = ( $pageNumber - 1 ) * 100;
	$search{limit} = 100;
	$search{offset} = $offset;
	
	my $cveList = $oTaranisConfigCVE->getCVE( %search );
		
	$vars->{cveList} = $cveList;
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, $resultCount, 100 );
	$vars->{filterButton} = 'btn-cve-search';
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('cve.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub openDialogCVEFiles {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;

	my $isAdmin = getUserRights(
			entitlement => "admin_generic", 
			username => sessionGet('userid')
		)->{admin_generic}->{write_right};

	if ( $isAdmin ) {
		my $oTaranisConfigCVEFile = Taranis::Configuration::CVEFile->new( Config );

		$vars->{cveFiles} = $oTaranisConfigCVEFile->getCVEFile();
		$tpl = 'cve_files.tt';
		
	} else {
		$vars->{message} = 'No rights';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			isAdmin => $isAdmin
		}
	};
}

sub saveCVEFiles {
	my ( %kvArgs) = @_;
	my $message;
	my $saveOk = 0;

	my $isAdmin = getUserRights(
			entitlement => "admin_generic", 
			username => sessionGet('userid')
		)->{admin_generic}->{write_right};

	if ( $isAdmin ) {
		my $oTaranisConfigCVEFile = Taranis::Configuration::CVEFile->new( Config );
		
		my @submittedFiles = flat $kvArgs{file_url};
		my %submittedFilesMap = map { $_ => 1 } @submittedFiles;
		delete $submittedFilesMap{''};
		
		my $storedFiles = $oTaranisConfigCVEFile->getCVEFile();
		
		# delete CVE download configuration
		foreach my $storedFile ( @$storedFiles ) {
			if ( !exists( $submittedFilesMap{ $storedFile->{file_url} } ) ) {
				$oTaranisConfigCVEFile->deleteCVEFile( $storedFile->{file_url} );
			} else {
				delete $submittedFilesMap{ $storedFile->{file_url} };
			}
		}

		# add CVE download configuration
		foreach my $submittedUrl ( keys %submittedFilesMap ) {
			$submittedUrl =~ /^.*\/(.*?)$/;
			my $filename = $1; 
			
			if ( !$oTaranisConfigCVEFile->addCVEFile(
				file_url => $submittedUrl,
				filename => $filename,
			) ) {
				$message = $oTaranisConfigCVEFile->{errmsg};
			}
		}
		
		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No rights';
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk
		}
	}
}

sub applyCVETemplate {
	my ( %kvArgs) = @_;
	my $message;
	my $replacementText = '';
	
	if ( $kvArgs{template_id} =~ /^\d+$/ ) {
		my $oTaranisConfigCVETemplate = Taranis::Configuration::CVETemplate->new( Config );	
		my $cveTemplate = $oTaranisConfigCVETemplate->getCVETemplates( id => $kvArgs{template_id} );
		if(ref $cveTemplate eq 'ARRAY') {
			$replacementText = $kvArgs{original_text} . "\n" if ( $kvArgs{original_text} ); 
			$replacementText.= $cveTemplate->[0]->{template};
		}
	} else {
		$message = 'Invalid input.';
	}
	
	return {
		params => {
			cve_id => $kvArgs{cve_id},
			replacement_text => $replacementText,
			message => $message
		}
	}
}

1;
