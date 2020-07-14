#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::HttpUtil qw(lwpRequest);
use Taranis::Template;
use Taranis::SoftwareHardware;
use Taranis::ImportCpe;
use strict;

use JSON;
use XML::XPath;
use HTML::Entities qw(encode_entities);
use filetest 'access';
use File::Basename qw(basename);

my @EXPORT_OK = qw(
	openDialogImportCPE getCPEImportEntries loadCPEFile processXml
	addCPEImportItem updateCPEImportItem deleteCPEImportItem 
	bulkDiscardCPEImport bulkImportCPEImport clearImport importRest 
);

sub import_cpe_export {
	return @EXPORT_OK;
}

sub openDialogImportCPE {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $dialogContent, $fileImportDone );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		
		$fileImportDone = ( Database->checkIfExists({ cpe_id => "cpe%" }, "software_hardware_cpe_import", "IGNORE_CASE"	) ) ? 1 : 0;
		
		$tpl = 'import_cpe.tt';
		
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	$dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight, 
			fileImportDone => $fileImportDone 
		}  
	};	
}

sub loadCPEFile {
	my ( %kvArgs) = @_;
	my ( $message, $location );

	my $writeRight = right("write");
	
	my $loadFileOk = 0;
	$location = $kvArgs{location};

	if ( $writeRight ) {
		if ( $location !~ /\.xml$/i ) {
			$message = "Only valid XML is allowed.";	
		} elsif ( $location =~ m!^https?://!i ) {
	
			## concerns web location
	
			if ( $location !~ m!^https?://static\.nvd\.nist\.gov/! ) {
				$message = "Only a web location from nist.gov is allowed.";	
			} else {
	
				my $filename = basename $location;
				my $download_path = find_config 'var/cpe-dictionary';
				my $download_file = "$download_path/$filename";

				my $result = lwpRequest( get => $location, ':content_file' => $download_file);
	
				if ( $result->is_success ) {
					my $fh;
					open ( $fh, "<", $download_file );
					my $firstLine = <$fh>;
					close ( $fh );
	
					if ( $firstLine =~ /<\?xml version='1\.0' encoding='UTF-8'\?>/ ) {
						$loadFileOk = 1;
						$location = $download_file;
					} else {
						$message = "The downloaded file does not seem te be a valid XML file.";
					}
				} else {
					$message = "Error GET request: " . $result->status_line;
				}
			}
		} else {
			
		## concerns server location
	
			if ( !-r $location ) {
				$message = "Cannot read file";						
			} else {
				my $fh;
				open ( $fh, "<", $location );
				my $firstLine = <$fh>;
				close ( $fh ); 
	
				if ( $firstLine =~ /<\?xml version='1\.0' encoding='UTF-8'\?>/ ) {
					$loadFileOk = 1;
					$location = $location;
				} else {
					$message = "The downloaded file does not seem te be a valid XML file.";
				}
			}
		}
	} else {
		$message = "No permission";
	}
	
	if ( $loadFileOk ) {
		setUserAction( action => 'download cpe', comment => "Downloaded CPE file");
	} else {
		setUserAction( action => 'download cpe', comment => "Got error '$message' while trying to download CPE file");
	}
	
	return {
		params => { 
			location => $location,
			message => $message,
			loadFileOk => $loadFileOk
		}
	};
}

