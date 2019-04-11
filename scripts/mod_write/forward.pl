#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util flat);
use Taranis::Database qw(withTransaction);
use Taranis::Template;
use Taranis::Publication;
use Taranis::Publication::Advisory;
use Taranis::Analysis;
use Taranis::Users qw();
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);
use Taranis::FunctionalWrapper qw(CGI Config Publication Template Users);
use Taranis::Damagedescription;
use Taranis::SoftwareHardware;
use Taranis::Config::XMLGeneric;
use Taranis::Configuration::CVE;
use Taranis::Screenshot;
use Taranis::Session qw(sessionGet);
use strict;
use JSON;
use Carp;
use CGI::Simple;
use Encode qw(decode_utf8);

my @EXPORT_OK = qw(
	openDialogNewForward openDialogForwardDetails openDialogUpdateForward openDialogPreviewForward 
	saveForwardDetails saveNewForward saveUpdateForward setForwardStatus getForwardPreview
);

sub forward_export {
	return @EXPORT_OK; 
}

sub openDialogNewForward {
	my ( %kvArgs ) = @_;
	my ( $vars, $idString, $analysis);
	
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	if ( rightOnParticularization( $typeName ) && right('write') ) {
		my $oTaranisAnalysis = Taranis::Analysis->new( Config );
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		
		my $settings = getAdvisoryForwardSettings();
		
		my $userId = sessionGet('userid'); 
		
		my $analysisId = ( exists( $kvArgs{analysisId} ) && $kvArgs{analysisId} =~ /^\d{8}$/) ? $kvArgs{analysisId} : undef;
	
		$vars->{analysis_id} = $analysisId;
		$vars->{pub_type} = 'email';
				
		########## TAB GENERAL #########
		if ( $analysisId ) { 
			$analysis = $oTaranisAnalysis->getRecordsById( table => 'analysis', id => $analysisId )->[0];

			if ( $analysis->{idstring} ) {
				my @ids = split( ' ', $analysis->{idstring} );
				foreach ( @ids ) {

					if ( $_ =~ /^CVE.*/i) {
						$idString .= $_.', ';
					}
				}
				
				$idString =~ s/, $//;
			}
		}
		
		@{ $vars->{damage_description} } = $oTaranisDamageDescription->getDamageDescription();
		$vars->{advisory_id} = $settings->{advisoryPrefix} . '-' . nowstring(6) . '-' . $settings->{x};
		$vars->{advisory_version} = '1.00';
		$vars->{author} = Users->getUser( $userId )->{fullname};
		$vars->{date_created} = nowstring(9);
		$vars->{cve_id} = sortCVEString( $idString );
			
		######### TAB PLATFORM(s) & PRODUCT(s) #########
		if ( $analysisId ) {

			my $allSh = Publication->extractSoftwareHardwareFromCve( $analysis->{idstring} );

			my ( @platforms, @products, @platformIds, @productIds);
			
			foreach my $item ( @$allSh ) {
				if ( $item->{cpe_id} =~ /^cpe:\/o/i ) {
					push @platforms, $item;
					push @platformIds, $item->{id};
				} else {
					push @products, $item;
					push @productIds, $item->{id};
				}
			}
			
			$vars->{platforms} = \@platforms;
		 	$vars->{software_hardware} = \@products; 

			if ( @platformIds ) {
				$vars->{platforms_text} = Publication->listSoftwareHardware(ids => \@platformIds, columns => ['producer', 'name', 'version']);
			}
	
			if ( @productIds ) {
				$vars->{products_text} = Publication->listSoftwareHardware(ids => \@productIds, columns => ['producer', 'name']);
	
				$vars->{versions_text} = Publication->listSoftwareHardware(ids => \@productIds, columns => ['version']);
			} 
		}
		
		######### TAB UPDATE / SUMMARY / SOURCE / TLPAMBER #########
		my @templates;
		Template->getTemplate( type => $settings->{usableTypeIds} );
		while ( Template->nextObject() ) {
			my $tpl = Template->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;
			}
		}
	
		$vars->{advisory_templates} = \@templates;
		
		######### TAB LINKS #########
		$vars->{links} = Publication->getItemLinks( analysis_id => $analysisId );
				
		######### TAB PREVIEW #########
				
		$vars->{isNewAdvisory} = 1;
		
		my $dialogContent = Template->processTemplate( 'write_advisory_forward.tt', $vars, 1 );
		return { dialog => $dialogContent };
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}	
}

