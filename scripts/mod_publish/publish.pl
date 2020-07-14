#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:util);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::SessionUtil qw(right rightOnParticularization getSessionUserSettings);
use Taranis::Template;
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);

use HTML::Entities qw(decode_entities);
use Carp           qw(confess);

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
	website => {
		id_column_name     => "Advisory ID",
		title_column_name  => "Advisory title",
		table              => "publication_advisory_website",
		type_id            => ["govcertid", "version_str"],
		title_content      => ["pub_title"],
		particularization  => "advisory (website)",
		page_title         => "Advisory Website",
		pgp_setting        => "pgp_signing_advisory"
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

	my $pageNumber = val_int $kvArgs{'hidden-page-number'};
	my $type   = $pageOptions{$kvArgs{pub_type}} ? $kvArgs{pub_type} : "advisory";
	my $typeId = $oTaranisPublication->getPublicationTypeId( $pageOptions{$type}->{particularization} );
	
	if ( !$typeId ) {
		logErrorToSyslog("displayPublish: type id not found for type '$type', could be configuration error...");
		return { content => '<div>type id not found for type</div>', filters => '<div></div>' };
	}	
	
	my $vars = _getPublishSettings( type => $type );

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
		'js/publish_advisory_website.js',
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

sub _simplify_to_match($) {
	my $text = decode_entities($_[0] // '');
	for($text) {
		#XXX old input decoding bug?
		s/%([a-fA-F0-9][a-fA-F0-9])/pack "C", hex $1/eg;

		# PGP folds the lines, we simple ignore any space
		# PGP normalizes spaces, like \xA0. Which ones?  Simply ignore all
		s/\p{Space}//g;
	}
	$text;
}

sub checkPGPSigning {
	my %kvArgs = @_;
	my $publicationId = val_int $kvArgs{id};
	my $options       = $pageOptions{$kvArgs{publicationType}} or confess;
	my $text          = $kvArgs{publicationText} // '';

	my $table         = $options->{table};
	my $do_sign_flag  = $options->{pgp_setting};
	my $need_sign_pgp = uc(Config->{$do_sign_flag}) eq 'ON';

	my $message;
	if($need_sign_pgp) {
		$text =~ s/\r\n/\n/g;  # do not use trim_text: might disturb the msg
		$text =~ s/^\s*\n//;
		if($text =~ m/  -----BEGIN\ PGP\ SIGNED\ MESSAGE----- \n
						Hash:(?:.*?) \n
						(.* \n)
						-----BEGIN\ PGP\ SIGNATURE
					 /isx) {

			my $signed = $1;
			$signed    =~ s/^- -/-/gm; # PGP adds '- ' to lines with leading '-'
			my $got    = _simplify_to_match $signed;

			my $publication = Publication->getPublicationDetails(
				table => $table,
				"$table.publication_id" => $publicationId,
			);
			my $expect = _simplify_to_match $publication->{contents};

			if($expect ne $got) {
				$message = "The text of the publication was changed while "
				  . "signing. Therefore, the publication will not be sent.";
			}
		} else {
			$message = "The publication must be signed with PGP. Invalid "
			  . "or missing signature.";
		}
  	}
  	
  	return {
  		params => {
			message       => $message,
			pgpSigningOk  => !$message,
			publicationId => $publicationId,
  		}
  	};
}


sub _getPublishSettings {
	my %kvArgs = @_;
	my $type   = $kvArgs{type};

	my $hasRightsForPublish = 0;
	my $parts = $pageOptions{$type}->{particularization};
	if(ref $parts eq 'ARRAY') {
		$hasRightsForPublish ||= rightOnParticularization($_) for @$parts;
	} else {
		$hasRightsForPublish   = rightOnParticularization($parts);	
	}

	my $is_admin =  getUserRights(
		entitlement => "admin_generic",
		username => sessionGet('userid')
	)->{admin_generic}->{write_right};

	+ {
		pub_type      => $type,
		page_columns  => $pageOptions{$type},
		write_right   => right("write"),
		execute_right => right("execute"),
		is_admin      => $is_admin,
		pageSettings  => getSessionUserSettings(),
		hasRightsForPublish => $hasRightsForPublish,
	};
}


1;
