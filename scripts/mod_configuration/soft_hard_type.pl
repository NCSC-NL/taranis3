#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::SoftwareHardware;
use Taranis::Template;

my @EXPORT_OK = qw( 
	displaySoftwareHardwareTypes openDialogNewSoftwareHardwareType openDialogSoftwareHardwareTypeDetails 
	saveNewSoftwareHardwareType saveSoftwareHardwareTypeDetails deleteSoftwareHardwareType getSoftwareHardwareTypeItemHtml
);

sub soft_hard_type_export {
	return @EXPORT_OK;
}

sub displaySoftwareHardwareTypes {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	my @softwareHardwareTypes;
	$sh->getShType();
    while ( $sh->nextObject() ) {
        push @softwareHardwareTypes, $sh->getObject(); 
    }

	for ( my $i = 0; $i < @softwareHardwareTypes; $i++ ) {
		$softwareHardwareTypes[$i]->{in_use} = ( $sh->{dbh}->checkIfExists( { type => $softwareHardwareTypes[$i]->{base} }, "software_hardware") ) ? 1 : 0;
		
		if ( $softwareHardwareTypes[$i]->{sub_type} ) {
			$softwareHardwareTypes[$i]->{sub_type_description} = $sh->getShType( base => $softwareHardwareTypes[$i]->{sub_type} )->{description};
		}
	}

	$vars->{softwareHardwareTypes} = \@softwareHardwareTypes;

	$vars->{numberOfResults} = scalar @softwareHardwareTypes;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('soft_hard_type.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('soft_hard_type_filters.tt', $vars, 1);
	
	my @js = ('js/soft_hard_type.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewSoftwareHardwareType {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		
		my @baseTypes;
		my $types = $sh->getBaseTypes();
		foreach my $type ( keys %$types ) {
			if ( $type =~ /^[a-z]$/ ) {
				push @baseTypes, { base => $type, description => $types->{$type} };
			}
		}
		$vars->{base_types} = \@baseTypes;
		
		$tpl = 'soft_hard_type_details.tt';
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

sub openDialogSoftwareHardwareTypeDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $typeId );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^[a-z]+$/ ) {
		$typeId = $kvArgs{id};

	    my $type = $sh->getShType( base => $typeId );
		
		if ( $type->{sub_type} ) {
			$type->{sub_type_description} = $sh->getShType( base => $type->{sub_type} )->{description};
		}

		$vars->{softwareHardwareType} = $type;

		$tpl = 'soft_hard_type_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $typeId
		}  
	};	
} 

sub saveNewSoftwareHardwareType {
	my ( %kvArgs) = @_;
	my ( $message, $typeId );
	my $saveOk = 0;
	
	my $sh = Taranis::SoftwareHardware->new( Config );

	if ( right("write") ) {
		my $sub_type = $kvArgs{sub_type};
		my $description = $kvArgs{description};

		if ( $typeId = $sh->addShType( sub_type => $kvArgs{sub_type}, description => $kvArgs{description} ) ) {
			$saveOk = 1;
			setUserAction( action => 'add software/hardware type', comment => "Added software/hardware type '$description'");
		} else {
			$message = $sh->{errmsg};
			setUserAction( action => 'add software/hardware type', comment => "Got error '$message' while trying to add software/hardware type '$description'");
		}
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $typeId,
			insertNew => 1
		}
	};
}

sub saveSoftwareHardwareTypeDetails {
	my ( %kvArgs) = @_;
	my ( $message, $typeId );
	my $saveOk = 0;


	if ( right("write") && $kvArgs{id} =~ /^[a-z]+$/ ) {
		my $sh = Taranis::SoftwareHardware->new( Config );
		$typeId = $kvArgs{id};

		if ( !$sh->setShType( base => $typeId, description => $kvArgs{description} ) ) {
			$message = $sh->{errmsg};
			setUserAction( action => 'edit software/hardware type', comment => "Got error '$message' while editing software/hardware type '$kvArgs{description}'");
		} else {
			setUserAction( action => 'edit software/hardware type', comment => "Edited software/hardware type '$kvArgs{description}'");
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $typeId,
			insertNew => 0
		}
	};
}

sub deleteSoftwareHardwareType {
	my ( %kvArgs) = @_;
	my ( $message, $typeId );
	my $deleteOk = 0;
	
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	if ( 
		right("write") 
		&& $kvArgs{id} =~ /^[a-z]+$/
		&& !$sh->{dbh}->checkIfExists( { type => $kvArgs{id} }, "software_hardware")
	) {

		$typeId = $kvArgs{id};
		my $type = $sh->getShType( base => $typeId );
		
		if ( !$sh->delShType( base => $typeId ) ) {
			$message = $sh->{errmsg};
			setUserAction( action => 'delete software/hardware type', comment => "Got error '$message' while deleting software/hardware type '$type->{description}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete software/hardware type', comment => "Deleted software/hardware type '$type->{description}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $typeId
		}
	};	
}

sub getSoftwareHardwareTypeItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	my $typeId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my @softwareHardwareTypes;

 	my $type = $sh->getShType( base => $typeId );
	if ( $type ) {

		$type->{in_use} = ( !$insertNew || !$sh->{dbh}->checkIfExists( { type => $type->{base} }, "software_hardware") ) ? 0 : 1;

		if ( $type->{sub_type} ) {
			$type->{sub_type_description} = $sh->getShType( base => $type->{sub_type} )->{description};
		}

		$vars->{softwareHardwareType} = $type;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'soft_hard_type_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $typeId
		}
	};	
}

1;
