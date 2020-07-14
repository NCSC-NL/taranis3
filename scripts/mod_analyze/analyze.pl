#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Tagging;
use Taranis::Users qw(getUserRights);
use Taranis::Template;
use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Publication;
use Taranis::Publication::Advisory;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Session qw(sessionGet);
use strict;

my @EXPORT_OK = qw(displayAnalyze searchAnalyze getAnalyzeItemHtml setOwnership checkOwnership unlinkItem);

my $config = Config;
my $oTaranisAnalysis = Taranis::Analysis->new($config);
my $oTaranisPublication = Taranis::Publication->new($config);
my $advisoryPrefix   = $config->{advisory_prefix};
my $advisoryIdLength = $config->{advisory_id_length};
my $settings;

sub analyze_export {
	return @EXPORT_OK;
}

sub displayAnalyze {
	my ( %kvArgs ) = @_;

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $vars = getAnalyzeSettings();
	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	my $status = ( exists( $kvArgs{status} ) ) ? $kvArgs{status} : '';
	
	$vars->{status} = $status;
	
	$vars->{collection} = getAnalyzeResults(
		page => $pageNumber,
		status => $status,
	);
	
	$vars->{renderItemContainer} = 1;
	$vars->{filterButton} = 'btn-analyze-search';
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, $oTaranisAnalysis->{result_count}, $oTaranisAnalysis->{limit} );
	
	my $htmlContent = $oTaranisTemplate->processTemplate('analyze.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('analyze_filters.tt', $vars, 1);
	
	my @js = (
		'js/publications_common_actions.js',
		'js/publications.js',
		'js/publications_advisory.js',
		'js/publications_advisory_forward.js',
		'js/analyze.js',
		'js/analyze_filters.js',
		'js/analyze_details.js',
		'js/assess_details.js',
		'js/assess2analyze.js',
		'js/analysis2publication.js',
	);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub searchAnalyze {
	my ( %kvArgs) = @_;

	my $oTaranisTemplate = Taranis::Template->new;

	my $vars = getAnalyzeSettings();

	my @rating     = flat $kvArgs{rating};
	my $pageNumber = val_int $kvArgs{'hidden-page-number'};

	my $status = ( exists( $kvArgs{status} ) ) ? $kvArgs{status} : '';	
	my $search = ( exists( $kvArgs{searchkeywords} ) ) ? trim( $kvArgs{searchkeywords} ) : undef;
	
	$vars->{collection} = getAnalyzeResults(
		page => $pageNumber,
		status => $status,
		rating => \@rating,
		search => $search,
	);
	
	$vars->{renderItemContainer} = 1;
	$vars->{filterButton} = 'btn-analyze-search';	
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, $oTaranisAnalysis->{result_count}, $oTaranisAnalysis->{limit} );
	
	my $htmlContent = $oTaranisTemplate->processTemplate('analyze.tt', $vars, 1);
	
	my @js = ('js/analyze.js');

	my $htmlFilters;
	if ( exists( $kvArgs{triggeredByPopstate} ) ) {
		$vars->{status} = $status;
		$vars->{search} = $search;
		$vars->{rating} = join('', @rating);
		$htmlFilters = $oTaranisTemplate->processTemplate('analyze_filters.tt', $vars, 1);
	}
	
	return { 
		content => $htmlContent,
		filters => $htmlFilters,
		js => \@js, 
		params => { yes => 1 } 
	};
}

sub getAnalyzeItemHtml {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $status );
	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	
	my $analysisId = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
	my $analysis = $oTaranisAnalysis->getRecordsById( table => 'analysis', id => $analysisId );
	
	if ( $analysis ) {
		$vars = getAnalyzeSettings();
		
		$vars->{renderItemContainer} = $insertNew;
		my $formattedAnalysis = formatAnalysisRecord( record => $analysis->[0] ); 
		$formattedAnalysis->{links} = $oTaranisAnalysis->getLinkedItems( $analysisId );
		$status = $formattedAnalysis->{status};
		$vars->{analysis} = $formattedAnalysis;

		my $tags = $oTaranisTagging->getTagsByItem( $analysisId, 'analysis' );
		$vars->{tags} = $tags;
		
		$tpl = 'analyze_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $analyzeItemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $analyzeItemHtml,
			analysisId => $analysisId,
			insertNew => $insertNew,
			status => $status
		} 
	};
}