sub openDialogForwardDetails {
	my ( %kvArgs ) = @_;
	my ( $vars );
	
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( rightOnParticularization( $typeName ) && right('write') ) {
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
		my $settings = getAdvisoryForwardSettings();
		my $publicationId = $kvArgs{id};
		
		my $advisory = Publication->getPublicationDetails( table => 'publication_advisory_forward', 'publication_advisory_forward.publication_id' => $publicationId );
		$vars->{advisory} = $advisory;
	
		$vars->{pub_type} = ( $advisory->{version} > 1.00 ) ? 'forward_update' : 'forward';
		$vars->{isUpdate} = ( $advisory->{version} > 1.00 ) ? 1 : 0;

		if ( $advisory->{ids} =~ /CVE/ ) {
			my $oTaranisConfigurationCVE = Taranis::Configuration::CVE->new( Config );
			my %uniqueCVE;
			foreach ( split( ",", $advisory->{ids} ) ) {
				my $cveID = $_;
				$cveID =~ s/\s//g;
				if ( $cveID =~ /^CVE.*/i && !exists( $uniqueCVE{ uc($cveID) } ) ) {
					$uniqueCVE{ uc( $cveID ) } = 1;
				}
			}
			
			$vars->{cveList} = $oTaranisConfigurationCVE->getCVE( identifier => [ keys( %uniqueCVE ) ] );
		}

		########## TAB GENERAL ######### 	
		my $govcertId = ( $advisory->{govcertid} ) ? $advisory->{govcertid} : $settings->{advisoryPrefix} . '-' . nowstring(6) . '-' . $settings->{x};
		my $advisoryVersion = ( $advisory->{version} =~ /\d\.\d9/ ) ? $advisory->{version} . '0' : $advisory->{version};
	
		$vars->{advisory_heading} = $govcertId .': '. $advisory->{title};
		$vars->{advisory_id} = $govcertId;
		$vars->{advisory_version} = $advisoryVersion;
		$vars->{author}	= Users->getUser( $advisory->{created_by} )->{fullname};
	
		@{ $vars->{damage_description} } = $oTaranisDamageDescription->getDamageDescription();
		my @damageIds = Publication->getLinkedToPublicationIds( 
			table => 'advisory_forward_damage',
			select_column => 'damage_id',
			advisory_forward_id => $advisory->{id}
		);
				
		for ( my $i = 0; $i < @{ $vars->{damage_description} }; $i++ ) {
			for ( my $j = 0; $j < @damageIds; $j++ ) {
				if ( $vars->{damage_description}->[$i]->{id} eq $damageIds[$j] ) {
					$vars->{damage_description}->[$i]->{selected} = 1;
				}
			}
		}
		
		########## TAB PLATFORMS #########
		Publication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => 'softhard_id' },
			join_table_2 => { software_hardware => 'id' },
			'pu.id' => $advisory->{publication_id}
		);
		
		my @platforms;						 
		while ( Publication->nextObject() ) {
			push @platforms, Publication->getObject() ;
		}
			
		for ( my $i = 0; $i < @platforms; $i++ ) {
			$platforms[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $platforms[$i]->{id} }, 'soft_hard_usage' );
			$platforms[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $platforms[$i]->{type} )->{description};
		}
		
		$vars->{platforms} = \@platforms;
		$vars->{platforms_text} = $advisory->{platforms_text};
	
		########## TAB PRODUCTS #########
		Publication->getLinkedToPublication(
			join_table_1 => { product_in_publication => 'softhard_id' },
			join_table_2 => { software_hardware => 'id'	},
			'pu.id' => $advisory->{publication_id}
		);
		
		my @products;						 
		while ( Publication->nextObject() ) {
			push @products, Publication->getObject() ;
		}
	
		for ( my $i = 0; $i < @products; $i++ ) {
			$products[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $products[$i]->{id} }, 'soft_hard_usage' );
			$products[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $products[$i]->{type} )->{description};
		}														 
		$vars->{software_hardware} = \@products;
		$vars->{products_text} = $advisory->{products_text};
		$vars->{versions_text} = $advisory->{versions_text};
		
		########## TABS UPDATE / SUMMARY / SOURCE / TLPAMBER #########
		my @templates;
		Template->getTemplate( type => $settings->{usableTypeIds} );
		while ( Template->nextObject() ) {
			my $tpl = Template->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;
			}
		}
			
		$vars->{advisory_templates} = \@templates;

		########## TAB ATTACHMENTS #########
		
		$vars->{attachments} = Publication->getPublicationAttachments( publication_id => $advisory->{publication_id} );
		
		########## TAB LINKS #########
			
		$advisory->{hyperlinks} =~ s/\r//g;
		$advisory->{hyperlinks} =~ s/\n+/\n/g;
	
		@{ $vars->{links} } = split( "\n", $advisory->{hyperlinks} ); 
			
		########## TAB PREVIEW #########
	
		$vars->{show_statuschange_buttons} = (
				!( 
					$advisory->{damage} == 3 
					&& $advisory->{probability} == 3 
					&& !$settings->{publishLL}
				)
				&& $advisory->{status} != 3
			)
			? 1 : 0;
		
		$vars->{publishLL} = $settings->{publishLL};
		
		### SET opened_by OR RETURN locked = 1 ###
		if ( my $opened_by = Publication->isOpenedBy( $advisory->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $opened_by->{fullname};
		} elsif( right('write') ) {
			if ( Publication->openPublication( sessionGet('userid'), $advisory->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}
		$vars->{isNewAdvisory} = 0;

		my $dialogContent = Template->processTemplate( 'write_advisory_forward.tt', $vars, 1 );	
		return { 
			dialog => $dialogContent,
			params => { 
				publicationid => $publicationId,
				isLocked => $vars->{isLocked},
				isUpdate => $vars->{isUpdate}
			}
		};	
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}	
}

sub openDialogUpdateForward {
	my ( %kvArgs ) = @_;
	my $vars;

	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( rightOnParticularization( $typeName ) && $writeRight ) {
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
		
		my $settings = getAdvisoryForwardSettings();
		
		my $userId = sessionGet('userid'); 

		my $advisory = Publication->getPublicationDetails( 
			table => "publication_advisory_forward",
			"publication_advisory_forward.publication_id" => $publicationId
		);

		$advisory->{update} = "";
		$vars->{advisory} = $advisory;

		########## TAB GENERAL ######### 	
			
		my $advisoryVersion = ( $advisory->{version} =~ /\d\.\d9/ ) ? $advisory->{version} + 0.01 . "0" : $advisory->{version} + 0.01;

		$vars->{advisory_heading} = $advisory->{govcertid} .": ". $advisory->{title};
		$vars->{advisory_id} = $advisory->{govcertid};
		$vars->{advisory_version} = $advisoryVersion;
		$vars->{author} = Users->getUser( $userId )->{fullname};
		$vars->{date_created} = nowstring(9);
		$vars->{analysis_id} = $kvArgs{analysisId};
		
		### IDS ###
		my %ids;

		if ( $advisory->{ids} =~ /CVE/ ) {
			my $oTaranisConfigurationCVE = Taranis::Configuration::CVE->new( Config );
			my %uniqueCVE;
			foreach ( split( ",", $advisory->{ids} ) ) {
				my $cveID = $_;
				$cveID =~ s/\s//g;
				if ( $cveID =~ /^CVE.*/i && !exists( $uniqueCVE{ uc($cveID) } ) ) {
					$uniqueCVE{ uc( $cveID ) } = 1;
				}
				if ( $cveID =~ /^CVE.*/i ) {
					$ids{$_} = { 'new' => 0 };
				}
			}
			$vars->{cveList} = $oTaranisConfigurationCVE->getCVE( identifier => [ keys( %uniqueCVE ) ] );
		}

		$vars->{cve_id} = sortCVEString( join(", ",  keys %ids ) );

		# for tab platforms & products, create an array with the new CVE-IDS
		my @newCveIds;
		foreach my $id ( keys %ids ) {
			if ( $ids{$id}->{'new'} && $id =~ /^CVE.*/i) {
				push @newCveIds, $id;
			}
		}

		### DAMAGE DESCRIPTION ###
		@{ $vars->{damage_description} } = $oTaranisDamageDescription->getDamageDescription();
		my @damageIds = Publication->getLinkedToPublicationIds( 
			table => "advisory_forward_damage",
			select_column => "damage_id",
			advisory_forward_id => $advisory->{id}
		);

		for ( my $i = 0; $i < @{ $vars->{damage_description} }; $i++ ) {
			for ( my $j = 0; $j < @damageIds; $j++ ) {
				if ( $vars->{damage_description}->[$i]->{id} eq $damageIds[$j] ) {
					$vars->{damage_description}->[$i]->{selected} = 1;
				}
			}
		}
			
		########## TABS PLATFORMS  & PRODUCTS #########
		my ( @platforms, @products, @platformIds, @productIds);
		my ( %uniquePlatforms, %uniqueProducts );

		$vars->{platforms_text} = $advisory->{platforms_text};
		$vars->{products_text} = $advisory->{products_text};
		$vars->{versions_text} = $advisory->{versions_text};

		# current platforms taken from previous version
		Publication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => "softhard_id" },
			join_table_2 => { software_hardware => "id" },
			"pu.id" => $advisory->{publication_id}
		);

		while ( Publication->nextObject() ) {
			my $platform = Publication->getObject();
			push @platforms, $platform;
			$uniquePlatforms{ $platform->{cpe_id} } = 1;
		}
	
		# current products taken from previous version
		Publication->getLinkedToPublication(
			join_table_1 => { product_in_publication => "softhard_id" },
			join_table_2 => { software_hardware => "id" },
			"pu.id" => $advisory->{publication_id}
		);

		while ( Publication->nextObject() ) {
			my $product = Publication->getObject();
			push @products, $product;
			$uniqueProducts{ $product->{cpe_id} } = 1;
		}

		# possible new platforms and products depending on new CVE-IDS
		if ( @newCveIds ) {
			my $allSh = Publication->extractSoftwareHardwareFromCve( "@newCveIds" );
			foreach my $item ( @$allSh ) {
				if ( $item->{cpe_id} =~ /^cpe:\/o/i ) {
					if ( !exists( $uniquePlatforms{ $item->{cpe_id} } ) ) {
						push @platforms, $item;
						push @platformIds, $item->{id};
					}
				} else {
					if ( !exists( $uniqueProducts{ $item->{cpe_id} } ) ) {
						push @products, $item;
						push @productIds, $item->{id};
					}
				}
			}
				
			# add the platforms and products to the preview text of the previous advisory version
			if ( @platformIds ) {
				$vars->{platforms_text} .= "\n" . Publication->listSoftwareHardware(ids => \@platformIds, columns => ['producer', 'name', 'version']); 
			}
				
			if ( @productIds ) {
				$vars->{products_text} .= "\n" . Publication->listSoftwareHardware(ids => \@productIds, columns => ['producer', 'name']);

				$vars->{versions_text} .= "\n" . Publication->listSoftwareHardware(ids => \@productIds, columns => 'version');
			} 
		}
	
		for ( my $i = 0; $i < @platforms; $i++ ) {
			$platforms[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $platforms[$i]->{type} )->{description};
		}
			
		$vars->{platforms} = \@platforms;
	
		for ( my $i = 0; $i < @products; $i++ ) {
			$products[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $products[$i]->{type} )->{description};
		}														 
		$vars->{software_hardware} = \@products;
	
		########## TABS UPDATE / SUMMARY / SOURCE / TLPAMBER #########
		my @templates;
		Template->getTemplate( type => $settings->{usableTypeIds} );
		while ( Template->nextObject() ) {
			my $tpl = Template->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;	
			}
		}
			
		$vars->{advisory_templates} = \@templates;

		########## TAB ATTACHMENTS #########
		
		$vars->{attachments} = Publication->getPublicationAttachments( publication_id => $advisory->{publication_id} );

		########## TAB LINKS #########
			
		my @linksPreviousVersion = split( "\n", $advisory->{hyperlinks} );
		my @itemLinks = @{ Publication->getItemLinks( publication_id => $advisory->{publication_id} ) };
		my @itemLinksNewAnalysis; 
		if ( $kvArgs{analysisId} =~ /^\d+$/i ) {
			@itemLinksNewAnalysis = @{ Publication->getItemLinks( analysis_id => $kvArgs{analysisId} ) };
		}
		
		my %uniqueLinks;
		foreach ( @linksPreviousVersion ) {
			$uniqueLinks{$_}->{address} = $_;
			$uniqueLinks{$_}->{check} = 1; 
		}
			
		foreach ( @itemLinks ) {
			if ( !exists( $uniqueLinks{$_} ) ) {
				$uniqueLinks{$_}->{address} = $_;
				$uniqueLinks{$_}->{check} = 0;
			} 
		}
		
		foreach ( @itemLinksNewAnalysis ) {
			if ( !exists( $uniqueLinks{$_} ) ) {
				$uniqueLinks{$_}->{address} = $_;
				$uniqueLinks{$_}->{check} = 0;
			} 
		}
			
		$vars->{links} = \%uniqueLinks;
			
		$vars->{uncheck_new_links} = 1;
		$vars->{isNewAdvisory} = 1;
		$vars->{isUpdate} = 1;
		$vars->{update_notes} = $advisory->{notes};
		
		my $dialogContent = Template->processTemplate( 'write_advisory_forward.tt', $vars, 1 );
		return { 
			dialog => $dialogContent,
			params => {	publicationid => $advisory->{publication_id} }
		};	
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}	
	
}

