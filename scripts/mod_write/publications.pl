#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Carp;
use CGI::Simple;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization getSessionUserSettings);
use Taranis::FunctionalWrapper qw(CGI Config Publication);
use Taranis::Tagging;
use Taranis::Template;
use Taranis::Publication;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);

my @EXPORT_OK = qw(
	displayPublicationOptions displayPublications deletePublication 
	searchPublications getPublicationItemHtml closePublication
	loadPublicationAttachment
);

sub publications_export {
	return @EXPORT_OK;
}

my %page_options = (
	advisory => {
		id_column_name		=> "Advisory ID", 
		title_column_name	=> "Advisory title", 
		table				=> "publication_advisory",
		type_id				=> [ "govcertid", "version_str" ],
		title_content		=> ["pub_title"],
		particularization	=> "advisory (email)",
		page_title			=> "Advisory"
	},
	forward => {
		id_column_name		=> "Advisory ID", 
		title_column_name	=> "Advisory title", 
		table				=> "publication_advisory_forward",
		type_id				=> [ "govcertid", "version_str" ],
		title_content		=> ["pub_title"],
		particularization	=> "advisory (forward)",
		page_title			=> "Forward Advisory"
	},
	eod => { 
		id_column_name		=> "Publication", 
		title_column_name	=> "Timeframe", 
		table				=> "publication_endofday",
		type_id				=> [ "pub_title"],
		title_content		=> ["timeframe_str"],
		particularization	=> "end-of-day (email)",
		page_title			=> "End-of-Day"
	},
	eos => { 
		id_column_name		=> "Publication",
		title_column_name	=> "Shift",
		table				=> "publication_endofshift",
		type_id				=> [ "pub_title" ],
		title_content		=> [ "timeframe_str" ],
		particularization	=> "end-of-shift (email)",
		page_title			=> "End-of-Shift"
	},
	eow	=> { 
		id_column_name		=> "Publication",
		title_column_name	=> "Created on",
		table				=> "publication_endofweek",
		type_id				=> [ "pub_title"],
		title_content		=> ["created_on_str"],
		particularization	=> "end-of-week (email)",
		page_title			=> "End-of-Week"
	},
);

my %statusDictionary = ( 
	0 => 'pending',
	1 => 'ready4review',
	2 => 'approved',
	3 => 'published',
	4 => 'sending'
);


sub displayPublicationOptions {
	my ( %kvArgs) = @_;
	my ( $vars );
	my $oTaranisTemplate = Taranis::Template->new;
	
	$vars->{pageSettings} = getSessionUserSettings();
	my $htmlContent = $oTaranisTemplate->processTemplate('publications_options.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('publications_options_filters.tt', $vars, 1);

	my @js = (
		'js/publications.js',
		'js/publish_details.js'
	);
	
	return { content => $htmlContent,  filters => $htmlFilters, js => \@js };
}


sub displayPublications {
	my ( %kvArgs) = @_;
	my ( $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	my $type = ( exists( $page_options{ $kvArgs{pub_type} } ) ) ? $kvArgs{pub_type} : "advisory";

	my $vars = getPublicationsSettings( type => $type ); 
		
	if ( $vars->{hasRightsForPublication} ) {
		my %searchFields = (
			pageNumber => $pageNumber, 
			table => $page_options{ $type }->{table},
			type => $type,
			oPublication => $oTaranisPublication
		);
		$vars->{publications} = getPublicationResults(%searchFields);

		$vars->{filterButton} = 'btn-publications-search';
		$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, getPublicationCount(%searchFields), 100 );
		$vars->{renderItemContainer} = 1;
		$vars->{page_title} = $page_options{ $type }->{page_title};

		$tpl = 'publications.tt';
	} else {
		$tpl = 'no_permission.tt';
	}

	my $htmlContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	my $htmlFilters = $oTaranisTemplate->processTemplate('publications_filters.tt', $vars, 1);
	
	my @js = (
		'js/jquery.timepicker.min.js',
		'js/publications.js',
		'js/publications_filters.js',
		'js/publications_advisory.js',
		'js/publications_advisory_forward.js',
		'js/publications_eow.js',
		'js/publications_eos.js',
		'js/publications_eod.js',
		'js/publications_common_actions.js',
		'js/publish_details.js',
		'js/cve.js',
		'js/tab_in_textarea.js'
	);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub searchPublications {
	my ( %kvArgs ) = @_;
	my ( $tpl, %extraSearchOptions );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	
	my $keywords = ( exists( $kvArgs{searchkeywords} ) ) ? $kvArgs{searchkeywords} : '';
	my $startDate = ( exists( $kvArgs{startdate} ) ) ? $kvArgs{startdate} : '';
	my $endDate = ( exists( $kvArgs{enddate} ) ) ? $kvArgs{enddate} : '';
	my $status = ( exists( $kvArgs{status} ) ) ? $kvArgs{status} : '';
	
	my $type = ( exists( $page_options{ $kvArgs{pub_type} } ) ) ? $kvArgs{pub_type} : "advisory";
		
	my $pageNumber  = val_int $kvArgs{'hidden-page-number'} || 1;
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;

	my $vars = getPublicationsSettings( type => $type ); 

	if ( $kvArgs{pub_type} =~ /^(advisory|advisory_forward)$/ ) {
		$extraSearchOptions{probability} = $kvArgs{probability} if ( exists( $kvArgs{probability} ) && $kvArgs{probability} =~ /^(1|2|3)$/ );
		$extraSearchOptions{damage} = $kvArgs{damage} if ( exists( $kvArgs{damage} ) && $kvArgs{damage} =~ /^(1|2|3)$/ );
	}

	if ( $vars->{hasRightsForPublication} ) {
		my %searchFields = (
			pageNumber => $pageNumber, 
			table => $page_options{ $type }->{table},
			type => $type,
			startDate => $startDate,
			endDate => $endDate,
			status => $status,
			hitsperpage => $hitsperpage,
			keywords => $keywords,
			extraSearchOptions => \%extraSearchOptions,
			oPublication => $oTaranisPublication
		);
		$vars->{publications} = getPublicationResults(%searchFields);

		$vars->{filterButton} = 'btn-publications-search';
		$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, getPublicationCount(%searchFields), $hitsperpage );
		$vars->{renderItemContainer} = 1;

		$tpl = 'publications.tt';
	} else {
		$tpl = 'no_permission.tt';
	}

	my $htmlContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		content => $htmlContent,
		params => { publicationType => $type }
	};
}

