#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:util flat val_int);
use Taranis::Database qw(withTransaction);
use Taranis::Error;
use Taranis::Template;
use Taranis::Publication;
use Taranis::Publication::Advisory;
use Taranis::Publication::EndOfDay;
use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Users qw();
use Taranis::Config;
use Taranis::Publish;
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);
use Taranis::FunctionalWrapper qw(Config Publication Publish Database);
use Taranis::Damagedescription;
use Taranis::SoftwareHardware;
use Taranis::Config::XMLGeneric;
use Taranis::Configuration::CVE;
use Taranis::Session qw(sessionGet);

use HTML::Entities;
use MIME::Parser;
use XML::LibXML::Simple qw(XMLin);
use Encode;

my @EXPORT_OK = qw(
	openDialogNewAdvisory openDialogAdvisoryDetails openDialogUpdateAdvisory openDialogPreviewAdvisory
	saveAdvisoryDetails saveNewAdvisory saveUpdateAdvisory openDialogAdvisoryNotificationDetails
	setReadyForReview setAdvisoryStatus getAdvisoryPreview openDialogImportAdvisory
	saveAdvisoryLateLinks
);

sub advisory_export {
	return @EXPORT_OK;
}

sub openDialogNewAdvisory {
	my ( %kvArgs ) = @_;
	my ( $vars, $idString, $analysis);

	my $oTaranisTemplate = Taranis::Template->new;

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {
		my $oTaranisAnalysis = Taranis::Analysis->new( Config );
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		my $oTaranisPublication = Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );

		my $settings = getAdvisorySettings();

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
		$vars->{author} = $oTaranisUsers->getUser( $userId )->{fullname};
		$vars->{date_created} = nowstring(9);
		$vars->{cve_id} = sortCVEString( $idString );

		######### TAB PLATFORM(s) & PRODUCT(s) #########
		if ( $analysisId ) {

			my $allSh = $oTaranisPublication->extractSoftwareHardwareFromCve( $analysis->{idstring} );

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
				$vars->{platforms_text} = $oTaranisPublication->listSoftwareHardware(ids => \@platformIds, columns => ['producer', 'name', 'version' ]);
			}

			if ( @productIds ) {
				$vars->{products_text} = $oTaranisPublication->listSoftwareHardware(ids => \@productIds, columns => ['producer', 'name' ]);

				$vars->{versions_text} = $oTaranisPublication->listSoftwareHardware(ids => \@productIds, columns => 'version');
			}
		}

		######### TAB UPDATE / SUMMARY / CONSEQUENCES / DESCRIPTION / SOLUTION / TLPAMBER #########
		my @templates;
		$oTaranisTemplate->getTemplate( type => $settings->{usableTypeIds} );
		while ( $oTaranisTemplate->nextObject() ) {
			my $tpl = $oTaranisTemplate->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;
			}
		}

		$vars->{advisory_templates} = \@templates;

		######### TAB LINKS #########
		$vars->{links} = $oTaranisPublication->getItemLinks( analysis_id => $analysisId );
		$vars->{ignore_new_links} = 1;

		######### TAB PREVIEW #########

		$vars->{isNewAdvisory} = 1;

		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory.tt', $vars, 1 );
		return { dialog => $dialogContent };
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub openDialogAdvisoryDetails {
	my ( %kvArgs ) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {
		my $oTaranisPublication= Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
		my $oTaranisError = Taranis::Error->new( Config );
		my $settings = getAdvisorySettings();
		my $publicationId = $kvArgs{id};

		my $advisory = $oTaranisPublication->getPublicationDetails( table => 'publication_advisory', 'publication_advisory.publication_id' => $publicationId );
		$vars->{advisory} = $advisory;

		$vars->{pub_type} = ( $advisory->{version} > 1.00 ) ? 'update' : 'email';
		$vars->{isUpdate} = ( $advisory->{version} > 1.00 ) ? 1 : 0;

		if ( $advisory->{based_on} ) {
			$oTaranisError->loadCollection( reference_id => $publicationId );
			while ( $oTaranisError->nextObject() ) {
				push @{ $vars->{importNotifications} }, $oTaranisError->getObject();
			}
		}

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

		$vars->{advisory_heading} = $govcertId .': '. $advisory->{title};
		$vars->{advisory_id} = $govcertId;
		$vars->{advisory_version} = $advisory->{version};
		$vars->{author}	= $oTaranisUsers->getUser( $advisory->{created_by} )->{fullname};

		@{ $vars->{damage_description} } = $oTaranisDamageDescription->getDamageDescription();
		my @damageIds	= $oTaranisPublication->getLinkedToPublicationIds(
			table => 'advisory_damage',
			select_column => 'damage_id',
			advisory_id => $advisory->{id}
		);

		for ( my $i = 0; $i < @{ $vars->{damage_description} }; $i++ ) {
			for ( my $j = 0; $j < @damageIds; $j++ ) {
				if ( $vars->{damage_description}->[$i]->{id} eq $damageIds[$j] ) {
					$vars->{damage_description}->[$i]->{selected} = 1;
				}
			}
		}

		########## TAB PLATFORMS #########
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => 'softhard_id' },
			join_table_2 => { software_hardware => 'id' },
			'pu.id' => $advisory->{publication_id}
		);

		my @platforms;
		while ( $oTaranisPublication->nextObject() ) {
			push @platforms, $oTaranisPublication->getObject() ;
		}

		for ( my $i = 0; $i < @platforms; $i++ ) {
			$platforms[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $platforms[$i]->{id} }, 'soft_hard_usage' );
			$platforms[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $platforms[$i]->{type} )->{description};
		}

		$vars->{platforms} = \@platforms;
		$vars->{platforms_text} = $advisory->{platforms_text};

		########## TAB PRODUCTS #########
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { product_in_publication => 'softhard_id' },
			join_table_2 => { software_hardware => 'id'	},
			'pu.id' => $advisory->{publication_id}
		);

		my @products;
		while ( $oTaranisPublication->nextObject() ) {
			push @products, $oTaranisPublication->getObject() ;
		}

		for ( my $i = 0; $i < @products; $i++ ) {
			$products[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $products[$i]->{id} }, 'soft_hard_usage' );
			$products[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $products[$i]->{type} )->{description};
		}
		$vars->{software_hardware} = \@products;
		$vars->{products_text} = $advisory->{products_text};
		$vars->{versions_text} = $advisory->{versions_text};

		########## TABS UPDATE / SUMMARY / CONSEQUENCES / DESCRIPTION / SOLUTION / TLPAMBER #########
		my @templates;
		$oTaranisTemplate->getTemplate( type => $settings->{usableTypeIds} );
		while ( $oTaranisTemplate->nextObject() ) {
			my $tpl = $oTaranisTemplate->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;
			}
		}

		$vars->{advisory_templates} = \@templates;

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
		if ( my $opened_by = $oTaranisPublication->isOpenedBy( $advisory->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $opened_by->{fullname};
		} elsif( right('write') ) {
			if ( $oTaranisPublication->openPublication( sessionGet('userid'), $advisory->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}
		$vars->{isNewAdvisory} = 0;

		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory.tt', $vars, 1 );
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
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub openDialogUpdateAdvisory {
	my ( %kvArgs ) = @_;
	my $vars;

	my $oTaranisTemplate = Taranis::Template->new;

	my $publicationId = $kvArgs{id};
	my $writeRight = right('write');
	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && $writeRight ) {
#		my $an = Taranis::Analysis->new( Config );
		my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );
		my $oTaranisPublication= Publication;
		my $oTaranisUsers = Taranis::Users->new( Config );
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );

		my $settings = getAdvisorySettings();

		my $userId = sessionGet('userid');

		my $advisory = $oTaranisPublication->getPublicationDetails(
			table => "publication_advisory",
			"publication_advisory.publication_id" => $publicationId
		);

		$advisory->{update} = "";
		$advisory->{based_on} = "";
		$vars->{advisory} = $advisory;

		########## TAB GENERAL #########

		my $advisoryVersion = ( $advisory->{version} =~ /\d\.\d9/ ) ? $advisory->{version} + 0.01 . "0" : $advisory->{version} + 0.01;

		$vars->{advisory_heading} = $advisory->{govcertid} .": ". $advisory->{title};
		$vars->{advisory_id} = $advisory->{govcertid};
		$vars->{advisory_version} = $advisoryVersion;
		$vars->{author} = $oTaranisUsers->getUser( $userId )->{fullname};
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


#TODO: create a list of the 'new' CVE id's and prompt user for action
		# get CVE id's from linked analysis
#		$oTaranisPublication->getLinkedToPublication(
#			join_table_1 => { analysis_publication => "analysis_id" },
#			join_table_2 => { analysis => "id" },
#			"pu.id" => $advisory->{publication_id}
#		);
#
#		while ( $oTaranisPublication->nextObject() ) {
#			foreach ( split( " ", $oTaranisPublication->getObject()->{idstring} ) ) {
#				if ( $_ =~ /^CVE.*/i ) {
#					if ( exists( $ids{$_} ) ) {
#						$ids{$_} = { 'new' => 0 };
#					} else {
#						$ids{$_} = { 'new' => 1 };
#					}
#				}
#			}
#		}

		# when an update is created from an analysis, get the idstring from that analysis.
#		if ( $kvArgs{analysisId} =~ /^\d+$/ ) {
#			foreach ( split( " ", $oTaranisAnalysis->getRecordsById( table => "analysis", id => $kvArgs{analysisId} )->[0]->{idstring} ) ) {
#				if ( $_ =~ /^CVE.*/i ) {
#					if ( exists( $ids{$_} ) ) {
#						$ids{$_} = { 'new' => 0 };
#					} else {
#						$ids{$_} = { 'new' => 1 };
#					}
#				}
#			}
#		}

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
		my @damageIds	= $oTaranisPublication->getLinkedToPublicationIds(
			table => "advisory_damage",
			select_column => "damage_id",

			# Why not on publidation_id?
			advisory_id => $advisory->{id}
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
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => "softhard_id" },
			join_table_2 => { software_hardware => "id" },
			"pu.id" => $advisory->{publication_id}
		);

		while ( $oTaranisPublication->nextObject() ) {
			my $platform = $oTaranisPublication->getObject();
			push @platforms, $platform;
			$uniquePlatforms{ $platform->{cpe_id} } = 1;
		}

		# current products taken from previous version
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { product_in_publication => "softhard_id" },
			join_table_2 => { software_hardware => "id" },
			"pu.id" => $advisory->{publication_id}
		);

		while ( $oTaranisPublication->nextObject() ) {
			my $product = $oTaranisPublication->getObject();
			push @products, $product;
			$uniqueProducts{ $product->{cpe_id} } = 1;
		}

		# possible new platforms and products depending on new CVE-IDS
		if ( @newCveIds ) {
			my $allSh = $oTaranisPublication->extractSoftwareHardwareFromCve( "@newCveIds" );
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
				$vars->{platforms_text} .= "\n" . $oTaranisPublication->listSoftwareHardware(ids => \@platformIds, columns => ['producer', 'name', 'version' ]);
			}

			if ( @productIds ) {
				$vars->{products_text} .= "\n" . $oTaranisPublication->listSoftwareHardware(ids => \@productIds, columns => ['producer', 'name']);

				$vars->{versions_text} .= "\n" . $oTaranisPublication->listSoftwareHardware(ids => \@productIds, columns => 'version');
			}
		}

		foreach my $platform (@platforms) {
			$platform->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $platform->{id} }, 'soft_hard_usage' );
			$platform->{description} =	$oTaranisSoftwareHardware->getShType( base => $platform->{type} )->{description};
		}
		$vars->{platforms} = \@platforms;

		foreach my $product (@products) {
			$product->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $product->{id} }, 'soft_hard_usage' );
			$product->{description} =	$oTaranisSoftwareHardware->getShType( base => $product->{type} )->{description};
		}
		$vars->{software_hardware} = \@products;

		########## TABS UPDATE / SUMMARY / CONSEQUENCES / DESCRIPTION / SOLUTION / TLPAMBER #########
		my @templates;
		$oTaranisTemplate->getTemplate( type => $settings->{usableTypeIds} );
		while ( $oTaranisTemplate->nextObject() ) {
			my $tpl = $oTaranisTemplate->getObject();
			if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
				next;
			} else {
				push @templates, $tpl;
			}
		}

		$vars->{advisory_templates} = \@templates;

		########## TAB LINKS #########

		my @linksPreviousVersion = split( "\n", $advisory->{hyperlinks} );
		my @itemLinks = @{ $oTaranisPublication->getItemLinks( publication_id => $advisory->{publication_id} ) };
		my @itemLinksNewAnalysis;
		if (my $id = val_int $kvArgs{analysisId}) {
			@itemLinksNewAnalysis = @{ $oTaranisPublication->getItemLinks( analysis_id => $id ) };
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

		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory.tt', $vars, 1 );
		return {
			dialog => $dialogContent,
			params => {	publicationid => $advisory->{publication_id} }
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}

}