sub openDialogPreviewForward {
	my ( %kvArgs ) = @_;
	my $vars;
	
	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $executeRight = right('execute');
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( rightOnParticularization( $typeName ) ) {
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
		my $us = Taranis::Users->new( Config );
		my $userId = sessionGet('userid');
		my $settings = getAdvisoryForwardSettings();
		
		my $advisory = Publication->getPublicationDetails( 
			table => "publication_advisory_forward",
			"publication_advisory_forward.publication_id" => $publicationId
		);

		$vars->{is_updated} = ( $advisory->{replacedby_id} ) ? 1 : 0; 
		
		$vars->{pub_type} = ( $advisory->{version} > 1.00 ) ? "forward_update" : "forward";
		
		$vars->{created_by_name} = ( $advisory->{created_by} ) ? $us->getUser( $advisory->{created_by}, 1 )->{fullname} : undef;
		$vars->{approved_by_name} = ( $advisory->{approved_by} ) ? $us->getUser( $advisory->{approved_by}, 1 )->{fullname} : undef;
		$vars->{published_by_name} = ( $advisory->{published_by} ) ? $us->getUser( $advisory->{published_by}, 1 )->{fullname} : undef; 
		my $userIsAuthor = ( $advisory->{created_by} eq sessionGet('userid') ) ? 1 : 0;

		$vars->{advisory} = $advisory;
		$vars->{attachments} = Publication->getPublicationAttachments( publication_id => $advisory->{publication_id} );		
		
		### SET opened_by OR RETURN locked = 1 ###
		if ( my $opened_by = Publication->isOpenedBy( $advisory->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $opened_by->{fullname};
		} elsif( $writeRight || $executeRight ) {
			Publication->openPublication( $userId, $advisory->{publication_id} );
			$vars->{isLocked} = 0;
		} else {
			$vars->{isLocked} = 1;
		}
		
		my $noStatusChangeButtons = 0;
		if ( $advisory->{damage} == 3 && $advisory->{probability} == 3 && !$settings->{publishLL} ) {
			$noStatusChangeButtons = 1;
		}

		# PLATFORMS
		Publication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => 'softhard_id' },
			join_table_2 => { software_hardware => 'id' },
			'pu.id' => $advisory->{publication_id}
		);
		
		my @platforms;						 
		while ( Publication->nextObject() ) {
			push @platforms, Publication->getObject() ;
		}
			
		for ( my $i = 0; $i < @platforms; $i++ ) {
			$platforms[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $platforms[$i]->{id} }, 'soft_hard_usage' );
			$platforms[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $platforms[$i]->{type} )->{description};
		}
		
		$vars->{platforms} = \@platforms;
		$vars->{platforms_text} = $advisory->{platforms_text};
	
		# PRODUCTS
		Publication->getLinkedToPublication(
			join_table_1 => { product_in_publication => 'softhard_id' },
			join_table_2 => { software_hardware => 'id'	},
			'pu.id' => $advisory->{publication_id}
		);
		
		my @products;						 
		while ( Publication->nextObject() ) {
			push @products, Publication->getObject() ;
		}
	
		for ( my $i = 0; $i < @products; $i++ ) {
			$products[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $products[$i]->{id} }, 'soft_hard_usage' );
			$products[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $products[$i]->{type} )->{description};
		}
		$vars->{products} = \@products;

		my $dialogContent = Template->processTemplate( 'write_advisory_preview.tt', $vars, 1 );
		return { 
			dialog => $dialogContent,
			params => { 
				publicationid => $publicationId,
				isLocked => $vars->{isLocked},
				executeRight => $executeRight,
				userIsAuthor => $userIsAuthor,
				currentStatus => $advisory->{status},
				noStatusChangeButtons => $noStatusChangeButtons,
				writeRight => $writeRight
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}
}