sub closePublication {
	my ( %kvArgs ) = @_;
	my $oTaranisPublication = Publication;
	
	my $userid = sessionGet('userid');
	my $id = $kvArgs{id};

	my $is_admin = getUserRights( 
		entitlement => "admin_generic", 
		username => $userid 
	)->{admin_generic}->{write_right};
	
	my $openedBy = $oTaranisPublication->isOpenedBy( $id );
	
	# closeByAdmin needs to be set explicitly
	if ( 
		( exists( $openedBy->{opened_by} ) && $openedBy->{opened_by} eq $userid ) 
		|| ( $is_admin && exists( $kvArgs{closeByAdmin} ) && $kvArgs{closeByAdmin} == 1 ) 
	) {
		$oTaranisPublication->closePublication( $id );
	}
	
	return {
		params => {
			id => $id
		}
	};
}

sub deletePublication {
	my ( %kvArgs ) = @_;
	my ( $message );
	my $deleteOk = 0;
	my $multiplePublicationsUpdated = 0;
	my $previousVersion = '';
	my $oTaranisPublication = Publication;
	
	undef $oTaranisPublication->{previousVersionId};
	undef $oTaranisPublication->{multiplePublicationsUpdated};
	
	if ( $kvArgs{del} =~ /^\d+$/ && right('write') ) {
		if ( !$oTaranisPublication->deletePublication( $kvArgs{del}, $kvArgs{pubType} ) ) {
			$message = $oTaranisPublication->{errmsg};
			setUserAction( action => 'delete publication', comment => "Got error '$message' while trying to delete publication of type '$kvArgs{pubType}' with ID $kvArgs{del}" );
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete publication', comment => "Deleted publication of type '$kvArgs{pubType}' with ID $kvArgs{del}" );
		}
	}
	if ( defined( $oTaranisPublication->{previousVersionId} ) && $oTaranisPublication->{previousVersionId} ) {
		$previousVersion = $oTaranisPublication->{previousVersionId};
		$oTaranisPublication->{previousVersionId} = undef;
	}
	
	$multiplePublicationsUpdated = ( defined( $oTaranisPublication->{multiplePublicationsUpdated} ) && $oTaranisPublication->{multiplePublicationsUpdated} ) ? 1 : 0;
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			publicationid => $kvArgs{publicationId},
			previousVersion => $previousVersion,
			multiplePublicationsUpdated => $multiplePublicationsUpdated
		}
	}
}


sub getPublicationItemHtml {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $publicationStatus );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	
	my $publicationId = $kvArgs{id};
	my $pubType = $kvArgs{pubType};
	my $insertNew = $kvArgs{insertNew};

	my $table = $page_options{$pubType}->{table};
	my $publication = $oTaranisPublication->getPublicationDetails( table => $table, $table . ".publication_id" => $publicationId );
 
	if ( $publication ) {
		$publicationStatus = $statusDictionary{ $publication->{status} };
		$vars = getPublicationsSettings( type => $pubType );
		
		foreach ( @{ $page_options{ $pubType }->{type_id} } ) {
			$publication->{specific_id} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A ";
		}

		foreach ( @{ $page_options{ $pubType }->{title_content} } ) {
			$publication->{title_content} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A ";
		}
			
		$publication->{statusDescription} = $statusDictionary{ $publication->{status} };
		$publication->{tname} = $table;

		$vars->{renderItemContainer} = $insertNew;
		$vars->{publication} = $publication;

		my $tags = $oTaranisTagging->getTagsByItem( $publication->{details_id}, $table );
		$vars->{tags} = $tags;
		
		$tpl = 'publications_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $publicationItemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $publicationItemHtml,
			publicationId => $publicationId,
			insertNew => $insertNew,
			publicationStatus => $publicationStatus
		}
	};
}

