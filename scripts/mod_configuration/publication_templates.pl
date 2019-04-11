#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Publicationtype;
use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use strict;

my @EXPORT_OK = qw( 
	displayPublicationTemplates openDialogNewPublicationTemplate openDialogPublicationTemplateDetails
	saveNewPublicationTemplate savePublicationTemplateDetails deletePublicationTemplate
	searchPublicationTemplates getPublicationTemplateItemHtml	
);

sub publication_templates_export {
	return @EXPORT_OK;
}

sub displayPublicationTemplates {
	my ( %kvArgs) = @_;
	my ( $vars, @publicationTemplates );

	
	my $tt = Taranis::Template->new;
	
	my $emailPublicationTemplates = Taranis::Config::XMLGeneric->new( Config->{publication_templates}, "email", "templates" );
	my %nonUsableTemplates;
	foreach my $val ( values %{$emailPublicationTemplates->loadCollection()} ) {
		foreach ( %$val ) {
			$nonUsableTemplates{ lc $val->{$_} } = 1 if ( $val->{$_} );
		}
	}
	
	$tt->getTemplate();
	while ( $tt->nextObject ) {
		my $record = $tt->getObject();
		if ( exists( $nonUsableTemplates{ lc $record->{title} } ) ) {
			$record->{no_delete} = 1;
		} else {
			$record->{no_delete} = 0;
		}
		
		push( @publicationTemplates, $record );
	}
	
	$vars->{publicationTemplates} = \@publicationTemplates;
	$vars->{numberOfResults} = scalar @publicationTemplates;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('publication_templates.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('publication_templates_filters.tt', $vars, 1);
	
	my @js = ('js/publication_templates.js', 'js/validate_template.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewPublicationTemplate {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {
		my @publicationTypes;
		my $pt = Taranis::Publicationtype->new( Config );
	
		$pt->getPublicationTypes();
		while ( $pt->nextObject ) {
			push( @publicationTypes, $pt->getObject );
		}
		$vars->{publication_types} = \@publicationTypes;
		$vars->{publicationTemplate}->{tpl} = <<'__BLANK_TEMPLATE';
<publication>
<template>
</template>

<fields>
</fields>
</publication>
__BLANK_TEMPLATE
		
		$tpl = 'publication_templates_details.tt';
		
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};
}

sub openDialogPublicationTemplateDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $pt = Taranis::Publicationtype->new( Config );
		
		$tt->getTemplate( id => $id );
		$vars->{publicationTemplate} = $tt->{dbh}->fetchRow();
		
		my @publicationTypes;
		$pt->getPublicationTypes();
		while ( $pt->nextObject ) {
			push( @publicationTypes, $pt->getObject );
		}
		$vars->{write_right} = $writeRight;
		$vars->{publication_types} = \@publicationTypes;		
		$vars->{message} = $tt->{errmsg};

		$vars->{write_right} = $writeRight;
        
		$tpl = 'publication_templates_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};
	
}

sub	saveNewPublicationTemplate {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $tt = Taranis::Template->new;
		if ( !$tt->{dbh}->checkIfExists( { title => $kvArgs{title} }, "publication_template", "IGNORE_CASE" ) ) {

			$kvArgs{template} =~ s/(\r)//g;
			$kvArgs{description} =~ s/(\r)//g;

			if ( 
				$tt->addTemplate( 
					title=> $kvArgs{title}, 
					description => $kvArgs{description}, 
					template => $kvArgs{template}, 
					"type" => $kvArgs{type} 
				) 
			) {
				$id = $tt->{dbh}->getLastInsertedId('publication_template');
				setUserAction( action => 'add publication template', comment => "Added publication template '$kvArgs{title}'");
			} else {
				$message .= $tt->{errmsg};
				setUserAction( action => 'add publication template', comment => "Got error '$message' while trying to add publication template '$kvArgs{title}'");
			}
		} else {
			$message = "A template with the same title already exists.";
		}

	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};
}
 
sub savePublicationTemplateDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $tt = Taranis::Template->new;
		
		$tt->getTemplate( id => $id );
		my $originalTemplateTitle = $tt->{dbh}->fetchRow()->{title};
			
		if ( 
			( lc( $kvArgs{title} ) eq lc( $originalTemplateTitle ) )
			|| !$tt->{dbh}->checkIfExists( { title => $kvArgs{title} }, "publication_template", "IGNORE_CASE" ) 
		) {

			$kvArgs{template} =~ s/(\r)//g;
			$kvArgs{description} =~ s/(\r)//g;
								
			if ( 
				!$tt->setTemplate(
					id => $id, 
					template => $kvArgs{template}, 
					description => $kvArgs{description}, 
					type => $kvArgs{type},
					title => $kvArgs{title}				  
				)
			) {
				$message = $tt->{errmsg};
				setUserAction( action => 'edit publication template', comment => "Got error '$message' while trying to edit publication template '$originalTemplateTitle'");
			} else {
				setUserAction( action => 'edit publication template', comment => "Edited publication template '$originalTemplateTitle'");
			}
		} else {
			$message = "A template with the same title already exists.";
		}

	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
	
}

sub deletePublicationTemplate {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $tt = Taranis::Template->new;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};

		$tt->getTemplate( id => $id );
		my $publicationTemplate = $tt->{dbh}->fetchRow();

		if (  !$tt->deleteTemplate( $kvArgs{id} ) ) {
			$message = $tt->{errmsg};
			setUserAction( action => 'delete publication template', comment => "Got error '$message' while trying to delete publication template '$publicationTemplate->{title}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete publication template', comment => "Deleted publication template '$publicationTemplate->{title}'");
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

sub searchPublicationTemplates {
	my ( %kvArgs) = @_;
	my ( $vars, @publicationTemplates, %search );

	
	my $tt = Taranis::Template->new;

	my $publicationTypes = right("particularization");

	if ( $publicationTypes && scalar( @$publicationTypes ) > 0 ) {
		my @publicationTypeIDs = @{ $tt->getTypeIds( @$publicationTypes ) };
		$search{"type"} = \@publicationTypeIDs;
	}

	my $emailPublicationTemplates = Taranis::Config::XMLGeneric->new( Config->{publication_templates}, "email", "templates" );
	my %nonUsableTemplates;
	foreach my $val ( values %{$emailPublicationTemplates->loadCollection()} ) {
		foreach ( %$val ) {
			$nonUsableTemplates{ lc $val->{$_} } = 1 if ( $val->{$_} );
		}
	}
	
	$search{title} = $kvArgs{title};
	
	$tt->getTemplate( %search );
	while ( $tt->nextObject ) {
		my $record = $tt->getObject();
		if ( exists( $nonUsableTemplates{ lc $record->{title} } ) ) {
			$record->{no_delete} = 1;
		} else {
			$record->{no_delete} = 0;
		}
		
		push( @publicationTemplates, $record );
	}

	$vars->{publicationTemplates} = \@publicationTemplates;	
	$vars->{numberOfResults} = scalar @publicationTemplates;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('publication_templates.tt', $vars, 1);
	
	return { content => $htmlContent }	
}

sub getPublicationTemplateItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	$tt->getTemplate( id => $id );
	my $publicationTemplate = $tt->{dbh}->fetchRow();
 
	if ( $publicationTemplate ) {

		$vars->{publicationTemplate} = $publicationTemplate;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'publication_templates_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};	
}

1;	