sub saveNewForward {
	my ( %kvArgs ) = @_;

	my ( $message, $publicationId, $advisoryId );
	my $saveOk = 0;
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( rightOnParticularization($typeName) && right('write') ) {
		my $settings = getAdvisoryForwardSettings();
		
		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;

		my $typeId = Publication->getPublicationTypeId($typeName);
		my $userId = sessionGet('userid');
		 
		my $analysisId = $kvArgs{analysisId} || undef;
	
		my $advisoryIdentifier = ( $kvArgs{advisory_id} ) ? $kvArgs{advisory_id} : $settings->{advisoryPrefix} . '-' . nowstring(6) . '-' . $settings->{x};
		my $advisoryVersion = ( exists( $kvArgs{advisory_version} ) ) ? $kvArgs{advisory_version} : '1.00'; 

		my $uploadedFiles = getUploadedFiles();

		my ( @screenshotURLs, @screenshotDescriptions );
		if($kvArgs{screenshot_url}) {
			@screenshotURLs = flat $kvArgs{screenshot_url};
			@screenshotDescriptions = flat $kvArgs{screenshot_description};
		}

		withTransaction {
			Publication->addPublication(
				title => substr( $kvArgs{title}, 0, 50 ),
				created_by => $userId,
				type => $typeId,
				status => '0'
			);
			$publicationId = Publication->{dbh}->getLastInsertedId('publication');

			Publication->linkToPublication(
					table => 'analysis_publication',
					analysis_id => $analysisId,
					publication_id => $publicationId
			) if $analysisId;

			Publication->linkToPublication(
				table => 'publication_advisory_forward',
				publication_id => $publicationId,
				version => $advisoryVersion,
				govcertid => $advisoryIdentifier,
				title => $kvArgs{title},
				probability => $kvArgs{probability},
				damage => $kvArgs{damage},
				ids => sortCVEString( $kvArgs{cve_id} ),
				platforms_text => $kvArgs{platforms_txt},
				versions_text => $kvArgs{versions_txt},
				products_text => $kvArgs{products_txt},
				hyperlinks => $advisoryLinks,
				tlpamber => $kvArgs{tab_tlpamber_txt},
				summary => $kvArgs{tab_summary_txt},
				source => $kvArgs{tab_source_txt},
				ques_dmg_infoleak => $kvArgs{dmg_infoleak},
				ques_dmg_privesc => $kvArgs{dmg_privesc},
				ques_dmg_remrights => $kvArgs{dmg_remrights},
				ques_dmg_codeexec => $kvArgs{dmg_codeexec},
				ques_dmg_dos => $kvArgs{dmg_dos},
				ques_dmg_deviation => $kvArgs{dmg_deviation},
				ques_pro_solution => $kvArgs{pro_solution},
				ques_pro_expect => $kvArgs{pro_expect},
				ques_pro_exploited => $kvArgs{pro_exploited},
				ques_pro_userint => $kvArgs{pro_userint},
				ques_pro_complexity => $kvArgs{pro_complexity},
				ques_pro_credent => $kvArgs{pro_credent},
				ques_pro_access => $kvArgs{pro_access},
				ques_pro_details => $kvArgs{pro_details},
				ques_pro_exploit => $kvArgs{pro_exploit},
				ques_pro_standard => $kvArgs{pro_standard},
				ques_pro_deviation => $kvArgs{pro_deviation} 
			);

			$advisoryId = Publication->{dbh}->getLastInsertedId('publication_advisory_forward');

			#### link products, platforms and damage descriptions to publication ####
			foreach my $productID (flat $kvArgs{pd_left_column}) {
				Publication->linkToPublication(
					table => 'product_in_publication',
					softhard_id => $productID,
					publication_id => $publicationId
				);
			}

			foreach my $platformID (flat $kvArgs{pf_left_column}) {
				Publication->linkToPublication(
					table => 'platform_in_publication',
					softhard_id => $platformID,
					publication_id => $publicationId
				);
			}

			foreach my $damageDescriptionID (flat $kvArgs{damage_description}) {
				Publication->linkToPublication(
					table => 'advisory_forward_damage',
					damage_id => $damageDescriptionID,
					advisory_forward_id => $advisoryId
				);
			}

			#create screenshot and add to publication
			for ( my $i = 0; $i < @screenshotURLs; $i++ ) {
				
				if ( my $screenshot = takeScreenshotFromURL( $screenshotURLs[$i] ) ) {

					$screenshot->{filename} = ( $screenshotDescriptions[$i] )
						? $screenshotDescriptions[$i] . ".png"
						: $screenshotURLs[$i] . ".png";
					
					$screenshot->{publication_id} = $publicationId;

					Publication->addFileToPublication( %$screenshot );
				} else {
					$message = 'Could not create a screenshot';
				}
			}

			# store uploaded files in database as large objects
			foreach my $uploadedFile ( @$uploadedFiles ) {
				$uploadedFile->{publication_id} = $publicationId;
				Publication->addFileToPublication( %$uploadedFile );
			}
		};

		if ( !$message ) {
			my $advisoryType = ( $advisoryVersion > 1 ) ? 'forward_update' : 'forward';
			my $previewText = Template->processPreviewTemplate( 'advisory', $advisoryType, $advisoryId, $publicationId, 71 );
	
			Publication->setPublication( id => $publicationId, contents => $previewText );
		}
			
		$saveOk = 1 if ( !$message );
	
	} else {
		$message = 'No persmission';
	}

	if ( $saveOk ) {
		setUserAction( action => 'add advisory', comment => "Added advisory '$kvArgs{title}'" );
	} else {
		setUserAction( action => 'add advisory', comment => "Got error '$message' while trying to add advisory '$kvArgs{title}'" );
	}

	return {
		params => { 
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId,
			isUpdate => 0
		}
	};
}