sub processXml {
	my ( %kvArgs) = @_;
	my $message;

	my $writeRight = right("write");
	
	if ( $writeRight ) {

		my $xp = XML::XPath->new( filename => $kvArgs{file} );
		my $sh = Taranis::SoftwareHardware->new( Config );
		my $ic = Taranis::ImportCpe->new( Config );

		my $importOptionVersions = $kvArgs{importOptionVersions};
		my $nodeset = $xp->find( '//cpe-item' );

		CPE:
		foreach my $cpe ( $nodeset->get_nodelist ) {

			my $is_deprecated = 0;
			my $cpe_id = $cpe->find( '@name' )->string_value;
			my ( $prefix, $type, $producer, $product, $version, $update, $edition, $language ) = split( /:/, $cpe_id );
			    
			$version = trim( encode_entities( $version ) ) if ( $version );
			$version = undef if ( !defined( $version ) );

			$producer = trim( encode_entities( $producer ) );			    
			$producer =~ /^([0-9]*)([\s\-_]*)([a-z]*.*)$/i;
			$producer = $1 . $2 . ucfirst( $3 );

			$type =~ s/\///;
			    			    
			if ( $cpe->find( '@deprecated' )->string_value =~ /true/ ) {
				$is_deprecated = 1;
			}
			
			my $name = trim( $cpe->find( 'title[@xml:lang="en-US"]' )->string_value );

			$name = encode_entities( $name );

			if ( $name =~ /^(\Q$producer\E)/i ) {
				$producer = $1;
			}
					
			$name =~ s/^(\Q$producer\E\s)+//i if ( $name !~ /^\Q$producer\E$/i );
			$name =~ s/\s\Q$version\E$//i;	
					
			$name = trim( $name );
			$name = "" if ( !$name );
			
			my $versionCheck = ( $version ) ? $version : [ undef, '' ];
					
			if ( !$sh->{dbh}->checkIfExists( { cpe_id => $cpe_id }, "software_hardware" ) ) {

				## in dictionary, but not in Taranis
				if ( $is_deprecated ) {
					## deprecated in dictionary, skip entry
					next CPE;
				} else {
					## add to Taranis
							
					my $okToImport = ( $importOptionVersions && $version ) ? 0 : 1;
							
					if ( !$ic->addCpeImportEntry( 
							name => $name,
							producer => $producer,
							version => $version,
							type => $type,
							cpe_id => $cpe_id,
							ok_to_import => $okToImport
						)
					) {
						$message .= "Unable to ADD '$producer $name";
						$message .= " $version" if ( $version );
						$message .= "' with CPE ID $cpe_id, because of error: $ic->{errmsg} <br />";
					}
				}						

			} elsif ( $is_deprecated ) {
						
				## dictionary entry is deprecated, so check is SH in Taranis is linked to anything, if not delete SH in Taranis

				if ( $ic->isLinked( $cpe_id ) ) {
					next CPE;
				} else {
							
					if ( !$sh->deleteObject( cpe_id => $cpe_id ) ) {
						$message .= "Unable to DELETE '$producer $name";
						$message .= " $version" if ( $version );
						$message .= "' with CPE ID $cpe_id, because of error: $sh->{errmsg} (1)<br />";
					}
				}

			} elsif ( 
				!$sh->{dbh}->checkIfExists( 
					{ 
						name => $name,
						producer => $producer,
						version => $versionCheck,
						type => $type,
						cpe_id => $cpe_id,
					},
					"software_hardware"
				)
				&& !$sh->{dbh}->checkIfExists( { cpe_id => $cpe_id, deleted => 't' }, "software_hardware" )
			) {

				## dictionary entry is not the same as in Taranis or is set to deleted, so add entry

				my $okToImport = ( $importOptionVersions && $version ) ? 0 : 1;

				if ( !$ic->addCpeImportEntry( 
						name => $name,
						producer => $producer,
						version => $version,
						type => $type,
						cpe_id => $cpe_id,
						ok_to_import => $okToImport
					)
				) {
					$message = "Unable to ADD '$producer $name";
					$message .= " $version" if ( $version );
					$message .= "' with CPE ID $cpe_id, because of error: $ic->{errmsg} (2)<br />";
				}
														
			} else {
	
				## dictionary entry is same as in Taranis
				next CPE;
			}
		}

	} else {
		$message = "No permission";
	}
	
	if ( !$message ) {
		setUserAction( action => 'process cpe', comment => "Processed CPE file");
	} else {
		setUserAction( action => 'process cpe', comment => "Got error '$message' while trying to process CPE file");
	}	
	
	return {
		params => { 
			message => $message
		}
	};
}

