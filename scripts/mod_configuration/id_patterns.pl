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
	displayIDPatterns openDialogNewIDPattern openDialogIDPatternDetails
	saveNewIDPattern saveIDPatternDetails deleteIDPattern
	searchIDPatterns getIDPatternItemHtml 
);

sub id_patterns_export {
	return @EXPORT_OK;
}

sub _idconfig() {
	Taranis::Config::XMLGeneric->new(Config->{identifiersconfig}, "idname", "ids");
}

sub displayIDPatterns {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $ip = _idconfig;
	my $tt = Taranis::Template->new;
	
	my $unsortedPatterns = $ip->loadCollection();
	my @patterns = sort { $$a{'idname'} cmp $$b{'idname'} } @$unsortedPatterns;
	
	$vars->{patterns} = \@patterns;
	$vars->{numberOfResults} = scalar @patterns;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('id_patterns.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('id_patterns_filters.tt', $vars, 1);
	
	my @js = ('js/id_patterns.js');

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewIDPattern {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {

		$tpl = 'id_patterns_details.tt';
		
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

sub openDialogIDPatternDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $ip = _idconfig;
	my $writeRight = right("write"); 

	if ( exists( $kvArgs{id} ) && $kvArgs{id} ) {
		$id = $kvArgs{id};
		
		my $patterns = $ip->getElement( $kvArgs{id} );
		$vars->{pattern} = $patterns;

		$vars->{write_right} = $writeRight;
        
		$tpl = 'id_patterns_details.tt';
		
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

sub saveNewIDPattern {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && exists( $kvArgs{idname} ) && $kvArgs{idname} ) {
		$id = sanitizeInput("xml_primary_key", $kvArgs{idname} );
		
		my $ip = _idconfig;
		
		if ( !$ip->checkIfExists( $id ) ) {
			if ( 
				!$ip->addElement( 
					idname => $id, 
					pattern => $kvArgs{pattern}, 
					substitute => $kvArgs{substitute} 
				) 
			) {
				$message = $ip->{errmsg};
				setUserAction( action => 'add id pattern', comment => "Got error '$message' while trying to add ID pattern '$id'");
			} else {
				setUserAction( action => 'add id pattern', comment => "Added ID pattern '$id'");
			}
		} else {
			$message = "A pattern with the same name already exists.";
		}

	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id
		}
	};
}

sub saveIDPatternDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id, $originalId );
	my $saveOk = 0;
	
	
	if ( right("write") && $kvArgs{idname} && $kvArgs{originalId} ) {
		( $id, $originalId ) = sanitizeInput("xml_primary_key", $kvArgs{idname}, $kvArgs{originalId} );	
		
		my $ip = _idconfig;

		if ( lc( $id ) eq lc( $originalId ) || !$ip->checkIfExists( $id ) ) {
			if ( 
				!$ip->setElement(	
					idname => $id,  
					pattern => $kvArgs{pattern}, 
					substitute => $kvArgs{substitute}, 
					orig_idname=> $originalId, 
				) 
			) {
				$message = $ip->{errmsg};
				setUserAction( action => 'edit id pattern', comment => "Got error '$message' while trying to edit ID pattern '$originalId'");
			} else {
				setUserAction( action => 'edit id pattern', comment => "Edited ID pattern '$originalId'");
			}
		} else {
			$message = "A pattern with the same name already exists.";
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
			originalId => $originalId
		}
	};
}

sub deleteIDPattern {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $ip = _idconfig;

	if ( right("write") && $kvArgs{id} ) {
		$id = sanitizeInput("xml_primary_key", $kvArgs{id} );
			
		if ( !$ip->deleteElement( $id ) ) {
			$message = $ip->{errmsg};
			setUserAction( action => 'delete id pattern', comment => "Got error '$message' while deleting ID pattern '$id'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete id pattern', comment => "Deleted ID pattern '$id'");
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

sub searchIDPatterns {
	my ( %kvArgs) = @_;
	my ( $vars, @patterns );

	my $tt = Taranis::Template->new;
	my $ip = _idconfig;

	my $unsortedPatterns = $ip->loadCollection( $kvArgs{search_idname} );
	@patterns = sort { $$a{'idname'} cmp $$b{'idname'} } @$unsortedPatterns if ( $unsortedPatterns ); 
	
	$vars->{patterns} = \@patterns;
	$vars->{numberOfResults} = scalar @patterns;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('id_patterns.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub getIDPatternItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id, $originalId );

	my $tt = Taranis::Template->new;
	my $ip = _idconfig;
	
	my $insertNew = $kvArgs{insertNew};
	
 	( $id, $originalId ) = sanitizeInput("xml_primary_key", $kvArgs{id}, $kvArgs{originalId} );

	my $pattern = $ip->getElement( $id );
	 
	if ( $pattern ) {
		$vars->{pattern} = $pattern;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'id_patterns_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id,
			originalId=> $originalId
		}
	};	
}

1; 