sub saveForwardDetails {
	my ( %kvArgs ) = @_;

	my ( $advisory );
	my $saveOk = 0;
	my $publicationId = $kvArgs{pub_id};
	my $typeName = Config->publicationTemplateName(advisory => 'forward');

	if ( rightOnParticularization( $typeName ) && right('write') ) {
	
		my $advisoryId = $kvArgs{adv_id};
	
		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;

		my @productIds = Publication->getLinkedToPublicationIds( 
			table => 'product_in_publication',
			select_column => 'softhard_id',
			publication_id => $publicationId
		);
	
		my @products = flat $kvArgs{pd_left_column};
		my ( $newProducts, $deleteProducts ) = addAndDelete( \@productIds, \@products );
	
		my @platformIds = Publication->getLinkedToPublicationIds( 
			table => 'platform_in_publication',
			select_column => 'softhard_id',
			publication_id => $publicationId
		);
	
		my @platforms = flat $kvArgs{pf_left_column};
		my ( $newPlatforms, $deletePlatforms ) = addAndDelete( \@platformIds, \@platforms );
		
		my @damageDescriptionIds = Publication->getLinkedToPublicationIds( 
			table => 'advisory_forward_damage',
			select_column => 'damage_id',
			advisory_forward_id => $advisoryId
		);
	
		my @damageDescriptions = flat $kvArgs{damage_description};
		my ( $newDamageDescriptions, $deleteDamageDescriptions ) = addAndDelete( \@damageDescriptionIds, \@damageDescriptions );
		
		my ( @screenshotURLs, @screenshotDescriptions );
		if($kvArgs{screenshot_url}) {
			@screenshotURLs = flat $kvArgs{screenshot_url};
			@screenshotDescriptions = flat $kvArgs{screenshot_description};
		}
		
		# newly uploaded files
		my $uploadedFiles = getUploadedFiles();

		# current uploaded files which are already linked to publication
		my $currentAttachments = Publication->getPublicationAttachments( publication_id => $publicationId );
		
		my @deleteAttachments;
		if ( $kvArgs{publication_attachment} ) {
			my @submittedAttachments = flat $kvArgs{publication_attachment};
			my %currentAttachmentsMap = map { $_->{id} => 1 } @$currentAttachments;
			
			foreach my $submittedAttachment ( @submittedAttachments ) {
				if ( exists( $currentAttachmentsMap{$submittedAttachment} ) ) {
					delete $currentAttachmentsMap{$submittedAttachment};
				}
			}
			
			@deleteAttachments = keys %currentAttachmentsMap;
			
		} elsif ( $currentAttachments ) {
			foreach my $attachment ( @$currentAttachments ) {
				push @deleteAttachments, $attachment->{id};
			}
		}
		
		withTransaction {
			Publication->setPublicationDetails(
				table => 'publication_advisory_forward',
				where => { id => $advisoryId },
				title => $kvArgs{title},
				probability => $kvArgs{probability},
				damage => $kvArgs{damage},
				ids => sortCVEString( $kvArgs{cve_id} ),
				hyperlinks => $advisoryLinks,
				platforms_text => $kvArgs{platforms_txt},
				versions_text => $kvArgs{versions_txt},
				products_text => $kvArgs{products_txt},
				tlpamber => $kvArgs{tab_tlpamber_txt},
				summary => $kvArgs{tab_summary_txt},
				source => $kvArgs{tab_source_txt},
				update => $kvArgs{tab_update_txt},
				ques_dmg_infoleak => $kvArgs{dmg_infoleak},
				ques_dmg_privesc => $kvArgs{dmg_privesc},
				ques_dmg_remrights => $kvArgs{dmg_remrights},
				ques_dmg_codeexec => $kvArgs{dmg_codeexec},
				ques_dmg_dos => $kvArgs{dmg_dos},
				ques_dmg_deviation => $kvArgs{dmg_deviation},
				ques_pro_solution => $kvArgs{pro_solution},
				ques_pro_expect => $kvArgs{pro_expect},
				ques_pro_exploited => $kvArgs{pro_exploited},
				ques_pro_userint => $kvArgs{pro_userint},
				ques_pro_complexity => $kvArgs{pro_complexity},
				ques_pro_credent => $kvArgs{pro_credent},
				ques_pro_access => $kvArgs{pro_access},
				ques_pro_details => $kvArgs{pro_details},
				ques_pro_exploit => $kvArgs{pro_exploit},
				ques_pro_standard => $kvArgs{pro_standard},
				ques_pro_deviation => $kvArgs{pro_deviation}
			);

			#### link new products, platforms and damage descriptions to publication ####
			foreach my $productID ( @$newProducts ) {
				Publication->linkToPublication(
					table => 'product_in_publication',
					softhard_id => $productID,
					publication_id => $publicationId
				);
			}

			foreach my $platformID ( @$newPlatforms ) {
				Publication->linkToPublication(
					table => 'platform_in_publication',
					softhard_id => $platformID,
					publication_id => $publicationId
				);
			}

			foreach my $damageDescriptionID ( @$newDamageDescriptions ) {
				Publication->linkToPublication(
					table => 'advisory_forward_damage',
					damage_id => $damageDescriptionID,
					advisory_forward_id => $advisoryId
				);
			}

			#### unlink products, platforms and damage descriptions from publication ####
			foreach my $productID ( @$deleteProducts ) {
				Publication->unlinkFromPublication(
					table => 'product_in_publication',
					softhard_id => $productID,
					publication_id => $publicationId
				);
			}

			foreach my $platformID ( @$deletePlatforms ) {
				Publication->unlinkFromPublication(
					table => 'platform_in_publication',
					softhard_id => $platformID,
					publication_id => $publicationId
				);
			}

			foreach my $damageDescriptionID ( @$deleteDamageDescriptions ) {
				Publication->unlinkFromPublication(
					table => 'advisory_forward_damage',
					damage_id => $damageDescriptionID,
					advisory_forward_id => $advisoryId
				);
			}

			#create screenshot and add to publication
			for ( my $i = 0; $i < @screenshotURLs; $i++ ) {

				my $screenshot = takeScreenshotFromURL( $screenshotURLs[$i] )
					or croak 'Could not create a screenshot';

				$screenshot->{filename} = ( $screenshotDescriptions[$i] )
					? $screenshotDescriptions[$i] . ".png"
					: $screenshotURLs[$i] . ".png";

				$screenshot->{publication_id} = $publicationId;

				Publication->addFileToPublication( %$screenshot );
			}

			# store uploaded files in database as large objects
			if ( @$uploadedFiles ) {
				foreach my $uploadedFile ( @$uploadedFiles ) {
					$uploadedFile->{publication_id} = $publicationId;
					Publication->addFileToPublication( %$uploadedFile );
				}
			}

			# delete removed attachments
			foreach my $deleteAttachment ( @deleteAttachments ) {
				Publication->unlinkFromPublication(
					table => 'publication_attachment',
					id => $deleteAttachment
				);
			}
		};

		$advisory = Publication->getPublicationDetails( 
				table => 'publication_advisory_forward',
				'publication_advisory_forward.id' => $advisoryId 
			);
			
		my $publicationType = ( $advisory->{version} > 1.00 ) ? 'forward_update' : 'forward';
			
		my $previewText = Template->processPreviewTemplate( 'advisory', $publicationType, $advisoryId, $publicationId, 71 );
	
		Publication->setPublication( id => $publicationId, contents => $previewText );

		if ( !exists( $kvArgs{skipUserAction} ) ) {
			setUserAction( action => 'edit advisory', comment => "Edited advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");
		}
	} else {
		# No permission.
		die 403;
	}

	return {
		params => {
			saveOk => 1,
			publicationId => $publicationId
		}
	};
}

