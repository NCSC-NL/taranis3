#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Constituent_Group;
use Taranis::Database qw(withTransaction);
use Taranis::Publicationtype;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw( :all);
use Tie::IxHash;
use strict;

my @EXPORT_OK = qw( 
	displayConstituentTypes openDialogNewConstituentType openDialogConstituentTypeDetails 
	saveNewConstituentType saveConstituentTypeDetails deleteConstituentType getConstituentTypeItemHtml
);

sub constituent_types_export {
	return @EXPORT_OK;
}

sub displayConstituentTypes {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $cg = Taranis::Constituent_Group->new( Config );
	my $tt = Taranis::Template->new;

	my @constituentTypes = $cg->getTypeByID();
	if ( $constituentTypes[0] ) {
		for (my $i = 0; $i < @constituentTypes; $i++ ) {
			if ( !$cg->{dbh}->checkIfExists( { constituent_type => $constituentTypes[$i]->{id}, status => 0 }, "constituent_group") ) {
				$constituentTypes[$i]->{status} = 1;
			} else {
				$constituentTypes[$i]->{status} = 0;
			}
		}
	} else {
		undef @constituentTypes;
	}
	
	$vars->{constituentTypes} = \@constituentTypes;
	$vars->{numberOfResults} = scalar @constituentTypes;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('constituent_types.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('constituent_types_filters.tt', $vars, 1);
	
	my @js = ('js/constituent_types.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}


sub deleteConstituentType {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my $constituentType = $cg->getTypeByID( $kvArgs{id} );
		
		if ( !$cg->deleteType( $kvArgs{id} ) ) {
			$message = $cg->{errmsg};
			setUserAction( action => 'delete constituent type', comment => "Got error '$message' while deleting constituent type '$constituentType->{type_description}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete constituent type', comment => "Deleted constituent type '$constituentType->{type_description}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $kvArgs{id}
		}
	};
}

sub openDialogNewConstituentType {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $dialogContent );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		my $cg = Taranis::Constituent_Group->new( Config );
		my $pt = Taranis::Publicationtype->new( Config );
		
		my @publicationTypes;
		$pt->getPublicationTypes();
		while ( $pt->nextObject() ) {
			push( @publicationTypes, $pt->getObject() );
		}

		$vars->{allPublicationTypes} = \@publicationTypes;
		
		$tpl = 'constituent_types_details.tt';
		
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	$dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};
}

sub saveNewConstituentType {
	my ( %kvArgs) = @_;
	my ( $message, $constituentTypeId );
	my $saveOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") ) {
		
		if ( !$cg->{dbh}->checkIfExists( {type_description => $kvArgs{description} }, "constituent_type", "IGNORE_CASE" ) ) {

			withTransaction {
				$cg->addObject( table => "constituent_type", type_description => $kvArgs{description} );
				
				$constituentTypeId = $cg->{dbh}->getLastInsertedId(	"constituent_type" );
				
				my @newTypes;
				if ( $kvArgs{selected_types} ) { 
					
					@newTypes = ( ref( $kvArgs{selected_types} ) =~ /^ARRAY$/ )
						? @{ $kvArgs{selected_types} }
						: $kvArgs{selected_types};
						
					for ( my $i = 0 ; $i < @newTypes ; $i++ ) {
						if ( $newTypes[$i] ) {
							$cg->addObject( 
								table => "type_publication_constituent", 
								publication_type_id => $newTypes[$i], 
								constituent_type_id => $constituentTypeId 
							); 
						}					
						
						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}
			};
		} else{
			$message .= "A type description with this description already exists.";
		}

		$saveOk = 1 if ( !$message );
		if ( $saveOk ) {
			setUserAction( action => 'add constituent type', comment => "Added constituent type '$kvArgs{description}'");
		} else {
			setUserAction( action => 'add constituent type', comment => "Got error '$message' while trying to add constituent type '$kvArgs{description}'");
		}

	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $constituentTypeId,
			insertNew => 1
		}
	};
}

sub openDialogConstituentTypeDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $constituentTypeId );

	my $tt = Taranis::Template->new;
	my $cg = Taranis::Constituent_Group->new( Config );
	my $pt = Taranis::Publicationtype->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$constituentTypeId = $kvArgs{id};
		my $constituentType = $cg->getTypeByID( $constituentTypeId );
		
		my ( @publicationTypeIds, @allPublicationTypes );
	
		if ( $pt->getPublicationTypes( "ct.id" => $constituentTypeId ) ) {	
			while ( $pt->nextObject ) {
				push @publicationTypeIds, $pt->getObject()->{id};
			}
		}

		$vars->{type_description} = $constituentType->{type_description};
		$vars->{id} = $constituentTypeId;
		
		$pt->getPublicationTypes();
		while ( $pt->nextObject() ) {
			push( @allPublicationTypes, $pt->getObject() );
		}
		
		if ( @publicationTypeIds ) {
			my @selectedPublicationTypes;
			
			my %types_non_selected_hash;
			tie %types_non_selected_hash, "Tie::IxHash";
			foreach my $i ( @allPublicationTypes ) { $types_non_selected_hash{ $i->{id} } = $i }		
			
			foreach my $id ( @publicationTypeIds ) {
				if ( exists( $types_non_selected_hash{$id} ) ) {
					delete $types_non_selected_hash{$id};
				}
	
				for ( my $i = 0; $i < @allPublicationTypes; $i++ ) {
				 	push @selectedPublicationTypes, $allPublicationTypes[$i] if ( $allPublicationTypes[$i]->{id} eq $id );
				}
			}
			$vars->{selectedPublicationTypes} = \@selectedPublicationTypes;
			
			my @types_non_selected_array;
			foreach my $non_selected ( values %types_non_selected_hash ) {
				push( @types_non_selected_array, $non_selected );
			}
	
			$vars->{allPublicationTypes} = \@types_non_selected_array;
		} else {
			$vars->{allPublicationTypes} = \@allPublicationTypes;
		}		

		$tpl = 'constituent_types_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $constituentTypeId
		}  
	};	
}