sub openDialogImportAdvisory {
	my ( %kvArgs ) = @_;
	my ( $vars );

	my $importOk = 0;
	my $oTaranisTemplate = Taranis::Template->new;
	my $typeName = Config->publicationTemplateName(advisory => 'email');

	my $analysisId  = val_int $kvArgs{analysisId};
	my $emailItemId = val_int $kvArgs{emailItemId};

	if ( rightOnParticularization( $typeName ) && right('write') ) {
		if($analysisId && $emailItemId) {
			my $oTaranisAssess = Taranis::Assess->new( Config );
			my $oTaranisPublication= Publication;
			my $oTaranisPublicationAdvisory = Taranis::Publication::Advisory->new( config => Config );
			my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );
			my $oTaranisUsers = Taranis::Users->new( Config );
			my $oTaranisDamageDescription = Taranis::Damagedescription->new( Config );

			my $mimeParser = MIME::Parser->new();
			my $outputDir  = tmp_path 'import-adv-attachments';
			mkdir $outputDir;
			$mimeParser->output_dir( $outputDir );

			my $settings = getAdvisorySettings();

			my $userId = sessionGet('userid');
			$vars->{warning} = '';
			$vars->{analysis_id} = $analysisId;

			my $emailItem = $oTaranisAssess->getMailItem($emailItemId);
			my $decodedMessage = HTML::Entities::decode( $emailItem->{body} );
			my $messageEntity;
			eval{ $messageEntity = $mimeParser->parse_data( $decodedMessage ) } if ( $decodedMessage );

			if ( $@ ) {
				$vars->{message} = $@;
			} else {

				my $attachments = $oTaranisAssess->getAttachmentInfo($messageEntity);
				my $advisoryXSD = find_config Config->{advisory_xsd};
				my $validator;

				foreach my $attachmentName (keys %$attachments) {
					$attachments->{$attachmentName}->{filetype} eq 'xml'
						or next;

					my $attachment = $oTaranisAssess->getAttachment($messageEntity, $attachmentName)
						or next;

					my $attachmentEntity = eval { $mimeParser->parse_data( $attachment ) };
					my $attachmentDecoded = decodeMimeEntity( $attachmentEntity, 1, 0 );

					$validator ||= XML::LibXML::Schema->new(location => $advisoryXSD);
					eval { $validator->validated($attachmentDecoded ) };
					if($@) {
						$vars->{message} = $@;
						next;
					}

					# convert XML to perl datastructure
					my $xmlAdvisory = XMLin($attachmentDecoded, SuppressEmpty => '', KeyAttr => []);

					########## TAB MATRIX #########
					$vars->{advisory} = $xmlAdvisory->{rating}->{publisher_analysis};
					$vars->{advisory}->{damage} = $oTaranisPublicationAdvisory->{scale}->{ $xmlAdvisory->{meta_info}->{damage} };
					$vars->{advisory}->{probability} = $oTaranisPublicationAdvisory->{scale}->{ $xmlAdvisory->{meta_info}->{probability} };

					########## TAB GENERAL #########
					my $advisoyIDDetails = $oTaranisPublicationAdvisory->getAdvisoryIDDetailsFromXMLAdvisory( $xmlAdvisory );
					my $basedOnAdvisoryVersion = '1.00';

					my @xmlVersionHistory = flat $xmlAdvisory->{meta_info}->{version_history}->{version_instance};
					foreach my $versionInstance ( @xmlVersionHistory ) {
						$basedOnAdvisoryVersion = $versionInstance->{version} if ( $versionInstance->{version} > $basedOnAdvisoryVersion );
					}

					my $title = $oTaranisPublicationAdvisory->getTitleFromXMLAdvisory( $xmlAdvisory );
					$vars->{advisory_heading} = $advisoyIDDetails->{newAdvisoryDetailsId} .": ". $title;
					$vars->{advisory_id} = $advisoyIDDetails->{newAdvisoryDetailsId};
					$vars->{advisory_version} = $advisoyIDDetails->{newAdvisoryVersion};
					$vars->{publication_previous_version_id} = $advisoyIDDetails->{publicationPreviousVersionId};
					$vars->{author} = $oTaranisUsers->getUser( $userId )->{fullname};
					$vars->{date_created} = nowstring(9);
					$vars->{advisory}->{title} = $title;
					$vars->{analysis_id} = $analysisId;
					$vars->{advisory}->{based_on} = $xmlAdvisory->{meta_info}->{reference_number} . ' ' . $basedOnAdvisoryVersion;

					### IDS ###
					my $idString = '';
					{	my @ids;
						my $vuln_ids = $xmlAdvisory->{meta_info}->{vulnerability_identifiers};
						foreach my $typeDescr (values %$vuln_ids) {
							push @ids, flat($typeDescr->{id});
						}
						$idString = sortCVEString(join ', ', @ids);
					}
					$vars->{cve_id} = $idString;

					### DAMAGE DESCRIPTION ###
					@{ $vars->{damage_description} } = $oTaranisDamageDescription->getDamageDescription();
					my $damageDescriptionDetails = $oTaranisPublicationAdvisory->getDamageDescriptionsFromXMLAdvisory( $xmlAdvisory );

					for ( my $i = 0; $i < @{ $vars->{damage_description} }; $i++ ) {
						for ( my $j = 0; $j < @{ $damageDescriptionDetails->{damageDescriptionIds} }; $j++ ) {
							if ( $vars->{damage_description}->[$i]->{id} eq $damageDescriptionDetails->{damageDescriptionIds}->[$j] ) {
								$vars->{damage_description}->[$i]->{selected} = 1;
							}
						}
					}

					foreach my $xmlDamageDescription ( @{ $damageDescriptionDetails->{newDamageDescriptions} } ) {
						$vars->{warning} .= encode( 'UTF-8', "Warning: damage description '$xmlDamageDescription' could not be found!<br>");
					}

					########## TABS PLATFORMS  & PRODUCTS #########
					$vars->{platforms_text} = encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_platforms_text} );
					$vars->{products_text} = encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_products_text} );
					$vars->{versions_text} = encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_products_versions_text} );

					my $softwareHardwareDetails = $oTaranisPublicationAdvisory->getSoftwareHardwareFromXMLAdvisory( $xmlAdvisory );
					for ( my $i = 0; $i < @{ $softwareHardwareDetails->{platforms} }; $i++ ) {
						$softwareHardwareDetails->{platforms}->[$i]->{description} = $oTaranisSoftwareHardware->getShType( base => $softwareHardwareDetails->{platforms}->[$i]->{type} )->{description};
					}

					$vars->{platforms} = $softwareHardwareDetails->{platforms};

					for ( my $i = 0; $i < @{ $softwareHardwareDetails->{products} }; $i++ ) {
						$softwareHardwareDetails->{products}->[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $softwareHardwareDetails->{products}->[$i]->{type} )->{description};
					}
					$vars->{software_hardware} = $softwareHardwareDetails->{products};

					# log software/hardware which could not be linked to advisory
					foreach my $shProblem ( @{ $softwareHardwareDetails->{importProblems} } ) {
						$vars->{warning} .= "Warning: $shProblem <br>";
					}

					########## TABS UPDATE / SUMMARY / CONSEQUENCES / DESCRIPTION / SOLUTION / TLPAMBER #########
					my @templates;
					$oTaranisTemplate->getTemplate( type => $settings->{usableTypeIds} );
					while ( $oTaranisTemplate->nextObject() ) {
						my $tpl = $oTaranisTemplate->getObject();
						if ( exists( $settings->{nonUsableTemplates}->{ lc $tpl->{title} } ) ) {
							next;
						} else {
							push @templates, $tpl;
						}
					}

					$vars->{advisory_templates} = \@templates;
					$vars->{advisory}->{summary} = encode_entities( $xmlAdvisory->{content}->{abstract} );
					$vars->{advisory}->{consequences} = encode_entities( $xmlAdvisory->{content}->{consequences} );
					$vars->{advisory}->{description} = encode_entities( $xmlAdvisory->{content}->{description} );
					$vars->{advisory}->{solution} = encode_entities( $xmlAdvisory->{content}->{solution} );
					$vars->{advisory}->{update} = encode_entities( $xmlAdvisory->{content}->{update_information} );

					########## TAB LINKS #########
					my @linksFromXMLAdvisory = split( "\n", $oTaranisPublicationAdvisory->getLinksFromXMLAdvisory( $xmlAdvisory ) );
					$vars->{links} = \@linksFromXMLAdvisory;
					$vars->{uncheck_new_links} = 0;

					$vars->{isNewAdvisory} = 1;
					$vars->{isUpdate} = ( $advisoyIDDetails->{newAdvisoryVersion} > 1 ) ? 1 : 0;
				}
			}
		}

		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory.tt', $vars, 1 );
		return {
			dialog => $dialogContent,
			params => {}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}

}

