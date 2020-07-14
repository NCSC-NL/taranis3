#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use Taranis qw(val_int val_string);
use Taranis::Template;
use Taranis::Publicationtype;
use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);

my @EXPORT_OK = qw(
	displayPublicationTemplates openDialogNewPublicationTemplate openDialogPublicationTemplateDetails
	saveNewPublicationTemplate savePublicationTemplateDetails deletePublicationTemplate
	searchPublicationTemplates getPublicationTemplateItemHtml
);

sub publication_templates_export {
	return @EXPORT_OK;
}

sub displayPublicationTemplates {
	my %kvArgs = @_;

	my $emailPublicationTemplates = Taranis::Config::XMLGeneric->new( Config->{publication_templates}, "email", "templates" );
	my %nonUsableTemplates;
	foreach my $val ( values %{$emailPublicationTemplates->loadCollection} ) {
		foreach ( %$val ) {    #XXX keys and values?
			$nonUsableTemplates{ lc $val->{$_} } = 1 if ( $val->{$_} );
		}
	}

	my @publicationTemplates;

	my $tt = Taranis::Template->new;
	$tt->getTemplate();
	while(my $record = $tt->nextObject) {
		$record->{no_delete} = $nonUsableTemplates{lc $record->{title}} || 0;
		push @publicationTemplates, $record;
	}

	my $vars;
	$vars->{publicationTemplates} = \@publicationTemplates;
	$vars->{numberOfResults      } = @publicationTemplates;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $htmlContent = $tt->processTemplate('publication_templates.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('publication_templates_filters.tt', $vars, 1);
	my @js = ('js/publication_templates.js', 'js/validate_template.js');

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewPublicationTemplate {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $writeRight = right("write");

	if ( $writeRight ) {
		my $pt = Taranis::Publicationtype->new(Config);
		$vars->{publication_types} = [ $pt->allPublicationTypes ];

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

	my $tt = Taranis::Template->new;
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub openDialogPublicationTemplateDetails {
	my %kvArgs   = @_;
	my $templId = val_int $kvArgs{id};

	my ($vars, $tpl);
	my $writeRight = right("write");

	my $tt = Taranis::Template->new;
	if($templId) {
		$tt->getTemplate(id => $templId);
		$vars->{publicationTemplate} = $tt->{dbh}->fetchRow();
		$vars->{message} = $tt->{errmsg};

		my $pt = Taranis::Publicationtype->new(Config);
		$vars->{publication_types}   = [ $pt->allPublicationTypes ];

		$vars->{write_right}         = $writeRight;
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
			id => $templId,
		}
	};
}

sub	saveNewPublicationTemplate {
	my %kvArgs = @_;
	my ($message, $templId);

	my $title = val_string $kvArgs{title};
	if ( right("write") ) {
		my $tt = Taranis::Template->new;
		if ( !$tt->{dbh}->checkIfExists( { title => $title }, "publication_template", "IGNORE_CASE" ) ) {
			my $template    = $kvArgs{template};
			my $description = $kvArgs{description};
			s/\r//g for $template, $description;

			$tt->addTemplate(
				title       => $title,
				description => $description,
				template    => $template,
				type        => $kvArgs{type},
			);
			$templId = $tt->{dbh}->getLastInsertedId('publication_template');
			setUserAction( action => 'add publication template', comment => "Added publication template '$title'");
		} else {
			$message = "A template with the same title already exists.";
		}

	} else {
		$message = 'No permission';
	}

	my $saveOk = $message ? 0 : 1;
	return {
		params => {
			saveOk    => $saveOk,
			message   => $message,
			id        => $templId,
			insertNew => 1,
		}
	};
}

sub savePublicationTemplateDetails {
	my %kvArgs  = @_;
	my $templId = val_int $kvArgs{id};

	my $message;
	if(right("write") && $templId) {
		my $tt = Taranis::Template->new;
		$tt->getTemplate( id => $templId );
		my $originalTemplateTitle = $tt->{dbh}->fetchRow()->{title};

		my $title = val_string $kvArgs{title};
		if ( lc $title eq lc $originalTemplateTitle
			|| !$tt->{dbh}->checkIfExists( { title => $title }, "publication_template", "IGNORE_CASE" )
		) {
			my $template = $kvArgs{template};
			my $descr    = $kvArgs{description};
			s/(\r)//g for $template, $descr;

			$tt->setTemplate(
				id          => $templId,
				template    => $template,
				description => $descr,
				type        => $kvArgs{type},
				title => $title,
			);
			setUserAction( action => 'edit publication template', comment => "Edited publication template '$originalTemplateTitle'");
		} else {
			$message = "A template with the same title already exists.";
		}

	} else {
		$message = 'No permission';
	}

	my $saveOk = !$message;

	return {
		params => {
			saveOk    => $saveOk,
			message   => $message,
			id        => $templId,
			insertNew => 0,
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

	my $publicationTypes = right("particularization") || [];

	my $tt = Taranis::Template->new;
	$search{type} = [ $tt->getTypeIds(@$publicationTypes) ]
		if @$publicationTypes;

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
