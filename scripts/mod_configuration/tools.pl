#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw( 
	displayTools openDialogNewTool openDialogToolDetails
	saveNewTool saveToolDetails deleteTool getToolItemHtml
);

sub tools_export {
	return @EXPORT_OK;
}

sub displayTools {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );

	my $unsortedTools = $tl->loadCollection(); 
	$vars->{write_right} = right("write");
	
	if ( $unsortedTools ) {
		my @sortedTools = sort { $$a{'toolname'} cmp $$b{'toolname'} } @$unsortedTools;
		$vars->{tools} = \@sortedTools;
		$vars->{numberOfResults} = scalar @sortedTools;	
	} else {
		$vars->{numberOfResults} = "0";
	}
	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('tools.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('tools_filters.tt', $vars, 1);
	
	my @js = ('js/tools.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewTool {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {
		$tpl = 'tools_details.tt';
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

sub openDialogToolDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $toolName );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( $kvArgs{toolname} ) {
		my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );
		my $tool = $tl->getElement( $kvArgs{toolname} );

		$vars->{orig_toolname} = $tool->{toolname};
		$vars->{tool} = $tool;
		$vars->{write_right} = $writeRight;
        
		$tpl = 'tools_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			toolname => $kvArgs{toolname}
		}  
	};
}

sub saveNewTool {
	my ( %kvArgs) = @_;
	my ( $message, $toolName );
	my $saveOk = 0;
	
	
	$kvArgs{toolname} =	sanitizeInput("xml_primary_key", $kvArgs{toolname} );
	
	if ( right("write") && $kvArgs{toolname} ) {
		
		$toolName = $kvArgs{toolname};
		my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );
		
		my $backendToolsLocation = normalizePath($tl->{config}->{backend_tools});
		
		if ( !$tl->checkIfExists( $kvArgs{toolname} ) ) {
			
			$kvArgs{backend} =~ s/$backendToolsLocation//gi;
			$kvArgs{backend} =~ s/^\/+//;
			$kvArgs{backend} =~ s/\/+/\//;

			if ( !$tl->addElement(
				toolname => $kvArgs{toolname},
				webscript => $kvArgs{webscript},
				backend => $kvArgs{backend}
				)
			) {
				$message= $tl->{errmsg};
			}
		} else {
			$message = "A tool with the same name already exists.";
		}
	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'add tool', comment => "Added tool '$kvArgs{toolname}'");
	} else {
		setUserAction( action => 'add tool', comment => "Got error '$message' while trying to add tool '$kvArgs{toolname}'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			toolname => $toolName,
			insertNew => 1
		}
	};
}

sub saveToolDetails {
	my ( %kvArgs) = @_;
	my ( $message, $toolName, $originalToolName );
	my $saveOk = 0;
	

	( $kvArgs{toolname}, $kvArgs{orig_toolname} ) = sanitizeInput("xml_primary_key", $kvArgs{toolname}, $kvArgs{orig_toolname} );
	
	if ( right("write") && $kvArgs{toolname} && $kvArgs{orig_toolname} ) {
		
		$toolName = $kvArgs{toolname};
		$originalToolName = $kvArgs{orig_toolname};
		my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );
		my $backendToolsLocation = normalizePath($tl->{config}->{backend_tools});
		
		if ( lc( $kvArgs{toolname} ) eq lc( $kvArgs{orig_toolname} ) || !$tl->checkIfExists( $kvArgs{toolname} ) ) {
			$kvArgs{backend} =~ s/$backendToolsLocation//gi;
			$kvArgs{backend} =~ s/^\/+//;
			$kvArgs{backend} =~ s/\/+/\//;
			if ( !$tl->setElement(	
				toolname => $kvArgs{toolname}, 
				webscript => $kvArgs{webscript},
				backend => $kvArgs{backend},												
				orig_toolname => $kvArgs{orig_toolname} 
				) 
			) {
				$message = $tl->{errmsg};
			}
		} else {
			$message = "A tool with the same name already exists.";
		}
	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit tool', comment => "Edited tool '$kvArgs{orig_toolname}'");
	} else {
		setUserAction( action => 'edit tool', comment => "Got error '$message' while trying to edit tool '$kvArgs{orig_toolname}'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			toolname => $toolName,
			originalToolname => $originalToolName,
			insertNew => 0
		}
	};
}

sub deleteTool {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );

	$kvArgs{toolname} = sanitizeInput("xml_primary_key", $kvArgs{toolname} );

	if ( right("write") && $kvArgs{toolname} ) {
		if (!$tl->deleteElement( $kvArgs{toolname} ) ) {
			$message = $tl->{errmsg};
			setUserAction( action => 'delete tool', comment => "Got error '$message' while trying to delete tool '$kvArgs{toolname}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete tool', comment => "Deleted tool '$kvArgs{toolname}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			toolname => $kvArgs{toolname}
		}
	};
}

sub getToolItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $tl = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );
	
	my $insertNew = $kvArgs{insertNew};
	
 	( $kvArgs{toolname}, $kvArgs{orig_toolname} ) = sanitizeInput("xml_primary_key", $kvArgs{toolname}, $kvArgs{orig_toolname} );
 	my $originalToolName = $kvArgs{orig_toolname};
	my $toolName= $kvArgs{toolname};

	my $tool = $tl->getElement( $kvArgs{toolname} );
	 
	if ( $tool ) {
		$vars->{tool} = $tool;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'tools_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			toolname => $toolName,
			originalToolname => $originalToolName
		}
	};	
}
1;