sub openDialogPreviewAdvisory {
	my %kvArgs = @_;
	my $publicationId = val_int $kvArgs{id};

	my $vars;
	my $oTaranisTemplate = Taranis::Template->new;

	my $writeRight   = right('write');
	my $executeRight = right('execute');

	my $typeName = Config->publicationTemplateName(advisory => 'email');
	if ( rightOnParticularization( $typeName ) ) {
		my $oTaranisPublication = Publication;
		my $oTaranisSoftwareHardware = Taranis::SoftwareHardware->new( Config );

		my $userId   = sessionGet('userid');
		my $settings = getAdvisorySettings();

		my $advisory = $oTaranisPublication->getPublicationDetails(
			table => "publication_advisory",
			"publication_advisory.publication_id" => $publicationId
		);

		$vars->{is_updated} = $advisory->{replacedby_id} ? 1 : 0;
		$vars->{pub_type}   = $advisory->{version} > 1.00 ? "update" : "email";

		my $users = Taranis::Users->new( Config );
		$vars->{created_by_name}   = $users->getUserFullname($advisory->{created_by});
		$vars->{approved_by_name}  = $users->getUserFullname($advisory->{approved_by});
		$vars->{published_by_name} = $users->getUserFullname($advisory->{published_by});
		my $userIsAuthor = $advisory->{created_by} eq sessionGet('userid') ? 1 : 0;

		$vars->{message} = "Warning: this advisory has been deleted"
			if $advisory->{deleted};

		$vars->{advisory} = $advisory;

		### SET opened_by OR RETURN locked = 1 ###
		if ( my $opened_by = $oTaranisPublication->isOpenedBy( $advisory->{publication_id} ) ) {
			$vars->{isLocked} = 1;
			$vars->{openedByFullname} = $opened_by->{fullname};
		} elsif(($writeRight || $executeRight) && $advisory->{status} != 3) {
			if ( $oTaranisPublication->openPublication( $userId, $advisory->{publication_id} ) ) {
				$vars->{isLocked} = 0;
			} else {
				$vars->{message} = $oTaranisPublication->{errmsg};
				$vars->{isLocked} = 1;
			}
		} else {
			$vars->{isLocked} = 1;
		}

		my $noStatusChangeButtons = 0;
		if ( $advisory->{damage} == 3 && $advisory->{probability} == 3 && !$settings->{publishLL} ) {
			$noStatusChangeButtons = 1;
		}

		# PLATFORMS
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { platform_in_publication  => 'softhard_id' },
			join_table_2 => { software_hardware => 'id' },
			'pu.id' => $advisory->{publication_id}
		);

		my @platforms;
		while ( $oTaranisPublication->nextObject() ) {
			push @platforms, $oTaranisPublication->getObject() ;
		}

		for ( my $i = 0; $i < @platforms; $i++ ) {
			$platforms[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $platforms[$i]->{id} }, 'soft_hard_usage' );
			$platforms[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $platforms[$i]->{type} )->{description};
		}

		$vars->{platforms} = \@platforms;
		$vars->{platforms_text} = $advisory->{platforms_text};

		# PRODUCTS
		$oTaranisPublication->getLinkedToPublication(
			join_table_1 => { product_in_publication => 'softhard_id' },
			join_table_2 => { software_hardware => 'id'	},
			'pu.id' => $advisory->{publication_id}
		);

		my @products;
		while ( $oTaranisPublication->nextObject() ) {
			push @products, $oTaranisPublication->getObject() ;
		}

		for ( my $i = 0; $i < @products; $i++ ) {
			$products[$i]->{in_use} = $oTaranisSoftwareHardware->{dbh}->checkIfExists( { soft_hard_id => $products[$i]->{id} }, 'soft_hard_usage' );
			$products[$i]->{description} =	$oTaranisSoftwareHardware->getShType( base => $products[$i]->{type} )->{description};
		}
		$vars->{products} = \@products;

		my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory_preview.tt', $vars, 1 );
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
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub openDialogAdvisoryNotificationDetails {
	my ( %kvArgs ) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisError = Taranis::Error->new( Config );

	my $notification = $oTaranisError->getError( $kvArgs{id} );

	my $notificationText = fileToString( $notification->{logfile} );
	$vars->{notificationText} = decode_entities( $notificationText ) || "No logfile available.";

	my $dialogContent = $oTaranisTemplate->processTemplate( 'write_advisory_notification_details.tt', $vars, 1 );
	return {
		dialog => $dialogContent
	};
}