sub saveUpdateForward {
	my ( %kvArgs ) = @_;

	my ( $newPublicationId );
	my $publicationId = $kvArgs{pub_id};
	my $advisoryId = $kvArgs{adv_id};
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( rightOnParticularization( $typeName ) && right('write') ) {
	
		my $userId = sessionGet('userid'); 
		
		my $advisory = Publication->getPublicationDetails( 
			table => "publication_advisory_forward",
			"publication_advisory_forward.id" => $advisoryId
		);
		
		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;
			
		my $advisoryVersion = ( $advisory->{version} =~ /\d\.\d9/ ) ? $advisory->{version} + 0.01 . "0" : $advisory->{version} + 0.01;
			
		my @analysisIds = Publication->getLinkedToPublicationIds( 
			table => "analysis_publication",
			select_column => "analysis_id",
			publication_id => $publicationId
		);

		my ( @screenshotURLs, @screenshotDescriptions );
		if ( $kvArgs{screenshot_url} ) {
			@screenshotURLs = flat $kvArgs{screenshot_url};
			@screenshotDescriptions = flat $kvArgs{screenshot_description};
		}

		my $uploadedFiles = getUploadedFiles();
		my @submittedAttachments = flat $kvArgs{publication_attachment};

		foreach my $submittedAttachment ( @submittedAttachments ) {
			next if ( !$submittedAttachment );
			my $attachment = Publication->getPublicationAttachments( id => $submittedAttachment );
			if ( $attachment ) {
				my $attachmentToAdd = {};
				$attachment = $attachment->[0];
				my $file;
				my $mode = Publication->{dbh}->{dbh}->{pg_INV_READ};
				
				withTransaction {
					my $lobj_fd = Publication->{dbh}->{dbh}->func( $attachment->{object_id}, $mode, 'lo_open');
		
					Publication->{dbh}->{dbh}->func( $lobj_fd, $file, $attachment->{file_size}, 'lo_read' );
				};
				
				$attachmentToAdd->{binary} = $file;
				$attachmentToAdd->{filename} = $attachment->{filename};
				$attachmentToAdd->{mimetype} = $attachment->{mimetype};
				push @$uploadedFiles, $attachmentToAdd;
			}
		}

		withTransaction {
			Publication->addPublication(
				title => substr( $kvArgs{title}, 0, 50 ),
				created_by => $userId,
				type => $advisory->{type},
				status => "0"
			);
			$newPublicationId = Publication->{dbh}->getLastInsertedId("publication");

			Publication->linkToPublication(
				table => "publication_advisory_forward",
				publication_id => $newPublicationId,
				govcertid => $advisory->{govcertid},
				version => $advisoryVersion,
				title => $kvArgs{title},
				probability => $kvArgs{probability},
				damage => $kvArgs{damage},
				ids => sortCVEString( $kvArgs{cve_id} ),
				platforms_text => $kvArgs{platforms_txt},
				versions_text => $kvArgs{versions_txt},
				products_text => $kvArgs{products_txt},
				hyperlinks => $advisoryLinks,
				tlpamber => $kvArgs{tab_tlpamber_txt},
				summary => $kvArgs{tab_summary_txt},
				source => $kvArgs{tab_source_txt},
				update => $kvArgs{tab_update_txt},
				ques_dmg_infoleak => $kvArgs{dmg_infoleak},
				ques_dmg_privesc => $kvArgs{dmg_privesc},
				ques_dmg_remrights => $kvArgs{dmg_remrights},
				ques_dmg_codeexec => $kvArgs{dmg_codeexec},
				ques_dmg_dos => $kvArgs{dmg_dos},
				ques_dmg_deviation => $kvArgs{dmg_deviation},
				ques_pro_solution => $kvArgs{pro_solution},
				ques_pro_expect => $kvArgs{pro_expect},
				ques_pro_exploited => $kvArgs{pro_exploited},
				ques_pro_userint => $kvArgs{pro_userint},
				ques_pro_complexity => $kvArgs{pro_complexity},
				ques_pro_credent => $kvArgs{pro_credent},
				ques_pro_access => $kvArgs{pro_access},
				ques_pro_details => $kvArgs{pro_details},
				ques_pro_exploit => $kvArgs{pro_exploit},
				ques_pro_standard => $kvArgs{pro_standard},
				ques_pro_deviation => $kvArgs{pro_deviation} 
			);

			my $newAdvisoryId = Publication->{dbh}->getLastInsertedId("publication_advisory_forward");

			foreach my $productID (flat $kvArgs{pd_left_column}) {
				Publication->linkToPublication(
					table => "product_in_publication",
					softhard_id => $productID,
					publication_id => $newPublicationId
				);
			} 

			foreach my $platformID (flat $kvArgs{pf_left_column}) {
				Publication->linkToPublication(
					table => "platform_in_publication",
					softhard_id => $platformID,
					publication_id => $newPublicationId
				);
			}

			foreach my $damageDescriptionID (flat $kvArgs{damage_description}) {
				Publication->linkToPublication(
					table => "advisory_forward_damage",
					damage_id => $damageDescriptionID,
					advisory_forward_id => $newAdvisoryId
				);
			}

			if ( $kvArgs{analysisId} =~ /^\d+$/ ) {
				Publication->linkToPublication(
					table => "analysis_publication",
					analysis_id => $kvArgs{analysisId},
					publication_id => $newPublicationId
				);
			}

			foreach my $ana_id (grep $_ ne $kvArgs{analysisId}, @analysisIds) {
				Publication->linkToPublication(
					table => "analysis_publication",
					analysis_id => $ana_id,
					publication_id => $newPublicationId
				);
			}

			#create screenshot and add to publication
			for ( my $i = 0; $i < @screenshotURLs; $i++ ) {
				my $screenshot = takeScreenshotFromURL( $screenshotURLs[$i] )
					or croak 'Could not create a screenshot';

				$screenshot->{filename} = ( $screenshotDescriptions[$i] )
					? $screenshotDescriptions[$i] . ".png"
					: $screenshotURLs[$i] . ".png";
					
				$screenshot->{publication_id} = $newPublicationId;

				Publication->addFileToPublication( %$screenshot );
			}

			# store uploaded files in database as large objects
			foreach my $uploadedFile ( @$uploadedFiles ) {
				$uploadedFile->{publication_id} = $newPublicationId;
				Publication->addFileToPublication( %$uploadedFile );
			}

			my $previewText = Template->processPreviewTemplate( "advisory", "forward_update", $newAdvisoryId, $newPublicationId, 71 );
				
			Publication->setPublication( id => $newPublicationId, contents => $previewText );
			Publication->setPublication( id => $publicationId, replacedby_id => $newPublicationId );
		};
		
		setUserAction( action => 'update advisory', comment => "Created update on advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");

	} else {
		# No permission.
		die 403;
	}

	return {
		params => {
			saveOk => 1,
			publicationId => $newPublicationId,
			detailsId => $advisoryId,
			isUpdate => 1
		}
	};	
}