sub saveConstituentTypeDetails {
	my ( %kvArgs) = @_;
	my ( $message, $constituentTypeId, $originalConstituentType );
	my $saveOk = 0;
	
	my $cg = Taranis::Constituent_Group->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$constituentTypeId = $kvArgs{id};
		my $pt = Taranis::Publicationtype->new( Config );

		my ( @publicationTypeIds, @selectedPublicationTypes, @newSelectedPublicationTypes, %new_type_ids_hash, %type_ids_hash );
		if ( $pt->getPublicationTypes( "ct.id" => $constituentTypeId ) ) {	
			while ( $pt->nextObject ) {
				push @publicationTypeIds, $pt->getObject()->{id};
			}
		}

		foreach my $id ( @publicationTypeIds ) {
			$type_ids_hash{$id} = $id;
		}

		if ( $kvArgs{selected_types} ) {
			
			@selectedPublicationTypes = ( ref( $kvArgs{selected_types} ) =~ /^ARRAY$/ )
				? @{ $kvArgs{selected_types} }
				: $kvArgs{selected_types};		
		
			foreach my $id ( @selectedPublicationTypes ) {
				$new_type_ids_hash{$id} = $id;
				if ( !exists( $type_ids_hash{$id} ) ) {
					push( @newSelectedPublicationTypes, $id );
				}
			}
		}
		
		my @delete_types;
		foreach my $id ( @publicationTypeIds ) {
			if ( !exists( $new_type_ids_hash{$id} ) ) { push( @delete_types, $id ) }
		}

		my %constituentTypeUpdate = ( table => "constituent_type", id => $constituentTypeId, type_description => $kvArgs{description} );

		$originalConstituentType = $cg->getTypeByID( $constituentTypeId );

		if ( 
			!$cg->{dbh}->checkIfExists( {type_description => $kvArgs{description} } , "constituent_type", "IGNORE_CASE" ) 
			|| lc( $kvArgs{description} ) eq lc( $originalConstituentType->{type_description} ) 
		) {		
			
			withTransaction {
				# UPDATE CONSTITUENT DESCRIPTION
				$cg->setObject( %constituentTypeUpdate );
				
				$message = $cg->{errmsg};
				
				# ADD PUBLICATION TYPES TO CONSTITUENT TYPE
				if ( @newSelectedPublicationTypes ) {
					for ( my $i = 0 ; $i < @newSelectedPublicationTypes ; $i++ ) {
						if ( $newSelectedPublicationTypes[$i] ) {
							$cg->addObject( 
								table => "type_publication_constituent", 
								constituent_type_id => $constituentTypeId, 
								publication_type_id => $newSelectedPublicationTypes[$i] 
							) 
						}					
						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );					
					}
				}
				
				# DELETE PUBLICATION TYPES OF CONSTITUENT TYPE
				if ( @delete_types ) {
					for ( my $i = 0 ; $i < @delete_types ; $i++ ) {
						if ( $delete_types[$i] ) {
							$cg->deleteObject( 
								table => "type_publication_constituent",	
								constituent_type_id => $constituentTypeId,	
								publication_type_id => $delete_types[$i] 
							);
						}
						$message = $cg->{errmsg} if ( $message !~ /$cg->{errmsg}/g && $cg->{errmsg} ne "" );
					}
				}	

				$cg->deleteConstituentPublication();
			};
		} else {
			$message = "A type description with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		if ( $saveOk ) {
			setUserAction( action => 'edit constituent type', comment => "Edited constituent type '$originalConstituentType->{type_description}'");
		} else {
			setUserAction( action => 'edit constituent type', comment => "Got error '$message' while trying to edit constituent type '$originalConstituentType->{type_description}'");
		}

	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $constituentTypeId,
			insertNew => 0
		}
	};	
}

sub getConstituentTypeItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $cg = Taranis::Constituent_Group->new( Config );
	
	my $constituentTypeId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $constituentType = $cg->getTypeByID( $constituentTypeId );
 
	if ( $constituentType ) {

		if ( !$insertNew && $cg->{dbh}->checkIfExists( { constituent_type => $constituentTypeId, status => 0 }, "constituent_group") ) {
			$constituentType->{status} = 0;
		} else {
			$constituentType->{status} = 1;
		}

		$vars->{constituentType} = $constituentType;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'constituent_types_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $constituentTypeId
		}
	};
}

1;