sub saveNewAdvisory {
	my ( %kvArgs ) = @_;

	my ( $message, $publicationId, $advisoryId );
	my $saveOk = 0;

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $oTaranisPublication= Publication;
		my $oTaranisTemplate = Taranis::Template->new;
		my $settings = getAdvisorySettings();

		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;

		my $typeId = $oTaranisPublication->getPublicationTypeId($typeName);
		my $userId = sessionGet('userid');

		my $analysisId = $kvArgs{analysisId} || undef;
		my $basedOn    = $kvArgs{based_on} || undef;
		my $advisoryIdentifier = ( $kvArgs{advisory_id} ) ? $kvArgs{advisory_id} : $settings->{advisoryPrefix} . '-' . nowstring(6) . '-' . $settings->{x};
		my $advisoryVersion = ( exists( $kvArgs{advisory_version} ) ) ? $kvArgs{advisory_version} : '1.00';

		withTransaction {
			if (
				!$oTaranisPublication->addPublication(
					title => substr( $kvArgs{title}, 0, 50 ),
					created_by => $userId,
					type => $typeId,
					status => '0'
				)
				|| !( $publicationId = $oTaranisPublication->{dbh}->getLastInsertedId('publication') )
				|| (
					$analysisId
					&& !$oTaranisPublication->linkToPublication(
							table => 'analysis_publication',
							analysis_id => $analysisId,
							publication_id => $publicationId
					)
				)
				|| !$oTaranisPublication->linkToPublication(
						table => 'publication_advisory',
						publication_id => $publicationId,
						version => $advisoryVersion,
						govcertid => $advisoryIdentifier,
						based_on => $basedOn,
						title => $kvArgs{title},
						probability => $kvArgs{probability},
						damage => $kvArgs{damage},
						ids => sortCVEString( $kvArgs{cve_id} ),
						platforms_text => $kvArgs{platforms_txt},
						versions_text => $kvArgs{versions_txt},
						products_text => $kvArgs{products_txt},
						hyperlinks => $advisoryLinks,
						description => $kvArgs{tab_description_txt},
						consequences => $kvArgs{tab_consequences_txt},
						solution => $kvArgs{tab_solution_txt},
						tlpamber => $kvArgs{tab_tlpamber_txt},
						summary => $kvArgs{tab_summary_txt},
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
					)
			) {
				$message = $oTaranisPublication->{errmsg};
			} else {
				$advisoryId = $oTaranisPublication->{dbh}->getLastInsertedId('publication_advisory');

				#### link products, platforms and damage descriptions to publication ####
				foreach my $productId (flat $kvArgs{pd_left_column}) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'product_in_publication',
							softhard_id => $productId,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $platformId (flat $kvArgs{pf_left_column}) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'platform_in_publication',
							softhard_id => $platformId,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $damageDescription (flat $kvArgs{damage_description}) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'advisory_damage',
							damage_id => $damageDescription,
							advisory_id => $advisoryId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}
			}

			# update replacedby_id of previous version advisory with new publication id
			if (my $prev = $kvArgs{publication_previous_version_id} ) {
				if (!$oTaranisPublication->setPublication( id => $prev, replacedby_id => $publicationId ) ) {
					$message = $oTaranisPublication->{errmsg};
				}
			}
		};

		if ( !$message ) {
			my $advisoryType = ( $advisoryVersion > 1 ) ? 'update' : 'email';
			my $previewText = $oTaranisTemplate->processPreviewTemplate( 'advisory', $advisoryType, $advisoryId, $publicationId, 71 );
			my $xmlText = $oTaranisPublication->processPreviewXml( $advisoryId );

			if ( !$oTaranisPublication->setPublication( id => $publicationId, contents => $previewText, xml_contents => $xmlText ) ) {
				$message = $oTaranisPublication->{errmsg};
			}
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
			publicationId => $publicationId
		}
	};
}