sub setForwardStatus {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;
	
	my $settings = getAdvisoryForwardSettings();
	my $publicationId = $kvArgs{publicationId};
	my $newStatus = $kvArgs{status};
	my $userId = sessionGet('userid'); 
	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	
	if ( 
		( rightOnParticularization( $typeName ) && right('write') )
		|| $newStatus =~ /^(0|1|2)$/ 
	) {

		my $advisory = Publication->getPublicationDetails( 
			table => 'publication_advisory_forward',
			'publication_advisory_forward.publication_id' => $publicationId 
		);

		my $currentStatus = $advisory->{status};
		if ((
				 ( $currentStatus eq '0' && $newStatus eq '1' ) || 
				 ( $currentStatus eq '1' && $newStatus eq '0' ) ||
				 ( $currentStatus eq '2' && $newStatus eq '0' ) ||
				 ( $currentStatus eq '1' && $newStatus eq '2' && $advisory->{created_by} ne $userId && right('execute') )
			 ) 
			 && ( !( $advisory->{damage} == 3 && $advisory->{probability} == 3 && !$settings->{publishLL} ))
		) {

			if ( $newStatus eq '2' ) {
				if ( !Publication->setPublication( 
						id => $publicationId, 
						status => $newStatus,
						approved_on => nowstring(10),
						approved_by => $userId 
					) 
				) {
				
				$message = Publication->{errmsg};
				
				} else {
					$saveOk = 1;
				}			
			} else {
				if ( !Publication->setPublication( 
						id => $publicationId,
						status => $newStatus,
						approved_on => undef,
						approved_by => undef 
					)
				) {
					$message = Publication->{errmsg};
				} else {
					$saveOk = 1;
				}
			}				
		} else {
			$message = "This status change action is not permitted.";
		}

		if ( $saveOk ) {
			setUserAction( action => 'change advisory status', comment => "Changed advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' from '" . Publication->{status}->{$currentStatus} . "' to '" . Publication->{status}->{$newStatus} . "'");
		} else {
			setUserAction( action => 'change advisory status', comment => "Got error '$message' while trying to change status of advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' from '" . Publication->{status}->{$currentStatus} . "' to '" . Publication->{status}->{$newStatus} . "'");
		}

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};
}