sub loadPublicationAttachment {
	my ( %kvArgs ) = @_;
	
	my $fileID = $kvArgs{fileID};
	
	if ( $fileID =~ /^\d+$/ ) {
		my $oTaranisPublication = Publication;
		my $attachment = $oTaranisPublication->getPublicationAttachments( id => $fileID )->[0];
		
		my $file;
		my $mode = $oTaranisPublication->{dbh}->{dbh}->{pg_INV_READ};
		
		withTransaction {
			my $lobj_fd = $oTaranisPublication->{dbh}->{dbh}->func( $attachment->{object_id}, $mode, 'lo_open');

			$oTaranisPublication->{dbh}->{dbh}->func( $lobj_fd, $file, $attachment->{file_size}, 'lo_read' );
		};

		print CGI->header(
			-type => $attachment->{mimetype},
			-content_disposition => qq{attachment; filename="$attachment->{filename}"},
			-content_length => $attachment->{file_size},
		);
		binmode STDOUT;
		print $file;
	}
}

### HELPERS ###
sub preprocessSearchFields {
	my ( %kvArgs ) = @_;
	
	my $table = $kvArgs{table};
	my $pageNumber = $kvArgs{pageNumber}; 
	my $hitsPerPage = val_int $kvArgs{hitsperpage} || 100;
	my $type = $kvArgs{type};
	my $keywords = ( exists( $kvArgs{keywords} ) ) ? $kvArgs{keywords} : '';  
	my $startDate = ( exists( $kvArgs{startDate} ) && validateDateString( $kvArgs{startDate} ) ) ?  formatDateTimeString( $kvArgs{startDate} ) : '';
	my $endDate = ( exists( $kvArgs{endDate} ) && validateDateString( $kvArgs{endDate} ) ) ?  formatDateTimeString( $kvArgs{endDate} ): '';
	my $extraSearchOptions = ( exists( $kvArgs{extraSearchOptions} ) ) ? $kvArgs{extraSearchOptions} : {};
	
	my $oTaranisPublication = $kvArgs{oPublication};
	
	my $publicationType = $oTaranisPublication->getPublicationTypeId( $page_options{ $type }->{particularization} );
	my $typeId = $publicationType && $publicationType->{id}
		or croak "getPublicationResults: type id not found for type '$type', could be configuration error...";

	my @status = flat $kvArgs{status};

	my %searchFields = (
		table => $table,
		status => \@status,
		start_date => $startDate,
		end_date => $endDate,
		date_column	=> "created_on",
		hitsperpage => $hitsPerPage,
		offset => ( $pageNumber - 1 ) * $hitsPerPage,
		search => $keywords,
		publicationType => $typeId,
		extraSearchOptions => $extraSearchOptions
	);

	return \%searchFields;
}

sub getPublicationResults {
	my (%kvArgs) = @_;

	my $searchFields = preprocessSearchFields(%kvArgs);
	my $type = $kvArgs{type};
	my $table = $kvArgs{table};
	my $oTaranisPublication = $kvArgs{oPublication};

	my $publications = $oTaranisPublication->loadPublicationsCollection(%$searchFields);

	foreach my $publication ( @$publications ) {
		foreach ( @{ $page_options{ $type }->{type_id} } ) {
			$publication->{specific_id} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A ";
		}
		
		foreach ( @{ $page_options{ $type }->{title_content} } ) {
			$publication->{title_content} .= ( $publication->{ $_ } ) ? $publication->{ $_ } . " " : "N/A ";
		}

		$publication->{statusDescription} = $statusDictionary{ $publication->{status} };
		$publication->{tname} = $table;
	}

	return $publications;
}

sub getPublicationCount {
	my (%kvArgs) = @_;

	my $searchFields = preprocessSearchFields(%kvArgs);
	my $oTaranisPublication = $kvArgs{oPublication};

	return $oTaranisPublication->publicationsCollectionCount(%$searchFields);
}

sub getPublicationsSettings {
	my ( %kvArgs ) = @_;
	my $settings = {};
	
	my $type = $kvArgs{type}; 
	
	my $hasRightsForPublication = 0;
	if ( ref( $page_options{$type}->{particularization} ) eq 'ARRAY' ) {
		foreach my $particularization ( @{ $page_options{$type}->{particularization} } ) {
			if ( !$hasRightsForPublication ) {
				$hasRightsForPublication = rightOnParticularization( $particularization );
			}
		}
	} else {
		$hasRightsForPublication = rightOnParticularization( $page_options{$type}->{particularization} );	
	}

	$settings->{pub_type} = $type;
	$settings->{page_columns} = $page_options{ $type };
	$settings->{write_right} = right("write");
	$settings->{execute_right} = right("execute");
	$settings->{is_admin} = getUserRights( 
		entitlement => "admin_generic", 
		username => sessionGet('userid') 
	)->{admin_generic}->{write_right};
	
	$settings->{pageSettings} = getSessionUserSettings();
	$settings->{hasRightsForPublication} = $hasRightsForPublication;
	
	return $settings;
}

1;
