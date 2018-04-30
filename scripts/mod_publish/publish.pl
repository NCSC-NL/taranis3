#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::SessionUtil qw(right rightOnParticularization getSessionUserSettings);
use Taranis::Template;
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use strict;

use HTML::Entities qw(decode_entities);

my @EXPORT_OK = qw(displayPublishOptions displayPublish checkPGPSigning);

sub publish_export {
	return @EXPORT_OK;
}

our %pageOptions = (
	advisory => { 
		id_column_name 		=> "Advisory ID", 
		title_column_name 	=> "Advisory title", 
		table 				=> "publication_advisory",
		type_id 			=> ["govcertid", "version_str"],
		title_content 		=> ["pub_title"],
		particularization 	=> "advisory (email)",
		page_title 			=> "Advisory Email",
		pgp_setting			=> "pgp_signing_advisory"
	},
	forward => { 
		id_column_name 		=> "Advisory ID", 
		title_column_name 	=> "Advisory title", 
		table 				=> "publication_advisory_forward",
		type_id 			=> ["govcertid", "version_str"],
		title_content 		=> ["pub_title"],
		particularization 	=> "advisory (forward)",
		page_title 			=> "Forward Advisory",
		pgp_setting			=> "pgp_signing_advisory"
	},	
	eod => { 
		id_column_name 		=> "Publication", 
		title_column_name 	=> "Timeframe", 
		table 				=> "publication_endofday",
		type_id 			=> ["pub_title"],
		title_content 		=> ["timeframe_str"],
		particularization 	=> "end-of-day (email)",
		page_title 			=> "End-of-Day Confidential",
		pgp_setting			=> "pgp_signing_endofday"
	},
	eod_public => { 
		id_column_name		=> "Publication", 
		title_column_name	=> "Timeframe", 
		table				=> "publication_endofday",
		type_id				=> ["pub_title"],
		title_content		=> ["timeframe_str"],
		particularization	=> "end-of-day (email public)",
		page_title			=> "End-of-Day Public",
		pgp_setting			=> "pgp_signing_endofday_public",
	},
	eod_white => { 
		id_column_name		=> "Publication", 
		title_column_name	=> "Timeframe", 
		table				=> "publication_endofday",
		type_id				=> ["pub_title"],
		title_content		=> ["timeframe_str"],
		particularization	=> "end-of-day (email white)",
		page_title			=> "End-of-Day White",
		pgp_setting			=> "pgp_signing_endofday_white",
	},
	eos => { 
		id_column_name 		=> "Publication", 
		title_column_name 	=> "Timeframe", 
		table 				=> "publication_endofshift",
		type_id 			=> ["pub_title"],
		title_content 		=> ["timeframe_str"],
		particularization 	=> "end-of-shift (email)",
		page_title 			=> "End-of-Shift",
		pgp_setting			=> "pgp_signing_endofshift"
	},
	eow => { 
		id_column_name 		=> "Publication", 
		title_column_name 	=> "Created on", 
		table 				=> "publication_endofweek",
		type_id 			=> ["pub_title"],
		title_content 		=> ["created_on_str"],
		particularization 	=> "end-of-week (email)",
		page_title 			=> "End-of-Week",
		pgp_setting			=> "pgp_signing_endofweek"
	},
);