sub getCPEImportEntries {
	my ( %kvArgs) = @_;
	my ( $message, $importList, $leftToImport) ;

	my $writeRight = right("write");
	my $getEntriesOk = 0;
	
	if ( $writeRight ) {
	
		my $sh = Taranis::SoftwareHardware->new( Config );
		my $ic = Taranis::ImportCpe->new( Config );
				
		$importList = $ic->loadCollection( limit => 200, ok_to_import => 1 );
				
		foreach ( @$importList ) {
			$_->{version} = '' if ( !$_->{version} );
			$_->{is_new} = 0;
			$_->{has_multiple} = 0;

			## if there is an exact match on CPE ID ##
			if ( $sh->{dbh}->checkIfExists( { cpe_id => $_->{cpe_id} }, "software_hardware" ) ) {
				$_->{taranisEntry} = $sh->loadCollection( cpe_id => $_->{cpe_id} )->[0];

				$_->{taranisEntry}->{version} = '' if ( !$_->{taranisEntry}->{version} );
						
			} else {

				## if there is 1 match without a CPE ID ## 
				my $versionForCounting = ( $_->{version} ) ? $_->{version} : [ '', undef ];
				my $entryNoCPECount = $ic->{dbh}->countRows( 
					{ 
						producer 	=> $_->{producer},
						name 			=> $_->{name},
						version 	=> $versionForCounting,
						type 			=> $_->{type},
						cpe_id 		=> undef,
						deleted		=> 0
					}, 
					'software_hardware',
					'IGNORE_CASE',
					1 
				 ); 

				if ( $entryNoCPECount == 1 ) {

					$_->{taranisEntry} = $sh->loadCollection(  
						producer 	=> { -ilike => $_->{producer} },
						name 			=> { -ilike => $_->{name} },
						version 	=> $versionForCounting ,
						type 			=> $_->{type},
						cpe_id 		=> undef 
					)->[0];

					$_->{taranisEntry}->{version} = '' if ( !$_->{taranisEntry}->{version} );
							
				} elsif ( $entryNoCPECount > 1 ) {
					## if there are multiple matches without a CPE ID ##
					$_->{is_new} = 1;
					$_->{has_multiple} = 1;
				} else {
					## if there are no matches at all ##
					$_->{is_new} = 1;
				}
			}
		}
				
		if ( scalar( @$importList ) == 0 ) {
			$leftToImport = $sh->{dbh}->countRows( {}, 'software_hardware_cpe_import' );
		}
				
		$getEntriesOk = 1;
	
	
	} else {
		$message = "No permission";
	}
	
	return {
		params => { 
			message => $message,
			importList => $importList,
			leftToImport => $leftToImport,
			getEntriesOk => $getEntriesOk
		}
	};	
}

sub addCPEImportItem {
	my ( %kvArgs) = @_;
	my ( $message, $softwareHardwareId, $import ) ;

	my $writeRight = right("write");
	my $addOk = 0;
	
	if ( $writeRight ) {

		my $jsonImport = $kvArgs{import};
		$jsonImport =~ s/&quot;/"/g;
	
		$import = from_json( $jsonImport );
		
		my $setDeleteFlag = ( $import->{setDelete} ) ? 1 : 0;				

		$softwareHardwareId = $import->{import_id};
		my $ic = Taranis::ImportCpe->new( Config );
				
		withTransaction {
			if (
				$ic->importCpeEntry(
					producer => $import->{producer},
					name => $import->{name},
					version => $import->{version},
					type => $import->{type},
					cpe_id => $import->{cpe_id},
					deleted => $setDeleteFlag
				)
				&& $ic->deleteImportEntry( id => $softwareHardwareId )
			) {
				$addOk = 1;
			} else {
				$message = $ic->{errmsg};
			}
		};

	} else {
		$message = "No permission";
	}
	
	my $imported = $import->{producer} . ' ' . $import->{name};
	$imported .= ' ' . $import->{version} if ( $import->{version} );
	$imported .= ' ' . $import->{cpe_id} if ( $import->{cpe_id} );

	if ( $addOk ) {
		setUserAction( action => 'import cpe item', comment => "Imported '$imported' from CPE");
	} else {
		setUserAction( action => 'import cpe item', comment => "Got error '$message' while trying to import '$imported' from CPE");
	}
		
	return {
		params => { 
			message => $message,
			importAction => $addOk,
			id => $softwareHardwareId
		}
	};
}