sub checkOwnership {
	my ( %kvArgs ) = @_;
	
	my $message;
		
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
	my $analysisId = $kvArgs{id};
	
	my $owner = $oTaranisAnalysis->getOwnerShip( $analysisId );
	my $userIsOwner = 0;

	if ( defined( $owner ) && $owner eq sessionGet('userid') ) {
		$userIsOwner = 1;
	} else {
		$message = $oTaranisAnalysis->{errmsg};
	}

	return { 
		params => {
			owner => $owner,
			analysisId => $analysisId,
			message => $message,
			userIsOwner => $userIsOwner
		}
	};
}

sub setOwnership {
	my ( %kvArgs ) = @_;
	
	my $ownershipSet = 0;
	my $message;
		
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
	my $analysisId = $kvArgs{id};
	my $username = ( exists( $kvArgs{userIsOwner} ) && $kvArgs{userIsOwner} eq '0') 
		? sessionGet('userid')
		: undef;
	
	my ($action,$did) = $username ? ('take', 'Taken') : ('release', 'Released');
	my $analysisName = analysis_name $analysisId;

	if ( $oTaranisAnalysis->setOwnerShip( $username, $analysisId ) ) {
		$ownershipSet = 1;
		setUserAction(action => "$action analysis ownership", comment => "$did ownership of analysis $analysisName");
	}  else {
		$message = $oTaranisAnalysis->{errmsg};
		setUserAction(action => "$action analysis ownership", comment => "Got error '$message' while trying to $action ownership of analysis $analysisName");
	}
	
	return { 
		params => {
			ownershipSet => $ownershipSet,
			analysisId => $analysisId,
			message => $message
		}
	};
}

sub unlinkItem {
	my ( %kvArgs ) = @_;
	my $message;
	my $isUnlinked = 0;

	my $analysisId = $kvArgs{analysisid};
	my $itemId = $kvArgs{itemid};
	
	if ( 
		right("write") 
		&& $itemId =~ /^\d+$/
		&& $analysisId =~ /^\d+$/
	) {
		my $oTaranisAnalysis = Taranis::Analysis->new( Config );
		my $oTaranisAssess = Taranis::Assess->new( Config );
		
		my $item = $oTaranisAssess->getItem( $itemId );

		my $analysisName = analysis_name $analysisId;
		if ( $oTaranisAnalysis->unlinkItem( $item->{digest}, $analysisId ) ) {
			$oTaranisAssess->setItemStatus( digest => $item->{digest}, status => 1, ignore_waiting_room_status => 1 );
			$isUnlinked = 1;
			setUserAction(action => "unlinked item from analysis", comment => "unlinked '$item->{title}' from $analysisName");
		}  else {
			$message = $oTaranisAnalysis->{errmsg};
			setUserAction(action => "unlinked item from analysis", comment => "Got error '$message' while trying to unlinked '$item->{title}' from $analysisName");
		}
	}
	
	return { 
		params => {
			isUnlinked => $isUnlinked,
			analysisId => $analysisId,
			itemId => $itemId,
			message => $message
		}
	};
}

## HELPERS ##

sub getAnalyzeResults {
	my ( %kvArgs ) = @_;
	
	
	my $page = ( exists( $kvArgs{page} ) && $kvArgs{page} =~ /^\d+$/ ) ? $kvArgs{page} : 1;
	my $limit = $oTaranisAnalysis->{limit};
	my $offset = ( $page - 1 ) * $limit;
	
	my %collectionSettings = ( offset => $offset );
	
	$collectionSettings{search} = $kvArgs{search} if ( exists( $kvArgs{search} ) && $kvArgs{search} );
	$collectionSettings{rating} = $kvArgs{rating} if ( exists( $kvArgs{rating} ) && $kvArgs{rating} );
	
	my $status = ( exists( $kvArgs{status} ) ) ? $kvArgs{status} : '';
	
	my @searchStatus = @{ $settings->{pageSettings}->{analysis_status_options} };
	if ( $status ne '' ) {
		my $isStatusAllowed = 0;
		
		foreach my $allowedStatus ( @searchStatus ) {
			$isStatusAllowed = 1 if ( lc( $allowedStatus ) eq lc( $status ) );
		}
		
		if ( $isStatusAllowed  ) {
			@searchStatus = $status;	
		}
	}

	$collectionSettings{status} = \@searchStatus if ( @searchStatus );
	$oTaranisAnalysis->loadAnalysisCollection( %collectionSettings );

	my @collection;
	my @analysisIds;
	while ( $oTaranisAnalysis->nextObject() ) {
		my $record = $oTaranisAnalysis->getObject();
		push @analysisIds, $record->{id};
		push @collection, formatAnalysisRecord( record => $record );
	}

	my $linkedItemsBulk = $oTaranisAnalysis->getLinkedItemsBulk( 'ia.analysis_id' => \@analysisIds );
	for ( my $i = 0; $i < @collection; $i++ ) {
		if ( exists( $linkedItemsBulk->{ $collection[$i]->{orgid} } ) ) {
			$collection[$i]->{links} = $linkedItemsBulk->{ $collection[$i]->{orgid} };
		}
	}
	
	return \@collection;
}

