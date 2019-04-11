#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Assess;
use Taranis::Configuration::CVE;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Publication;
use Taranis::SoftwareHardware;
use Taranis::SessionUtil qw(setUserAction);
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use strict;
use Encode;
use JSON;

my @EXPORT_OK = qw(
	searchSoftwareHardwareWrite getPublicationTemplate getTemplateText 
	getPulicationPreview savePublicationNotes getCVEText
);

sub common_actions_export {
	return @EXPORT_OK; 
}

sub searchSoftwareHardwareWrite {
	my ( %kvArgs ) = @_;
	
	
	my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
	
	my $search = $kvArgs{search};
	my $publicationType = $kvArgs{publicationtype};
	my $publicationId = $kvArgs{publicationid};
	
	my $searchType = $kvArgs{searchtype};

	if ( $searchType =~ /^platforms$/ ) {
		$oTaranisSoftwareHardware->searchSH( search => $search, types => [ 'o' ] );
	} else {
		$oTaranisSoftwareHardware->searchSH( search => $search, not_type => [ 'o' ] );
	}

	my @sh_data;
	while ( $oTaranisSoftwareHardware->nextObject() ) {
		my $record = $oTaranisSoftwareHardware->getObject();
		$record->{version} = '' if ( !$record->{version} );
		push( @sh_data, $record );
	}	
	
	return { 
		params => { 
			data => \@sh_data,
			pubType => $publicationType,
			searchType => $searchType,
			publicationId => $publicationId
		}
	};
}


sub getPublicationTemplate {
	my ( %kvArgs ) = @_;
	my $message;
	my $templateOk = 0;
	my $oTaranisTemplate = Taranis::Template->new;	

	my $templateId = $kvArgs{templateid};
	my $tab = $kvArgs{tab};
	my $publicationId = $kvArgs{publicationid};
	my $publicationType = $kvArgs{publicationType};
	
	$oTaranisTemplate->getTemplate( id => $templateId );
	my $template = $oTaranisTemplate->{dbh}->fetchRow()->{tpl};
	
	my $template_fields = $oTaranisTemplate->processPublicationTemplate( $template, $tab );
	
	if ( $oTaranisTemplate->{tpl_error} ) {
		$message = $oTaranisTemplate->{tpl_error};
	} else {
		$templateOk = 1;
	}
	
	return {
		params => { 
			template => $template_fields,
			tab => $tab,
			templateOk => $templateOk,
			publicationId => $publicationId,
			message => $message,
			publicationType => $publicationType
		}
	};
}

sub getCVEText {
	my ( %kvArgs ) = @_;
	my $message;
	my $templateOk = 0;


	my $json_str = $kvArgs{templateData};
	$json_str =~ s/&quot;/"/g;
	my $templateData = from_json( $json_str );
	
	my $tab = $kvArgs{tab};
	my $publicationId = $kvArgs{publicationid};
	my $oTaranisConfigurationCVE = Taranis::Configuration::CVE->new(  Config );
	my $cve = $oTaranisConfigurationCVE->getCVE( identifier => $templateData->{cveId} );
	my $cveText = ( $cve ) ? $cve->[0]->{custom_description} : undef;

	my $templateText = $templateData->{original_txt} . "\n- $templateData->{cveId}\n$cveText\n";
	
	return {
		params => { 
			templateText => $templateText,
			tab => $tab,
			templateOk => 1,
			publicationId => $publicationId,
			message => $message,
		}
	};
}

sub getTemplateText {
	my ( %kvArgs ) = @_;
	my $message;
	my $templateOk = 0;

	my $oTaranisTemplate = Taranis::Template->new;	
	
	my $tab = $kvArgs{tab};
	my $publicationId = $kvArgs{publicationid};
	
	my $json_str = $kvArgs{templateData};

	$json_str =~ s/&quot;/"/g;
	
	my $templateText = $oTaranisTemplate->processPublicationTemplateText( $json_str, $tab );

	if ( $oTaranisTemplate->{tpl_error} ) {
		$message = $oTaranisTemplate->{tpl_error};
	} else {
		$templateOk = 1;		
	}
	
	return {
		params => { 
			templateText => $templateText,
			tab => $tab,
			templateOk => $templateOk,
			publicationId => $publicationId,
			message => $message,
		}
	};
}

sub getPulicationPreview {
	my ( %kvArgs ) = @_;
	my ( $message, $previewText );
	my $previewOk = 0;

	my $oTaranisTemplate = Taranis::Template->new;	
	my $oTaranisPublication = Publication	
	my $tab = $kvArgs{tab};
  
	my $userid = sessionGet('userid');
	my $json = $kvArgs{publicationJson};

	$json =~ s/&quot;/"/g;

	my $formData = from_json( $json );

	my $publicationId = $kvArgs{publicationid};
	my $publication = $kvArgs{publication};
	my $publicationType = $kvArgs{publication_type};
	my $line_width = ( defined $kvArgs{line_width} ) ? $kvArgs{line_width} : 71;

	if ( $publicationType =~ /^xml$/i ) {
		$previewText = $oTaranisPublication->processPreviewXmlRT( $formData );
	} else {
		$previewText = $oTaranisTemplate->processPreviewTemplateRT( 
			publication => $publication,
			publication_type => $publicationType,
			formData => $formData,
			line_width => $line_width
		);
	}

	if ( $previewText ) { 
		$previewOk = 1;
	} else {
		$message = $oTaranisTemplate->{errmsg};
	}
	
	return {
		params => {
			message => $message,
			previewOk => $previewOk,
			publicationId => $publicationId,
			previewText => $previewText
		}
	};
}

sub savePublicationNotes {
	my ( %kvArgs ) = @_;

	my ( $message, $table );
	my $saveOk = 0;
	my $oTaranisPublication = Publication;
	my $publicationId = $kvArgs{publicationId};
	my $notes = $kvArgs{notes};
	
	for ( $kvArgs{publicationType} ) {
		if (/^advisory$/) { $table = 'publication_advisory'; }
		elsif (/^forward$/) { $table = 'publication_advisory_forward'; }
	}

	my $publication = $oTaranisPublication->getPublicationDetails( 
		table => $table,
		$table.'.publication_id' => $publicationId 
	);

	if ( $oTaranisPublication->setPublicationDetails( table => $table, where => { publication_id => $publicationId }, notes => $notes ) ) {
		$saveOk = 1;
		setUserAction( action => 'edit publication notes', comment => "Edited notes of publication '$publication->{title}'");
	} else {
		$message = $oTaranisPublication->{errmsg};
		setUserAction( action => 'edit publication notes', comment => "Got error '$message' while trying to edit notes of publication notes of publication '$publication->{title}'");
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};
}


1;