sub updateCPEImportItem {
	my ( %kvArgs) = @_;
	my ( $message, $importList, $leftToImport, $softwareHardwareId, $import );

	my $writeRight = right("write");
	my $updateOk = 0;
	
	if ( $writeRight ) {

		my $jsonImport = $kvArgs{import};
		$jsonImport =~ s/&quot;/"/g;
	
		$import = from_json( $jsonImport );
		my $producer = $import->{producer};
		my $name = $import->{name};
		my $version = $import->{version};
		my $type = $import->{type};
		$softwareHardwareId = $import->{import_id};
		my $cpeID = $import->{cpe_id};
		
		my $setDeleteFlag = ( $import->{setDelete} ) ? 1 : 0;				
		
		my $versionForLoadCollection = ( $version ) ? { -ilike => $version } : [ undef, '' ];
		
		my $sh = Taranis::SoftwareHardware->new( Config );
		
		if ( 
			$sh->{dbh}->countRows( { 
				producer => $producer,
				name => $name,
				version => $versionForLoadCollection,
				type => $type,
				cpe_id => undef
			}, 
			'software_hardware',
			'IGNORE_CASE',
			1 
			) == 1
		) {

			my $softwareHardware = $sh->loadCollection( 
				producer => { -ilike => $producer },
				name => { -ilike => $name },
				type => $type,
				version => $versionForLoadCollection,
				cpe_id => undef
			);

			withTransaction {
				if (
					$sh->setObject(
						id => $softwareHardware->[0]->{id},
						producer => $producer,
						name => $name,
						version => $version,																
						cpe_id => $cpeID
					)
					&& $sh->deleteObject( table => 'software_hardware_cpe_import', id => $softwareHardwareId )
				) {
					$updateOk = 1;
				} else {
					$message = $sh->{errmsg};
				}
			};
			
		} else {
		
			withTransaction {
				if ( 
					$sh->setObject(
						producer => $producer,
						name => $name,
						version  => $version,
						type => $type,
						cpe_id => $cpeID,
						deleted => $setDeleteFlag															
					) 
					&& $sh->deleteObject( table => 'software_hardware_cpe_import', id => $softwareHardwareId )
				) {
					$updateOk = 1;
				} else {
					$message = $sh->{errmsg};
				}
			};
		}

	} else {
		$message = "No permission";
	}

	my $imported = $import->{producer} . ' ' . $import->{name};
	$imported .= ' ' . $import->{version} if ( $import->{version} );
	$imported .= ' ' . $import->{cpe_id} if ( $import->{cpe_id} );

	if ( $updateOk ) {
		setUserAction( action => 'update cpe item', comment => "Updated '$imported' from CPE");
	} else {
		setUserAction( action => 'update cpe item', comment => "Got error '$message' while trying to update '$imported' from CPE");
	}
	
	return {
		params => { 
			message => $message,
			importAction => $updateOk,
			id => $softwareHardwareId
		}
	};
}

