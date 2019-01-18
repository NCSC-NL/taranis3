#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Damagedescription;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use strict;

my @EXPORT_OK = qw( 
	displayDamageDescriptions openDialogNewDamageDescription openDialogDamageDescriptionDetails 
	saveNewDamageDescription saveDamageDescriptionDetails deleteDamageDescription getDamageDescriptionItemHtml
);

sub damage_description_export {
	return @EXPORT_OK;
}

sub	displayDamageDescriptions {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $dd = Taranis::Damagedescription->new( Config );
	
	my @damageDescription = $dd->getDamageDescription();
	if ( @damageDescription && $damageDescription[0] ) {
		for (my $i = 0; $i < @damageDescription; $i++ ) {
			if ( !$dd->{dbh}->checkIfExists( { damage_id => $damageDescription[$i]->{id} }, "advisory_damage") && !$damageDescription[$i]->{deleted} ) {
				$damageDescription[$i]->{status} = 1;
			} else {
				$damageDescription[$i]->{status} = 0;
			}
		}
	} else {
		undef @damageDescription;
	}
	
	$vars->{damageDescriptions} = \@damageDescription;
	$vars->{numberOfResults} = scalar @damageDescription;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('damage_description.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('damage_description_filters.tt', $vars, 1);
	
	my @js = ('js/damage_description.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewDamageDescription {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'damage_description_details.tt';
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

sub openDialogDamageDescriptionDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $dd = Taranis::Damagedescription->new( Config );
		$id = $kvArgs{id};

		my $damageDescription = $dd->getDamageDescription( id => $id );
		$vars->{description} = $damageDescription->{description};
		$vars->{id} = $damageDescription->{id};

		$tpl = 'damage_description_details.tt';
		
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
 
sub saveNewDamageDescription {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $dd = Taranis::Damagedescription->new( Config );
		
		if ( !$dd->{dbh}->checkIfExists( {description => $kvArgs{description} }, "damage_description", "IGNORE_CASE" ) ) {
			if ( $dd->addDamageDescription( description => $kvArgs{description} ) ) {
				$id = $dd->{dbh}->getLastInsertedId('damage_description');
				setUserAction( action => 'add damage description', comment => "Added damage description '$kvArgs{description}'");
			} else {
				$message = $dd->{errmsg};
				setUserAction( action => 'add damage description', comment => "Got error '$message' while trying to add damage description '$kvArgs{description}'");
			}
		} else {
			$message = "A damage with the same description already exists.";
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

sub saveDamageDescriptionDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {

		my $dd = Taranis::Damagedescription->new( Config );
		$id = $kvArgs{id};
		
		my $originalDdamageDescription = $dd->getDamageDescription( id => $id )->{description};

		if (
			lc( $kvArgs{description} ) eq lc( $originalDdamageDescription ) 
			|| !$dd->{dbh}->checkIfExists( {description => $kvArgs{description} } , "damage_description", "IGNORE_CASE" ) 
		) {
			if ( !$dd->setDamageDescription( id => $id, description => $kvArgs{description} ) ) {
				$message = $dd->{errmsg};
				setUserAction( action => 'edit damage description', comment => "Got error '$message' while trying to edit damage description '$originalDdamageDescription' to '$kvArgs{description}'");
			} else {
				setUserAction( action => 'edit damage description', comment => "Edited damage description '$originalDdamageDescription' to '$kvArgs{description}'");
			}
		} else {
			$message = "A damage with the same description already exists.";
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

sub deleteDamageDescription {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $dd = Taranis::Damagedescription->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my $damageDescription = $dd->getDamageDescription( id => $id );
		
		if ( !$dd->deleteDamageDescription( $kvArgs{id} ) ) {
			$message = $dd->{errmsg};
			setUserAction( action => 'delete damage description', comment => "Got error '$message' while deleting damage description '$damageDescription->{description}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete damage description', comment => "Deleted damage description '$damageDescription->{description}'");
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

sub getDamageDescriptionItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $dd = Taranis::Damagedescription->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $damageDescription = $dd->getDamageDescription( id => $id );
 
	if ( $damageDescription ) {

		if ( !$dd->{dbh}->checkIfExists( { damage_id => $damageDescription->{id} }, "advisory_damage") && !$damageDescription->{deleted} ) {
			$damageDescription->{status} = 1;
		} else {
			$damageDescription->{status} = 0;
		}

		$vars->{damageDescription} = $damageDescription;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'damage_description_item.tt';
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