sub saveAdvisoryDetails {
	my ( %kvArgs ) = @_;

	my ( $message, $advisory );
	my $saveOk = 0;
	my $publicationId = $kvArgs{pub_id};

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $oTaranisPublication= Publication;
		my $oTaranisTemplate = Taranis::Template->new;

		my $advisoryId = $kvArgs{adv_id};

		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;

		my @productIds = $oTaranisPublication->getLinkedToPublicationIds(
			table => 'product_in_publication',
			select_column => 'softhard_id',
			publication_id => $publicationId
		);

		my @products = flat $kvArgs{pd_left_column};
		my ( $newProducts, $deleteProducts ) = addAndDelete( \@productIds, \@products );

		my @platformIds = $oTaranisPublication->getLinkedToPublicationIds(
			table => 'platform_in_publication',
			select_column => 'softhard_id',
			publication_id => $publicationId
		);

		my @platforms = flat $kvArgs{pf_left_column};
		my ( $newPlatforms, $deletePlatforms ) = addAndDelete( \@platformIds, \@platforms );

		my @damageDescriptionIds = $oTaranisPublication->getLinkedToPublicationIds(
			table => 'advisory_damage',
			select_column => 'damage_id',
			advisory_id => $advisoryId
		);

		my @damageDescriptions = flat $kvArgs{damage_description};
		my ( $newDamageDescriptions, $deleteDamageDescriptions ) = addAndDelete( \@damageDescriptionIds, \@damageDescriptions );

		withTransaction {
			if (
				!$oTaranisPublication->setPublicationDetails(
					table => 'publication_advisory',
					where => { id => $advisoryId },
					title => $kvArgs{title},
					probability => $kvArgs{probability},
					damage => $kvArgs{damage},
					ids => sortCVEString( $kvArgs{cve_id} ),
					hyperlinks => $advisoryLinks,
					platforms_text => $kvArgs{platforms_txt},
					versions_text => $kvArgs{versions_txt},
					products_text => $kvArgs{products_txt},
					description => $kvArgs{tab_description_txt},
					consequences => $kvArgs{tab_consequences_txt},
					solution => $kvArgs{tab_solution_txt},
					tlpamber => $kvArgs{tab_tlpamber_txt},
					summary => $kvArgs{tab_summary_txt},
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
				)
			) {
				$message = $oTaranisPublication->{errmsg};
			} else {

				#### link new products, platforms and damage descriptions to publication ####
				foreach my $product_id ( @$newProducts ) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'product_in_publication',
							softhard_id => $product_id,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $platform_id ( @$newPlatforms ) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'platform_in_publication',
							softhard_id => $platform_id,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $damage_id ( @$newDamageDescriptions ) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => 'advisory_damage',
							damage_id => $damage_id,
							advisory_id => $advisoryId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				#### unlink products, platforms and damage descriptions from publication ####
				foreach my $productId ( @$deleteProducts ) {
					if (
						!$oTaranisPublication->unlinkFromPublication(
							table => 'product_in_publication',
							softhard_id => $productId,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $platformId ( @$deletePlatforms ) {
					if (
						!$oTaranisPublication->unlinkFromPublication(
							table => 'platform_in_publication',
							softhard_id => $platformId,
							publication_id => $publicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				foreach my $damageId ( @$deleteDamageDescriptions ) {
					if (
						!$oTaranisPublication->unlinkFromPublication(
							table => 'advisory_damage',
							damage_id => $damageId,
							advisory_id => $advisoryId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}
			}
			$saveOk = 1 if ( !$message );
		};

		$advisory = $oTaranisPublication->getPublicationDetails(
				table => 'publication_advisory',
				'publication_advisory.id' => $advisoryId
			);

		my $publicationType = ( $advisory->{version} > 1.00 ) ? 'update' : 'email';

		my $previewText = $oTaranisTemplate->processPreviewTemplate( 'advisory', $publicationType, $advisoryId, $publicationId, 71 );
		my $xmlText = $oTaranisPublication->processPreviewXml( $advisoryId );

		if ( !$oTaranisPublication->setPublication( id => $publicationId, contents => $previewText, xml_contents => $xmlText ) ) {
			$message = 'Updating the advisory preview and XML test has failed. ' . $oTaranisPublication->{errmsg};
		}

		if ( !exists( $kvArgs{skipUserAction} ) ) {
			if ( $saveOk ) {
				setUserAction( action => 'edit advisory', comment => "Edited advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");
			} else {
				setUserAction( action => 'edit advisory', comment => "Got error '$message' while trying to edit advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");
			}
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

sub saveUpdateAdvisory {
	my ( %kvArgs ) = @_;

	my ( $message, $newPublicationId );
	my $saveOk = 0;
	my $publicationId = $kvArgs{pub_id};
	my $advisoryId = $kvArgs{adv_id};

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $oTaranisPublication= Publication;
		my $oTaranisTemplate = Taranis::Template->new;

		my $userId = sessionGet('userid');

		my $advisory = $oTaranisPublication->getPublicationDetails(
			table => "publication_advisory",
			"publication_advisory.id" => $advisoryId
		);

		my @advisoryLinks = flat $kvArgs{advisory_links};
		push @advisoryLinks, split /\s+/s, $kvArgs{additional_links} || '';
		my $advisoryLinks = join "\n", @advisoryLinks;

		my $advisoryVersion = ( $advisory->{version} =~ /\d\.\d9/ ) ? $advisory->{version} + 0.01 . "0" : $advisory->{version} + 0.01;

		my @analysisIds = $oTaranisPublication->getLinkedToPublicationIds(
			table => "analysis_publication",
			select_column => "analysis_id",
			publication_id => $publicationId
		);

		withTransaction {
			if (
				!$oTaranisPublication->addPublication(
					title => substr( $kvArgs{title}, 0, 50 ),
					created_by => $userId,
					type => $advisory->{type},
					status => "0"
				)
				|| !( $newPublicationId = $oTaranisPublication->{dbh}->getLastInsertedId("publication") )
				|| !$oTaranisPublication->linkToPublication(
						table => "publication_advisory",
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
						description => $kvArgs{tab_description_txt},
						consequences => $kvArgs{tab_consequences_txt},
						solution => $kvArgs{tab_solution_txt},
						tlpamber => $kvArgs{tab_tlpamber_txt},
						summary => $kvArgs{tab_summary_txt},
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
					)
			) {
				$message = $oTaranisPublication->{errmsg};
			} else {

				my $newAdvisoryId = $oTaranisPublication->{dbh}->getLastInsertedId("publication_advisory");

				if ( $kvArgs{pd_left_column} && !$message ) {
					foreach my $productId (flat $kvArgs{pd_left_column}) {
						if (
							!$oTaranisPublication->linkToPublication(
								table => "product_in_publication",
								softhard_id => $productId,
								publication_id => $newPublicationId
							)
						) {
							$message = $oTaranisPublication->{errmsg};
						}
					}
				}

				if($kvArgs{pf_left_column} && !$message ) {
					foreach my $platformId (flat $kvArgs{pf_left_column}) {
						if (
							!$oTaranisPublication->linkToPublication(
								table => "platform_in_publication",
								softhard_id => $platformId,
								publication_id => $newPublicationId
							)
						) {
							$message = $oTaranisPublication->{errmsg};
						}
					}
				}

				if($kvArgs{damage_description} && !$message) {
					foreach my $damageDescription (flat $kvArgs{damage_description}) {
						if (
							!$oTaranisPublication->linkToPublication(
								table => "advisory_damage",
								damage_id => $damageDescription,
								advisory_id => $newAdvisoryId
							)
						) {
							$message = $oTaranisPublication->{errmsg};
						}
					}
				}

				my $analysisId = val_int $kvArgs{analysisId};
				if ($analysisId && !$message ) {
					if (
						!$oTaranisPublication->linkToPublication(
							table => "analysis_publication",
							analysis_id => $analysisId,
							publication_id => $newPublicationId
						)
					) {
						$message = $oTaranisPublication->{errmsg};
					}
				}

				if ( @analysisIds && !$message ) {
					foreach (grep $_ != $analysisId, @analysisIds ) {
						if (
							!$oTaranisPublication->linkToPublication(
								table => "analysis_publication",
								analysis_id => $_,
								publication_id => $newPublicationId
							)
						) {
							$message = $oTaranisPublication->{errmsg};
						}
					}
				}

				my $previewText = $oTaranisTemplate->processPreviewTemplate( "advisory", "update", $newAdvisoryId, $newPublicationId, 71 );

				if ( !$message && !$oTaranisPublication->setPublication( id => $newPublicationId, contents => $previewText ) ) {
					$message = $oTaranisPublication->{errmsg};
				}

				if ( !$message && !$oTaranisPublication->setPublication( id => $publicationId, replacedby_id => $newPublicationId ) ) {
					$message = $oTaranisPublication->{errmsg};
				}

				$saveOk = 1 if ( !$message );
			}
		};

		if ( $saveOk ) {
			setUserAction( action => 'update advisory', comment => "Created update on advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");
		} else {
			setUserAction( action => 'update advisory', comment => "Got error '$message' while trying to create an update on advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "'");
		}

	} else {
		$message = 'No permission';
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			publicationId => $newPublicationId,
			detailsId => $advisoryId
		}
	};
}

sub setAdvisoryStatus {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;

	my $oTaranisPublication= Publication;
	my $settings = getAdvisorySettings();
	my $publicationId = $kvArgs{publicationId};
	my $newStatus = $kvArgs{status};
	my $userId = sessionGet('userid');

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if (
		( rightOnParticularization( $typeName ) && right('write') )
		|| $newStatus =~ /^(0|1|2)$/
	) {

		my $advisory = $oTaranisPublication->getPublicationDetails(
			table => 'publication_advisory',
			'publication_advisory.publication_id' => $publicationId
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
				if ( !$oTaranisPublication->setPublication(
						id => $publicationId,
						status => $newStatus,
						approved_on => nowstring(10),
						approved_by => $userId
					)
				) {

					$message = $oTaranisPublication->{errmsg};

				} else {
					$saveOk = 1;
				}
			} else {
				if ( !$oTaranisPublication->setPublication(
						id => $publicationId,
						status => $newStatus,
						approved_on => undef,
						approved_by => undef
					)
				) {
					$message = $oTaranisPublication->{errmsg};
				} else {
					$saveOk = 1;
				}
			}
		} else {
			$message = "This status change action is not permitted.";
		}

		if ( $saveOk ) {
			setUserAction( action => 'change advisory status', comment => "Changed advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
		} else {
			setUserAction( action => 'change advisory status', comment => "Got error '$message' while trying to change status of advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' from '$oTaranisPublication->{status}->{$currentStatus}' to '$oTaranisPublication->{status}->{$newStatus}'");
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

sub setReadyForReview {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $saveOk = 0;
	my $oTaranisPublication= Publication;
	my $oTaranisTemplate = Taranis::Template->new;
	my $settings = getAdvisorySettings();
	my $publicationId = $kvArgs{publicationId};
	my $advisoryId = $kvArgs{advisoryId};

	my $typeName = Config->publicationTemplateName(advisory => 'email');

	if ( rightOnParticularization( $typeName ) && right('write') ) {

		my $email = $oTaranisTemplate->processPreviewTemplate( 'advisory', 'email', $advisoryId, $publicationId, 71 );

		my $advisory = $oTaranisPublication->getPublicationDetails(
			table => 'publication_advisory',
			'publication_advisory.id' => $advisoryId
		);

		if (
			$advisory->{damage} == 3
			&& $advisory->{probability} == 3
			&& !$settings->{publishLL}
		) {
			$message = "The advisory is scaled as LL (low probability, low damage), therefore cannot be send. To send LL advisories set configuration option 'publish_LL_advisory' to 'yes'.";
		} elsif (
			!$oTaranisPublication->setPublication(
				id => $publicationId,
				contents => $email,
				status => 1
			)
		) {
			$message = $oTaranisPublication->{errmsg};
		} else {
			$saveOk = 1;
		}

		if ( $saveOk ) {
			setUserAction( action => 'change advisory status', comment => "Changed advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' to ready for review");
		} else {
			setUserAction( action => 'change advisory status', comment => "Got error '$message' while trying to change status of advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' to ready for review");
		}
	}

	return {
		params => {
			message => $message,
			saveOk => $saveOk,
			publicationId => $publicationId
		}
	};
}

sub getAdvisoryPreview {
	my ( %kvArgs ) = @_;

	my ( $message );
	my $oTaranisPublication= Publication;
	my $oTaranisTemplate = Taranis::Template->new;
	my $settings = getAdvisorySettings();

	my $publicationId = $kvArgs{publicationId};
	my $advisoryId = $kvArgs{advisoryId};
	my $publicationType = $kvArgs{publicationType};
	my $previewText;

	if ( $publicationType eq "xml" ) {
		$previewText = $oTaranisPublication->processPreviewXml( $advisoryId );
	} else {
		$previewText = $oTaranisTemplate->processPreviewTemplate( "advisory", $publicationType, $advisoryId, $publicationId, 71 );
	}

	$message = $oTaranisTemplate->{errmsg};

	return {
		params => {
	 		previewText => $previewText,
	 		message => $message,
	 		publicationId => $publicationId
	 	}
	 };
}

sub saveAdvisoryLateLinks(%) {
	my %kvArgs = @_;

	my $oTaranisPublication = Publication;
	my $oTaranisAnalysis    = Taranis::Analysis->new( Config );
	my $oTaranisAssess      = Taranis::Assess->new( Config );

	my $advisoryId = $kvArgs{advisoryId};
	my $analysisId = $kvArgs{analysisId};
	my @newsItems  = split /\,/, $kvArgs{newsitems} || '';
	my $username   = sessionGet('userid');

	my $eod        = Taranis::Publication::EndOfDay->new->{typeId};

	my $db = Database->simple;

	withTransaction {

		foreach my $digest (@newsItems) {

			# Do not add the same link twice to the same advisory.  No visual
			# support for that (yet)
			my $found = $db->query(<<'__FIND', $digest, $advisoryId)->list;
 SELECT 1 FROM advisory_linked_items
  WHERE item_digest = ? AND publication_id = ?
__FIND
			next if $found;

			my $link_id = $db->query(<<'__LINK', $digest, $advisoryId, $username)->list;
 INSERT INTO advisory_linked_items
        (item_digest, publication_id, created_by)
 VALUES (?, ?, ?)
 RETURNING id
__LINK

			# Only for completeness: we need the info in advisory_linked_items
			# for advisory and creation time, which cannot be derived from
			# the item itself.
			$oTaranisAssess->addToPublication($digest, $eod, 'linked_item');
		}
	};

	return {
	};
}

## HELPERS ##
sub getAdvisorySettings {
	my $oTaranisTemplate = Taranis::Template->new;
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

			if ( $_ =~ /^(email|update|taranis_xml|website)$/ ) {
				push @usableTemplateTypeNames, $val->{$_};
			}

			$nonUsableTemplates{ lc $val->{$_} } = 1 if ( $val->{$_} );
		}
	}
	$settings->{nonUsableTemplates} = \%nonUsableTemplates;
	$settings->{usableTypeIds} = $oTaranisTemplate->getTypeIds( @usableTemplateTypeNames );

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
	my $cveString = shift;
	my %cves;
	s/^\s+//,s/\s+$// for $cveString;
	foreach my $cve (split /[., ]+/, $cveString) {
		$cve =~ /^(\w+)-(\d+)-(\d+)/ or next;
		$cves{sprintf "%04d-%s-%06d", $2, $1, $3} = $cve;
	}
	join ', ', @cves{sort keys %cves};
}

1;