sub formatAnalysisRecord {
	my ( %kvArgs ) = @_;

	my $analysis = {};
	my $record = $kvArgs{record};

	for ( $record->{rating} ) {
		if (/1/) { $analysis->{rating} = "low"; }
		elsif (/2/) { $analysis->{rating} = "medium"; }
		elsif (/3/) { $analysis->{rating} = "high"; }
		elsif (/4/) { $analysis->{rating} = "undefined"; }
	}
	
	$analysis->{orgid} = $record->{id};
	$analysis->{id} = analysis_name $record->{id};
	$analysis->{status} = ucfirst( lc( $record->{status} ) );
	$analysis->{created} = $record->{created};
	$analysis->{title} = $record->{title};
	$analysis->{opened_by} = $record->{opened_by};
	$analysis->{owned_by} = $record->{owned_by};
	$analysis->{openedbyfullname} = $record->{openedbyfullname};
	$analysis->{ownedbyfullname} = $record->{ownedbyfullname};
	$analysis->{sentAdvisory} = 0;
	
	my $comments = sanitizeInput( "newline_to_br", $record->{comments});
	$comments =~ s/\[\=\=\ /\<div\ class\=\"comments\"\>/gi;
	$comments =~ s/\ \=\=\](.*?)\<br\/?\>/<\/div\>/gi;
	$comments =~ s/\[\=\=\=\ /\<div\ class\=\"joinedAnalysis\"\>/gi;
	$comments =~ s/\ \=\=\=\](.*?)\<br\/?\>/<\/div\>/gi;

	# All own certids are translated to contain an internal advisory_pub id
	# which is then translated into a href by the template.

	my %seen;
	my @certids = grep ! $seen{$_}++,
		 $comments =~ /($advisoryPrefix-\d{4}-\d{$advisoryIdLength})/gi;

	my $published = $analysis->{publishedAdvisories} = [];
	foreach my $id (@certids) {
		my $advisory = $oTaranisPublication->getLatestAdvisoryVersion($id);

		my ($publicationType, $advisoryTable) = defined $advisory->{source}
		  ? (forward  => 'publication_advisory_forward')
		  : (advisory => 'publication_advisory');

		$comments =~ s/$id/$id\[$advisory->{publication_id}][$publicationType]/gi if $advisory;
		
		my $advisories = $oTaranisPublication->getPublishedPublicationsByAnalysisId( table => $advisoryTable, govcertid => $id, analysis_id => $record->{id} );

		push @$published, @$advisories if $advisories;
	}

	$analysis->{comments} = $comments;

	return $analysis;
}

sub getAnalyzeSettings {
	my $userId = sessionGet('userid');
	
	$settings->{write_right} = right("write");
	$settings->{pageSettings} = getSessionUserSettings();
	$settings->{is_admin} = getUserRights(
			entitlement => "admin_generic", 
			username => $userId
		)->{admin_generic}->{write_right};

	my $publication_rights = getUserRights( entitlement => "publication", username => $userId )->{publication};
	
	$settings->{publication_right} = 0;
	
	if ( $publication_rights->{write_right} ) {
		if ( $publication_rights->{particularization} ) {
			foreach my $right ( @{ $publication_rights->{particularization} } ) {
				if ( lc ( $right ) eq "advisory (email)" ) {
					$settings->{publication_right} = 1;
				}
				if ( lc ( $right ) eq "advisory (forward)" ) {
					$settings->{publication_right} = 1;
				}
			} 
		} else {
			$settings->{publication_right} = 1;
		}
	}
	
	return $settings;
}

1;