sub getForwardPreview {
	my ( %kvArgs ) = @_;

	my $settings = getAdvisoryForwardSettings();

	my $publicationId = $kvArgs{publicationId};
	my $advisoryId = $kvArgs{advisoryId};
	my $publicationType = $kvArgs{publicationType};
	my $previewText;
	
	$previewText = Template->processPreviewTemplate( "advisory", $publicationType, $advisoryId, $publicationId, 71 );	
	
	return {
		params => { 
	 		previewText => $previewText,
	 		publicationId => $publicationId
	 	}
	 };	
}

## HELPERS ##
sub getAdvisoryForwardSettings {
	my $settings = {};
	$settings->{advisoryPrefix} = Config->{advisory_prefix};
	$settings->{publishLL} = ( Config->{publish_LL_advisory} =~ /^yes$/ ) ? 1 : 0;
	
	my $advisoryIdLength = Config->{advisory_id_length};
	$advisoryIdLength = 3 if ( !$advisoryIdLength || $advisoryIdLength !~ /^\d+$/ );
	my $x = '';
	for ( my $i = 1; $i <= $advisoryIdLength; $i++ ) { $x .= 'X'; }
	$settings->{x} = $x;
	
	my $publicationTemplate = Taranis::Config::XMLGeneric->new( Config->{publication_templates}, 'email', 'templates');
	my %nonUsableTemplates;
	my @usableTemplateTypeNames;
	foreach my $val ( values %{$publicationTemplate->loadCollection()} ) {
		foreach ( %$val ) {
	
			if ( $_ =~ /^(email|update|taranis_xml|website|forward)$/ ) {
				push @usableTemplateTypeNames, $val->{$_};
			}		
			
			$nonUsableTemplates{ lc $val->{$_} } = 1 if ( $val->{$_} );
		}
	}
	$settings->{nonUsableTemplates} = \%nonUsableTemplates;
	$settings->{usableTypeIds} = Template->getTypeIds( @usableTemplateTypeNames );

	return $settings;
}

sub addAndDelete {
	my ( $currentIds, $inputIds ) = @_;

	my @new;
	my @delete;
	my %idsHash;

	foreach my $id (@$currentIds) {
		$idsHash{$id} = $id;
	}

	my %newIdsHash;
	foreach my $id ( @$inputIds ) {
		$newIdsHash{$id} = $id;
		if ( !exists( $idsHash{$id} ) ) {
			push( @new, $id );
		}
	}

	foreach my $id (@$currentIds) {
		if ( !exists( $newIdsHash{$id} ) ) { push( @delete, $id ) }
	}
	return \@new, \@delete;	
}

sub sortCVEString {
	my ( $cveString ) = @_;
	$cveString =~ s/ //g;
	return join( ', ', sort keys %{{ map { $_ => 1 } ( split( ",", uc $cveString ) ) }} );
}

sub getUploadedFiles {
	my @uploadedFiles;
	
		foreach my $file ( CGI->upload ) {
			next if ( !$file );
			my ( $memFile, $fh, %fileInfo );
			my $fhUploadedFile = CGI->upload( $file );

			open($fh, ">", \$memFile);
			binmode $fh;
			while(<$fhUploadedFile>) {
				print $fh $_ or return 0;
			}
			close $fh;
			
			$fileInfo{filename} = decode_utf8 $file;  # CGI->upload doesn't decode the filename for us.
			$fileInfo{binary} = $memFile;
			$fileInfo{mimetype} = CGI->upload_info( $file, 'mime' ); # MIME type of uploaded file

			push @uploadedFiles, \%fileInfo;
		}
		
		return \@uploadedFiles;
	}

sub takeScreenshotFromURL {
	my ( $url ) = @_;
	
	my %screenshotArgs = ( screenshot_module => Config->{screenshot_module} ); 
	$screenshotArgs{proxy_host} = Config->{proxy_host} if ( Config->{proxy_host} );
	$screenshotArgs{user_agent} = Config->{useragent} if ( Config->{useragent} );
	
	my $screenshot = Taranis::Screenshot->new( %screenshotArgs );
	
	if ( my $screenshot = $screenshot->takeScreenshot( siteAddress => $url ) ) {
		
		return {
			binary => $screenshot,
			mimetype => 'image/png'
		}
	}  else {
		return 0;
	}
}

1;