sub displayPublishOptions {
	my ( %kvArgs) = @_;
	my ( $vars );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublish = Taranis::Publish->new;

	if ( my $unpublishedCount = $oTaranisPublish->getUnpublishedCount() ) {
		$vars->{unpublishedCount}->{ lc($_->{title}) } = $_->{approved_count} for @$unpublishedCount;
	}
	
	$vars->{pageSettings} = getSessionUserSettings();
	my $htmlContent = $oTaranisTemplate->processTemplate('publish_options.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('publish_options_filters.tt', $vars, 1);
	
	my @js = (
		'js/publish.js',
	);
	
	return { content => $htmlContent,  filters => $htmlFilters, js => \@js };
}

sub displayPublish {
	my ( %kvArgs) = @_;
	my ( $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
		
	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	my $type = ( exists( $pageOptions{ $kvArgs{pub_type} } ) ) ? $kvArgs{pub_type} : "advisory";

	my $publicationType = $oTaranisPublication->getPublicationTypeId( $pageOptions{ $type }->{particularization} );
	my $typeId = ( $publicationType ) ? $publicationType->{id} : undef;
	
	if ( !$typeId ) {
		logErrorToSyslog("displayPublish: type id not found for type '$type', could be configuration error...");
		return { content => '<div>type id not found for type</div>', filters => '<div></div>' };
	}	
	
	my $vars = getPublishSettings( type => $type );

	if ( $vars->{hasRightsForPublish} ) {

		my %searchFields = (
			status => [2],
			table => $pageOptions{ $type }->{table},
			hitsperpage => 100,
			offset => ( $pageNumber - 1 ) * 100,
			date_column	=> "created_on",
			search => "",
			publicationType => $typeId
		);
		my $publications = $oTaranisPublication->loadPublicationsCollection(%searchFields);

		foreach my $publication ( @$publications ) {
			foreach ( @{ $pageOptions{ $type }->{type_id} } ) {
				$publication->{specific_id} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A";	
			}
			
			foreach ( @{ $pageOptions{ $type }->{title_content} } ) {
				$publication->{title_content} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A ";
			}
		}

		$vars->{publications} = $publications;
		$vars->{pub_type} = $type;
  		$vars->{page_title} = $pageOptions{ $type }->{page_title};
		$vars->{page_columns} = $pageOptions{ $type };
		$vars->{numberOfResults} = $oTaranisPublication->publicationsCollectionCount(%searchFields);

		$tpl = 'publish.tt';
	} else {
		$tpl = 'no_permission.tt';
	}

	my $htmlContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	my $htmlFilters = $oTaranisTemplate->processTemplate('publish_filters.tt', $vars, 1);
	
	my @js = (
		'js/publish_advisory.js',
		'js/publish_advisory_forward.js',
		'js/publish_eow.js',
		'js/publish_eos.js',
		'js/publish_eod.js',
		'js/publish_eod_public.js',
		'js/publish_eod_white.js',
		'js/publish.js'
	);
	
	return { 
		content => $htmlContent, 
		filters => $htmlFilters, 
		js => \@js
	};
}

sub checkPGPSigning {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $pgpSigningOk = 0;
	
	my $publicationId = $kvArgs{id};
	my $publicationType = $kvArgs{publicationType};	
	my $publicationText = $kvArgs{publicationText};

	$publicationText =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	$publicationText =~ s/&#39;/'/g;
	
	my $pgpSigningSetting = Config->{ $pageOptions{ $publicationType }->{pgp_setting} };

	my $oTaranisPublication = Publication;
	my $table = $pageOptions{ $publicationType }->{table};
	my $publication = $oTaranisPublication->getPublicationDetails( 
		table => $table,
		$table . ".publication_id" => $publicationId
	);
	
	my $from_db = decode_entities( $publication->{contents} );
	$from_db =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	
	if ( $pgpSigningSetting !~ /^ON$/i ) {

		$from_db =~ s/\s//g;
		$publicationText =~ s/\s//g;
		
		if ( $from_db ne decode_entities( $publicationText ) ) {
			$message = "The contents of the publication have been changed.\nThe publication cannot be sent with these changes.";
		} else {
			$pgpSigningOk = 1;		
		}

  	} else {
	
		$message = "The publication has not been signed with PGP.";
			
		if ( $publicationText =~ /^-----BEGIN PGP SIGNED MESSAGE-----\nHash:(?:.*?)\n(.*)-----BEGIN PGP SIGNATURE-----(.*)-----END PGP SIGNATURE-----$/is ) {
			my $org = $1;
			$org =~ s/\s//g;
	
			# PGP adds '- ' to a line when a line starts with '--', this is corrected below
			my $pgpComparisonReady = "";
			foreach my $line ( split( "\n", $from_db ) ) {
				if ( $line =~ /^-/ ) {
					$line = "- " . $line;
				} 
				$pgpComparisonReady .= $line ;
			}
			
			$pgpComparisonReady =~ s/\s//g;

			if ( $pgpComparisonReady ne decode_entities( $org ) ) {			
				$message = "The contents of the publication have been changed.\nThe publication cannot be sent with these changes.";
			} else {
				$pgpSigningOk = 1;		
			}
		}
  	}
  	
  	return { 
  		params => {
  			message => $message,
  			pgpSigningOk => $pgpSigningOk,
  			publicationId => $publicationId
  		}
  	};
}


## HELPER SUB ##
sub getPublishSettings {
	my ( %kvArgs ) = @_;
	my $settings = {};
	
	my $type = $kvArgs{type}; 

	my $hasRightsForPublish = 0;
	if ( ref( $pageOptions{$type}->{particularization} ) eq 'ARRAY' ) {
		foreach my $particularization ( @{ $pageOptions{$type}->{particularization} } ) {
			if ( !$hasRightsForPublish ) {
				$hasRightsForPublish = rightOnParticularization( $particularization );
			}
		}
	} else {
		$hasRightsForPublish = rightOnParticularization( $pageOptions{$type}->{particularization} );	
	}

	$settings->{pub_type} = $type;
	$settings->{page_columns} = $pageOptions{ $type };
	$settings->{write_right} = right("write");
	$settings->{execute_right} = right("execute");
	$settings->{is_admin} = getUserRights( 
		entitlement => "admin_generic", 
		username => sessionGet('userid') 
	)->{admin_generic}->{write_right};
	
	$settings->{pageSettings} = getSessionUserSettings();
	$settings->{hasRightsForPublish} = $hasRightsForPublish;

	return $settings;
}


1;