sub deleteCPEImportItem {
	my ( %kvArgs) = @_;
	my ( $message, $softwareHardwareId) ;

	my $writeRight = right("write");
	my $deleteOk = 0;
	
	if ( $writeRight && $kvArgs{id} =~ /^\d+$/ ) {

		$softwareHardwareId = $kvArgs{id};
		my $ic = Taranis::ImportCpe->new( Config );
		my $import = $ic->loadCollection( id => $softwareHardwareId );
		
		my $imported = $import->[0]->{producer} . ' ' . $import->[0]->{name}; 
		$imported .= ' ' . $import->[0]->{version} if ( $import->[0]->{version} );
		$imported .= ' ' . $import->[0]->{cpe_id} if ( $import->[0]->{cpe_id} );
				
		if ( $ic->deleteImportEntry( id => $softwareHardwareId ) ) {
			$deleteOk = 1;
			setUserAction( action => 'delete cpe import item', comment => "Deleted '$imported' from CPE import");
		} else {
			$message = $ic->{errmsg};
			setUserAction( action => 'delete cpe import item', comment => "Got error '$message' while trying to delete '$imported' from CPE import");
		}
	
	} else {
		$message = "No permission";
	}

	return {
		params => { 
			message => $message,
			importAction => $deleteOk,
			id => $softwareHardwareId
		}
	};	
}

sub bulkImportCPEImport {
	my ( %kvArgs) = @_;
	my ( $message, @importIDs ) ;

	my $writeRight = right("write");
	my $importOk = 0;
	
	if ( $writeRight ) {

		my $jsonSelection = $kvArgs{selection};
		$jsonSelection =~ s/&quot;/"/g;
				
		my $selection = from_json( $jsonSelection );
		my $ic = Taranis::ImportCpe->new( Config );
		my $sh = Taranis::SoftwareHardware->new( Config );
		
		my $setDeleteFlag = $kvArgs{setDelete};
		
		withTransaction {
			foreach my $item ( @$selection ) {
				
				my $setItemToDeleted = ( $setDeleteFlag && $item->{version} ) ? 1 : 0; 
				my $versionForLoadCollection = ( $item->{version} ) ? { -ilike => $item->{version} } : [ undef, '' ];
				
				if ( $ic->{dbh}->checkIfExists( { cpe_id => $item->{cpe_id} }, 'software_hardware' ) ) {
					if ( !$ic->{dbh}->setObject(
							'software_hardware',
							{ cpe_id => $item->{cpe_id} },																					
							{
								producer => $item->{producer},
								name => $item->{name},
								version => $item->{version},
								type => $item->{type},
								deleted => $setItemToDeleted
							}
						) 
						|| !$ic->deleteImportEntry( id => $item->{import_id} )
					) {
						$message = $ic->{dbh}->{db_error_msg};
					} else {
						push @importIDs, $item->{import_id};
					}
				} elsif ( $ic->{dbh}->countRows( 
					{ 
						producer 	=> $item->{producer},
						name 			=> $item->{name},
						version 	=> $versionForLoadCollection,
						type 			=> $item->{type},
						cpe_id 		=> undef
					}, 
					'software_hardware',
					'IGNORE_CASE', 
					1 
					) == 1
				) {						
					
					my $softwareHardware = $sh->loadCollection( 
						producer=> { -ilike => $item->{producer} },
						name => { -ilike => $item->{name} },
						type => $item->{type},
						version => $versionForLoadCollection,
						cpe_id => undef
					);
					
					if ( !$ic->{dbh}->setObject(
							'software_hardware',
							{ id => $softwareHardware->[0]->{id} },																					
							{
								producer => $item->{producer},
								name => $item->{name},
								version => $item->{version},
								type => $item->{type},
								cpe_id => $item->{cpe_id},																				
								deleted => $setItemToDeleted
							}
						) 
						|| !$ic->deleteImportEntry( id => $item->{import_id} )
					) {
						$message = $sh->{errmsg};
					} else {
						push @importIDs, $item->{import_id};
					}

				} else {

					if ( !$ic->importCpeEntry(
							producer => $item->{producer},
							name 		 => $item->{name},
							version  => $item->{version},
							type 		 => $item->{type},
							cpe_id 	 => $item->{cpe_id},
							deleted	 => $setItemToDeleted
						) 
						|| !$ic->deleteImportEntry( id => $item->{import_id} )
					) {
						$message = $ic->{errmsg};
					}else {
						push @importIDs, $item->{import_id};
					}
				}
			}
		};
		
	} else {
		$message = "No permission";
	}
	
	$importOk = 1 if ( !$message );
	if ( $importOk ) {
		setUserAction( action => 'import cpe items', comment => "Imported " . scalar( @importIDs ) . " items from CPE");
	} else {
		setUserAction( action => 'import cpe items', comment => "Got error '$message' while trying to import items from CPE");
	}

	return {
		params => { 
			message => $message,
			importOk => $importOk,
			importIDs => \@importIDs
		}
	};
}

