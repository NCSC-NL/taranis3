#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::ImportPhoto;
use Taranis::SoftwareHardware;
use Taranis::Template;
use POSIX;

my @EXPORT_OK = qw( 
	displaySoftwareHardware openDialogNewSoftwareHardware openDialogSoftwareHardwareDetails searchSoftwareHardware
	saveNewSoftwareHardware saveSoftwareHardwareDetails deleteSoftwareHardware getSoftwareHardwareItemHtml
);

sub software_hardware_export {
	return @EXPORT_OK;
}

sub displaySoftwareHardware {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $sh = Taranis::SoftwareHardware->new( Config );
	my $tt = Taranis::Template->new;

	my @vendors = $sh->getDistinctList(deleted => 0);
	$vars->{vendors} = \@vendors;

	my $types = $sh->getBaseTypes();
	foreach my $baseType ( keys %$types ) {
		if ( my $description = $sh->getSuperTypeDescription( $baseType ) ) {
			$types->{$baseType} .= " ($description->{description})"; 
		}
	}
	$vars->{base_types} = $types; 

	my @softwareHardwareList;
	my $resultCount = $sh->getListCount();
		
	$sh->getList( limit => '100', offset => '0' );
	while ( $sh->nextObject() ) {
		push @softwareHardwareList, $sh->getObject();
	}
	
	foreach my $product ( @softwareHardwareList ) {
		$product->{constituentGroups} = $sh->getConstituentUsage( $product->{id} );
	}
	
	$vars->{softwareHardware} = \@softwareHardwareList;
	$vars->{filterButton} = 'btn-software-hardware-search';
	$vars->{page_bar} = $tt->createPageBar( 1, $resultCount, 100 );

	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('software_hardware.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('software_hardware_filters.tt', $vars, 1);
	
	my @js = ('js/software_hardware.js', 'js/import_cpe.js', 'js/constituent_group.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewSoftwareHardware {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	my $writeRight = right("write");
	
	if ( $writeRight ) {

		my $types = $sh->getBaseTypes();
		foreach my $baseType ( keys %$types ) {
			
			if ( my $description = $sh->getSuperTypeDescription( $baseType ) ) {
				$types->{$baseType} .= " ($description->{description})"; 
			}
		}
		$vars->{base_types} = $types; 
		
		# when adding a S/H from photo import
		if ( exists( $kvArgs{import_id} ) && $kvArgs{import_id} =~ /^\d+$/ ) {
			my $oTaranisImportPhoto = Taranis::ImportPhoto->new( Config );
			my $importSH = $oTaranisImportPhoto->getImportSoftwareHardware( id => $kvArgs{import_id} );
			$vars->{softwareHardwareItem} = ( ref( $importSH ) =~ /^ARRAY$/ )
				? $importSH->[0]
				: $importSH;

			delete $vars->{softwareHardwareItem}->{id};
			my $shType = $sh->getShType( description => $vars->{softwareHardwareItem}->{type} );
			if ( $shType ) {
				$vars->{softwareHardwareItem}->{type} = $shType->{base};
			} else {
				$vars->{message} = "WARNING: UNKNOWN TYPE '$vars->{softwareHardwareItem}->{type}'<br>Add type to Software/Hardware Types!";
			}
		}
		
		$tpl = 'software_hardware_details.tt';
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

sub openDialogSoftwareHardwareDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};

		my $types = $sh->getBaseTypes();
		foreach my $baseType ( keys %$types ) {
			
			if ( my $description = $sh->getSuperTypeDescription( $baseType ) ) {
				$types->{$baseType} .= " ($description->{description})"; 
			}
		}
		$vars->{base_types} = $types; 
		
		$vars->{softwareHardwareItem} = $sh->getList( id => $id );
		$vars->{constituentGroups} = $sh->getConstituentUsage( $id );

		$vars->{id} = $id;

		$tpl = 'software_hardware_details.tt';
		
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
 
sub saveNewSoftwareHardware {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	my $sh = Taranis::SoftwareHardware->new( Config );

	if ( right("write") ) {
        if ( $sh->addObject(
				producer => $kvArgs{producer},
				name => $kvArgs{name},
				version => $kvArgs{version},
				monitored => $kvArgs{monitored},
				type => $kvArgs{type}
			)
		) {
			$id = $sh->{dbh}->getLastInsertedId( "software_hardware" );
		} else {
			$message = $sh->{errmsg};
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}

	my $softwareHardwareStr = $kvArgs{producer} . ' ' . $kvArgs{name};
	$softwareHardwareStr .= $kvArgs{version} if ( $kvArgs{version} );
	$softwareHardwareStr .= $kvArgs{cpe_id} if ( $kvArgs{cpe_id} );

	if ( $saveOk ) {
		setUserAction( action => 'add software/hardware', comment => "Added '$softwareHardwareStr' to software/hardware");
	} else {
		setUserAction( action => 'add software/hardware', comment => "Got error '$message' while trying to add '$softwareHardwareStr' to software/hardware");
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

sub saveSoftwareHardwareDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my $sh = Taranis::SoftwareHardware->new( Config );
		
		$id = $kvArgs{id};
		
		if (
			!$sh->setObject(
				producer => $kvArgs{producer},
				name => $kvArgs{name},
				version => $kvArgs{version},
				monitored => $kvArgs{monitored},
				type => $kvArgs{type},
				id => $id
			)
		) {
			$message = $sh->{errmsg};
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}

	my $softwareHardwareStr = $kvArgs{producer} . ' ' . $kvArgs{name};
	$softwareHardwareStr .= $kvArgs{version} if ( $kvArgs{version} );
	$softwareHardwareStr .= $kvArgs{cpe_id} if ( $kvArgs{cpe_id} );

	if ( $saveOk ) {
		setUserAction( action => 'edit software/hardware', comment => "Edited software/hardware '$softwareHardwareStr'");
	} else {
		setUserAction( action => 'edit software/hardware', comment => "Got error '$message' while trying to edit software/hardware '$softwareHardwareStr'");
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

sub deleteSoftwareHardware {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $sh = Taranis::SoftwareHardware->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $softwareHardware = $sh->getList( id => $id );
		
		my $softwareHardwareStr = $softwareHardware->{producer} . ' ' . $softwareHardware->{name};
		$softwareHardwareStr .= $softwareHardware->{version} if ( $softwareHardware->{version} );
		$softwareHardwareStr .= $softwareHardware->{cpe_id} if ( $softwareHardware->{cpe_id} );

		withTransaction {
			if ( $sh->{dbh}->checkIfExists( {  soft_hard_id => $id }, 'soft_hard_usage' ) ) {
				$sh->deleteObject( table => 'soft_hard_usage', soft_hard_id => $id );
			}

			if ( $sh->setObject( deleted => 't', id => $id ) ) {
				$deleteOk = 1;
			} else {
				$message = $sh->{errmsg};
			}
		};
		
		if ( $deleteOk ) {
			setUserAction( action => 'delete software/hardware', comment => "Deleted software/hardware '$softwareHardwareStr'");			
		} else {
			setUserAction( action => 'delete software/hardware', comment => "Got error '$message' while deleting software/hardware '$softwareHardwareStr'");
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

sub getSoftwareHardwareItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );
	
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
	my $softwareHardwareItem = $sh->getList( id => $id );
 
	if ( $softwareHardwareItem ) {

		$softwareHardwareItem->{constituentGroups} = $sh->getConstituentUsage( $id );

		$vars->{softwareHardwareItem} = $softwareHardwareItem;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'software_hardware_item.tt';
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

sub searchSoftwareHardware {
	my ( %kvArgs) = @_;
	my ( $vars, %search, @softwareHardwareList );

	
	my $tt = Taranis::Template->new;
	my $sh = Taranis::SoftwareHardware->new( Config );

	$search{producer} = $kvArgs{vendor_name};
	$search{type} = $kvArgs{product_type};
	$search{name} = $kvArgs{name};
	$search{in_use} = $kvArgs{in_use};

	my $resultCount = $sh->getListCount(
		producer => $search{producer},
		type => $search{type},
		name => $search{name},
		in_use => $search{in_use}
	);

	my $pageNumber  = val_int $kvArgs{'hidden-page-number'} || 1;
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;
	my $offset = ( $pageNumber - 1 ) * $hitsperpage;

	my $list = $sh->getList(
		producer => $search{producer},
		type => $search{type},
		name => $search{name},
		in_use => $search{in_use},
		limit => $hitsperpage,
		offset => $offset
	);

	while ( $sh->nextObject() ) {
		push @softwareHardwareList, $sh->getObject();
	}
	
	foreach my $product ( @softwareHardwareList ) {
		$product->{constituentGroups} = $sh->getConstituentUsage( $product->{id} );
	}
	
	$vars->{softwareHardware} = \@softwareHardwareList;
	$vars->{filterButton} = 'btn-software-hardware-search';
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $resultCount, $hitsperpage );
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('software_hardware.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

1;