sub bulkDiscardCPEImport {
	my ( %kvArgs) = @_;
	my ( $message, @importIDs );

	my $writeRight = right("write");
	my $importOk = 0;
	
	if ( $writeRight ) {

		my $jsonSelection = $kvArgs{selection};
		$jsonSelection =~ s/&quot;/"/g;
				
		my $selection = from_json( $jsonSelection );

		my $ic = Taranis::ImportCpe->new( Config );
						
		my @importIds;
		withTransaction {

			foreach my $item ( @$selection ) {
			
				if ( !$ic->deleteImportEntry( id => $item->{import_id} ) ) {
					$message = $ic->{errmsg};
				} else {
					push @importIDs, $item->{import_id};
				}
			}
		};
	} else {
		$message = "No permission";
	}
	
	$importOk = 1 if ( !$message );
	if ( $importOk ) {
		setUserAction( action => 'delete cpe import items', comment => "Deleted " . scalar( @importIDs ) . " items from CPE import");
	} else {
		setUserAction( action => 'delete cpe import items', comment => "Got error '$message' while trying to delete items from CPE import");
	}

	return {
		params => { 
			message => $message,
			importOk => $importOk,
			importIDs => \@importIDs
		}
	};	
}

sub importRest {
	my ( %kvArgs) = @_;
	my ( $message );

	my $writeRight = right("write");
	my $importOk = 1;
	my $importCount = 0;
	
	if ( $writeRight ) {
		my $ic = Taranis::ImportCpe->new( Config );
		my $products = $ic->getUniqueProducts();
		
		withTransaction {
			foreach my $product ( @$products ) {
				
				if ( !$ic->{dbh}->checkIfExists( 
						{ 
							producer => $product->{producer}, 
							name => $product->{name},
							type => $product->{type} 
						}, 
						'software_hardware', 
						'IGNORE_CASE' 
					)
				) {
					if ( !$ic->importCpeEntry( 
							producer => $product->{producer}, 
							name => $product->{name}, 
							type => $product->{type},
							deleted => 0,
					  )
					) {
						$message = $ic->{errmsg};
						$importOk = 0;
					} else {
						$importCount++;
					}
				}		
			}
			
			if ( $importOk ) {
				if ( !$ic->deleteAllImportEntries() ) {
					$importOk = 0;
					$message = $ic->{errmsg};						
				}
			}
		};

	} else {
		$message = "No permission";
	}
	
	$importOk = 1 if ( !$message );
	if ( $importOk ) {
		setUserAction( action => 'import cpe items', comment => "Imported $importCount items from CPE import");
	} else {
		setUserAction( action => 'import cpe items', comment => "Got error '$message' while trying to import items from CPE import");
	}

	return {
		params => { 
			message => $message,
			importOk => $importOk,
			itemsImported => $importCount
		}
	};	
}

sub clearImport {
	my ( %kvArgs) = @_;
	my ( $message );

	my $writeRight = right("write");
	my $clearOk = 0;
	
	if ( $writeRight ) {
	
		my $ic = Taranis::ImportCpe->new( Config );
				
		if ( !$ic->deleteAllImportEntries() ) {
			$message = $ic->{errmsg};						
		}		
	} else {
		$message = "No permission";
	}
	
	$clearOk = 1 if ( !$message );
	if ( $clearOk ) {
		setUserAction( action => 'delete cpe import items', comment => "Cleared all items from CPE import");
	} else {
		setUserAction( action => 'delete cpe import items', comment => "Got error '$message' while trying to clear all items from CPE import");
	}

	return {
		params => { 
			message => $message,
			clearOk => $clearOk
		}
	};	
}
1;
