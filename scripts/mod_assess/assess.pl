#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Users qw(getUserRights);
use Taranis::Assess;
use Taranis::Tagging;
use Taranis::Analysis;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Publication;
use Taranis::Template;
use Taranis::AssessCustomSearch;
use Taranis::Session qw(sessionGet);
use JSON;
use Tie::IxHash;
use strict;
use POSIX;
use URI::Escape;

use Data::Dumper;

my @EXPORT_OK = qw(
	displayAssess search customSearch addToPublication getAssessItemHtml 
	refreshAssessPage disableClustering getAddedToPublication
	displayAssessShortcuts
);

sub assess_export {
	return @EXPORT_OK;
}

my ( @assessCategoriesFromSession );

sub displayAssess {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $settings = getAssessSettings();
	
	my $userSettings = ( !exists( $kvArgs{searchkeywords} ) ) ? $oTaranisUsers->getUser( $settings->{userid} ) : {};

	my @status = ('0','1','2','3');
	my $uriw = '1111';
	if ( exists( $kvArgs{status} ) ) {
		@status = ( ref( $kvArgs{status} ) =~ /^ARRAY$/ )
			? @{ $kvArgs{status} }
			: $kvArgs{status};
		$uriw = '';
		
		for ( 0..3 ) {
			$uriw .= ( "@status" =~ /$_/ ) ? 1 : 0;
		}
		
	} elsif ( $userSettings->{uriw} ) {
		undef @status;
		$uriw = $userSettings->{uriw};
		
		foreach ( '0', '1', '2', '3' ) {
			push @status, $_ if ( substr( $userSettings->{uriw}, $_, 1 ) );
		}
	}
	
	my $dateStart = $userSettings->{date_start};
	my $dateStop = $userSettings->{date_stop};
	
	my $hitsperpage = val_int $userSettings->{hitsperpage} || 100;
	my $sorting	= $userSettings->{assess_orderby} || 'created_desc';
	my $source = ( $userSettings->{source} ) ? [ $userSettings->{source} ]: [];
	
	my $category = [];
	if ( $kvArgs{category} ) {
		$category = [ $kvArgs{category} ];
	} elsif ( $userSettings->{categoryid} ) {
		$category = [ $userSettings->{categoryid} ];
	}
	
	my $search = '';
	if ( exists( $kvArgs{searchkeywords} ) ) {
		$search = $kvArgs{searchkeywords};
	} elsif ( $userSettings->{search} ) {
		$search = $userSettings->{search};
	}
	
	$vars->{search} = $search;
	
	$vars->{items} = getAssessResults(
		dateStart 	=> $dateStart,
		dateStop 	=> $dateStop,
		search 		=> $search,
		category 	=> $category,
		status 		=> \@status,
		hitsperpage => $hitsperpage,
		sources 	=> $source,
		sorting 	=> $sorting,
		assessObj 	=> $oTaranisAssess
	);

	if ( exists( $kvArgs{searchkeywords} ) || exists( $kvArgs{status} ) ) {
		my %userSettings = ( username => $settings->{userid} );
		$userSettings{datestart} = ( $dateStart ) ? formatDateTimeString( $dateStart ) : undef;
		$userSettings{datestop} = ( $dateStop ) ? formatDateTimeString( $dateStop ) : undef;		
		$userSettings{search} = $search;
		$userSettings{category} = ( @$category ) ? "@$category" : undef;
		$userSettings{uriw} = $uriw;
		$userSettings{hitsperpage} = $hitsperpage;
		$userSettings{source} = ( @$source ) ? "@$source" : undef;
		$userSettings{assess_orderby} = $sorting;
	
		if ( !$oTaranisUsers->setUser( %userSettings ) ) {
			logErrorToSyslog( $oTaranisUsers->{errmsg} );
		}		
	}

	my %standardSearchSettings;
	$standardSearchSettings{dateStart} = $dateStart;
	$standardSearchSettings{dateEnd} = $dateStop;
	$standardSearchSettings{hitsperpage} = $hitsperpage;
	$standardSearchSettings{sorting} = $sorting;
	$standardSearchSettings{category} = "@$category";
	$standardSearchSettings{source} = "@$source";
	$standardSearchSettings{uriw} = $uriw;

	$vars->{standardSearchSettings} = \%standardSearchSettings;
	
	$vars->{pageSettings} = $settings->{pageSettings};
	@{ $vars->{sources} } = $oTaranisAssess->getDistinctSources( getAllowedCategories() );

	my $customSearches = $oTaranisAssessCustomSearch->loadCollection( created_by => $settings->{ userid }, is_public => 1 ); 

	CUSTOMSEARCH:
	foreach my $customSearch ( @$customSearches ) {
		if ( $customSearch->{categories} && @{ $customSearch->{categories} } > 0 ) {
			SEARCHCATEGORY:
			foreach my $searchCategory ( @{ $customSearch->{categories} } ) {
				foreach my $allowedCategory ( @assessCategoriesFromSession ) {
					next CUSTOMSEARCH if ( $allowedCategory->{id} eq $searchCategory->{id} );
				}
			}
			$customSearch = undef;
		} 
	}

	$vars->{searches} = $customSearches;

	$vars->{filterButton} = 'btn-assess-search';
	$vars->{resultCount} = $oTaranisAssess->{result_count};
	$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
	$vars->{execute_right} = $settings->{execute_right};
	$vars->{write_right} = $settings->{write_right};
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('assess.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('assess_filters.tt', $vars, 1);

	my @js = (
		'js/assess.js', 
		'js/assess_details.js', 
		'js/assess_filters.js',
		'js/assess2analyze.js',
		'js/analyze_details.js',
		'js/keyboard_shortcuts/assess.js',
	);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub search {
	my ( %kvArgs) = @_;
	my ( $vars, $currentItemId );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $settings = getAssessSettings();
	
	my $dateStart = ( exists( $kvArgs{startdate} ) && $kvArgs{startdate} =~ /\d\d-\d\d-\d\d\d\d/) 
		? $kvArgs{startdate} 
		: undef;
	my $dateStop = ( exists( $kvArgs{enddate} ) && $kvArgs{enddate} =~ /\d\d-\d\d-\d\d\d\d/ ) 
		? $kvArgs{enddate} 
		: undef;
		
	my $search = ( exists( $kvArgs{searchkeywords} ) ) ? $kvArgs{searchkeywords} : '';
	my $category = ( exists( $kvArgs{category} ) && $kvArgs{"category"} =~ /^\d+$/ ) 
		? [ $kvArgs{"category"} ] 
		: [];
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;
	my $pageNumber  = val_int $kvArgs{'hidden-page-number'} || 1;
	my $source = ( exists( $kvArgs{source} ) && $kvArgs{source} ) ? [ $kvArgs{source} ] : [];
	my $sorting = ( exists( $kvArgs{sorting} ) ) ? $kvArgs{sorting} : '';

	my @status = flat $kvArgs{item_status};
	my $lastInBatch = ( exists( $kvArgs{lastInBatch} ) ) ? $kvArgs{lastInBatch} : undef;
	my $firstInBatch = ( exists( $kvArgs{firstInBatch} ) ) ? $kvArgs{firstInBatch} : undef;
	
	my $items= getAssessResults( 
		dateStart 	=> $dateStart,
		dateStop 	=> $dateStop,
		search 		=> $search,
		category 	=> $category,
		status 		=> \@status,
		hitsperpage => $hitsperpage,
		pageNumber 	=> $pageNumber,
		sources 	=> $source,
		sorting 	=> $sorting,
		assessObj 	=> $oTaranisAssess,
		lastInBatch	=> $lastInBatch,
		firstInBatch => $firstInBatch
	);

	my $user = $oTaranisUsers->getUser( $settings->{userid} );

	my $checku = 0;
	my $checkr = 0;
	my $checki = 0;
	my $checkw = 0;	
	foreach ( @status ) {
		if (/^0$/) { $checku = 1 }
		if (/^1$/) { $checkr = 1 }
		if (/^2$/) { $checki = 1 }
		if (/^3$/) { $checkw = 1 }
	}

	my $uriw = "$checku";
	$uriw .= "$checkr";
	$uriw .= "$checki";
	$uriw .= "$checkw";
	
	my %userSettings = ( username => $settings->{userid} );
	$userSettings{datestart} = ( $dateStart ) ? formatDateTimeString( $dateStart ) : undef;
	$userSettings{datestop} = ( $dateStop ) ? formatDateTimeString( $dateStop ) : undef;
	$userSettings{search} = $search;
	$userSettings{category} = ( @$category ) ? "@$category" : undef;  #XXX bug
	$userSettings{uriw} = $uriw;
	$userSettings{hitsperpage} = $hitsperpage;
	$userSettings{source} = ( @$source ) ? "@$source" : undef;
	$userSettings{assess_orderby} = $sorting;

	if ( !$oTaranisUsers->setUser( %userSettings ) ) {
		logErrorToSyslog( $oTaranisUsers->{errmsg} );
	}

	$currentItemId = uri_escape( $kvArgs{currentItemID}, '+/');		

	if ( ( exists( $kvArgs{isPageRefresh} ) && $user->{assess_autorefresh} ) || !exists( $kvArgs{isPageRefresh} ) ) {

		$vars->{filterButton} = 'btn-assess-search';
		
		$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
		$vars->{execute_right} = $settings->{execute_right};
		$vars->{write_right} = $settings->{write_right};
		$vars->{pageSettings} = $settings->{pageSettings};
		
		$vars->{renderItemContainer} = 1;
		$vars->{items} = $items;
		$vars->{resultCount} = $oTaranisAssess->{result_count};
		
		if ( $lastInBatch ) {
			my $htmlContent = $oTaranisTemplate->processTemplate('assess_items_list.tt', $vars, 1);
			
			return { 
				 params => {
					newItemsHtml => $htmlContent
				}
			};		
			
		} else {
			my $htmlContent = $oTaranisTemplate->processTemplate('assess.tt', $vars, 1);
			
			my $htmlFilters;
			if ( exists( $kvArgs{triggeredByPopstate} ) ) {
				my %standardSearchSettings;
				$standardSearchSettings{dateStart} = $dateStart;
				$standardSearchSettings{dateEnd} = $dateStop;
				$standardSearchSettings{hitsperpage} = $hitsperpage;
				$standardSearchSettings{sorting} = $sorting;
				$standardSearchSettings{category} = "@$category";  #XXX bug
				$standardSearchSettings{source} = "@$source";
				$standardSearchSettings{uriw} = $uriw;
				$vars->{standardSearchSettings} = \%standardSearchSettings;

				@{ $vars->{sources} } = $oTaranisAssess->getDistinctSources( getAllowedCategories() );
			
				my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
				my $customSearches = $oTaranisAssessCustomSearch->loadCollection( created_by => $settings->{ userid }, is_public => 1 ); 
			
				CUSTOMSEARCH:
				foreach my $customSearch ( @$customSearches ) {
					if ( $customSearch->{categories} && @{ $customSearch->{categories} } > 0 ) {
						SEARCHCATEGORY:
						foreach my $searchCategory ( @{ $customSearch->{categories} } ) {
							foreach my $allowedCategory ( @assessCategoriesFromSession ) {
								next CUSTOMSEARCH if ( $allowedCategory->{id} eq $searchCategory->{id} );
							}
						}
						$customSearch = undef;
					} 
				}
			
				$vars->{searches} = $customSearches;
				$vars->{search} = $search;

				$htmlFilters = $oTaranisTemplate->processTemplate('assess_filters.tt', $vars, 1);
			}
			
			return { 
				content => $htmlContent,
				filters => $htmlFilters,
				params => {
					id => $currentItemId
				}
			};		
		}		
	} else {
		my $oldResultCount = ( exists( $kvArgs{resultCount} ) && $kvArgs{resultCount} =~ /^\d+$/ ) ? $kvArgs{resultCount} : 0; 
		my $newItemsCount = $oTaranisAssess->{result_count} - $oldResultCount;
		
		return {
			params => {
				newItemsCount => $newItemsCount 
			}
		}
	}
}

sub customSearch {
	my ( %kvArgs) = @_;
	my ( $vars, $currentItemId, $items, $lastInBatch );
	
	my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $settings = getAssessSettings();

	my $searchId = ( exists( $kvArgs{'custom-search-id'} ) && $kvArgs{'custom-search-id'} =~ /^\d+$/ ) 
		? $kvArgs{'custom-search-id'} 
		: undef; 

	if ( $searchId ) {
		my ( $category, $source, @status );
		
		my $searchSettings = $oTaranisAssessCustomSearch->getSearch( $searchId );

		@$category = @{ $searchSettings->{categories} };
		@$source	 = @{ $searchSettings->{sources} };

		push @status, "0" if ( substr( $searchSettings->{uriw}, 0, 1 ) eq "1" );
		push @status, "1" if ( substr( $searchSettings->{uriw}, 1, 1 ) eq "1" );
		push @status, "2" if ( substr( $searchSettings->{uriw}, 2, 1 ) eq "1" );
		push @status, "3" if ( substr( $searchSettings->{uriw}, 3, 1 ) eq "1" );
			
		my $startDate = $searchSettings->{startdate_plainformat};
		my $endDate = $searchSettings->{enddate_plainformat};
		my $keywords = $searchSettings->{keywords};
		my $sorting = $searchSettings->{sortby};
		my $hitsperpage  = val_int $searchSettings->{hitsperpage} || 100;
		my $pageNumber   = val_int $kvArgs{'hidden-page-number'}  || 1;

		$lastInBatch     = $kvArgs{lastInBatch};
		my $firstInBatch = $kvArgs{firstInBatch};
		
		$items = getAssessResults( 
			dateStart 	=> $startDate,
			dateStop 	=> $endDate,
			search 		=> $keywords,
			category 	=> $category,
			status 		=> \@status,
			hitsperpage => $hitsperpage,
			pageNumber	=> $pageNumber,
			sources 	=> $source,
			sorting 	=> $sorting,
			assessObj 	=> $oTaranisAssess,
			lastInBatch	=> $lastInBatch,
			firstInBatch => $firstInBatch
		);
		
		if ( $items ) {
			$vars->{filterButton} = 'btn-custom-search';
		}
		
	} else {
		$items = [];
	}
	
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $user = $oTaranisUsers->getUser( $settings->{userid} );
		
	$currentItemId = uri_escape( $kvArgs{currentItemID}, '+/');
			
	if ( ( exists( $kvArgs{isPageRefresh} ) && $user->{assess_autorefresh} ) || !exists( $kvArgs{isPageRefresh} ) ) {
		$vars->{pageSettings} = $settings->{pageSettings};
		$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
		$vars->{execute_right} = $settings->{execute_right};
		$vars->{write_right} = $settings->{write_right};
		$vars->{renderItemContainer} = 1;
		$vars->{items} = $items;
		$vars->{resultCount} = $oTaranisAssess->{result_count};

		if ( $lastInBatch ) {
			my $htmlContent = $oTaranisTemplate->processTemplate('assess_items_list.tt', $vars, 1);
			
			return { 
				 params => {
					newItemsHtml => $htmlContent
				}
			};
			
		} else {
			
			my $showCustomSearch = 0;
			
			# add filters section when browser back button is used
			my $htmlFilters;
			if ( exists( $kvArgs{triggeredByPopstate} ) ) {
			
				@{ $vars->{sources} } = $oTaranisAssess->getDistinctSources( getAllowedCategories() );
			
				my $oTaranisAssessCustomSearch = Taranis::AssessCustomSearch->new( Config );
				my $customSearches = $oTaranisAssessCustomSearch->loadCollection( created_by => $settings->{ userid }, is_public => 1 ); 
			
				CUSTOMSEARCH:
				foreach my $customSearch ( @$customSearches ) {
					if ( $customSearch->{categories} && @{ $customSearch->{categories} } > 0 ) {
						SEARCHCATEGORY:
						foreach my $searchCategory ( @{ $customSearch->{categories} } ) {
							foreach my $allowedCategory ( @assessCategoriesFromSession ) {
								next CUSTOMSEARCH if ( $allowedCategory->{id} eq $searchCategory->{id} );
							}
						}
						$customSearch = undef;
					} 
				}
				
				$vars->{searches} = $customSearches;
		
				$vars->{customSearchID} = $searchId;
		
				$htmlFilters = $oTaranisTemplate->processTemplate('assess_filters.tt', $vars, 1);
				$showCustomSearch = 1;
			}
			
			my $htmlContent = $oTaranisTemplate->processTemplate('assess.tt', $vars, 1);
			
			return { 
				content => $htmlContent,
				filters => $htmlFilters,
				params => {
					id => $currentItemId,
					showCustomSearch => $showCustomSearch
				}
			};
		}
	} else {
		my $oldResultCount = ( exists( $kvArgs{resultCount} ) && $kvArgs{resultCount} =~ /^\d+$/ ) ? $kvArgs{resultCount} : 0; 
		my $newItemsCount = $oTaranisAssess->{result_count} - $oldResultCount;
		
		return {
			params => {
				newItemsCount => $newItemsCount 
			}
		}		
	}
}

sub addToPublication {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $isAddedToPublication = 0;
	
	my $oTaranisAssess = Taranis::Assess->new( Config );

	my $itemDigest = $kvArgs{digest};
	my $publicationTypeId = $kvArgs{publicationTypeId};
	my $publicationSpecifics = $kvArgs{publicationSpecifics};

	my %check = ( 
		item_digest => $itemDigest,
		publication_type => $publicationTypeId,
		publication_specifics => $publicationSpecifics
	);

	my $action = ( $oTaranisAssess->{dbh}->checkIfExists( \%check, 'item_publication_type'))
		? 'removeFromPublication'
		: 'addToPublication'; 

	my $item = $oTaranisAssess->getItem( $itemDigest, 0 );
	if ( $oTaranisAssess->$action( $itemDigest, $publicationTypeId, $publicationSpecifics ) ) {
		$isAddedToPublication = 1;
		my $actionText = $action;
		$actionText =~ s/^(.*?)([A-Z].*?)([A-Z].*?)/$1 $2 $3/;
		setUserAction( action => lc( $actionText ), comment => ucfirst( lc( $actionText ) ) . " '$item->{title}'");
	} else {
		$message = $oTaranisAssess->{errmsg};
		my $actionText = $action;
		$actionText =~ s/^(.*?)([A-Z].*?)([A-Z].*?)/$1 $2 $3/;
		setUserAction( action => lc( $actionText ), comment => "Got error '$message' while trying to " . ucfirst( lc( $actionText ) ) . " item '$item->{title}'");
	}

	return { 
		params => { 
			action => $action,
			message => $message,
			isAddedToPublication => $isAddedToPublication,
			itemDigest => uri_escape( $itemDigest, '+/' ),
			publicationTypeId => $publicationTypeId,
			publicationSpecifics => $publicationSpecifics
		}
	};
}

sub disableClustering {
	my ( %kvArgs) = @_;
	my ( $message );
	
	my $oTaranisAssess = Taranis::Assess->new( Config );

	my $itemDigest = $kvArgs{id};

	my $item = $oTaranisAssess->getItem( $itemDigest, 0 );
	if ( !$oTaranisAssess->setAssessItem( digest => $itemDigest, cluster_enabled => 0 ) ) {
		$message = $oTaranisAssess->{errmsg};
		setUserAction( action => 'unlink item from cluster', comment => "Got error '$message' while trying to unlink '$item->{title}' from cluster");
	} else {
		setUserAction( action => 'unlink item from cluster', comment => "Unlinked '$item->{title}' from cluster");
	}

	return { 
		params => { 
			message => $message,
			itemDigest => uri_escape( $itemDigest, '+/' ),
			clusterId => uri_escape( $kvArgs{clusterId}, '+/' ),
			seedDigest => uri_escape( $kvArgs{seedDigest}, '+/' )
		}
	};
}

sub getAssessItemHtml {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisTagging = Taranis::Tagging->new( Config );
	
	my $digest = $kvArgs{id};

	my $insertNew = $kvArgs{insertNew};
 	my $is_archived = ( exists( $kvArgs{is_archived} ) ) ? $kvArgs{is_archived} : 0;
 	
	my $item = $oTaranisAssess->getItem( $digest, $is_archived );
	
	if ( $item ) {

		my $itemAnalysisRights = getUserRights( entitlement => "item_analysis", username => sessionGet('userid') )->{item_analysis};
		
		my %ia_categories;
		if ( $itemAnalysisRights->{particularization} ) {
			foreach my $cat ( @{ $itemAnalysisRights->{particularization} } ){
				$ia_categories{ uc( $cat ) } = 1;
			}
		}		
		
		$vars = getAssessSettings();
		
		$vars->{renderItemContainer} = $insertNew;
		$vars->{item} = formatAssessRecord( record => $item, itemAnalysisCategories => \%ia_categories, itemAnalysisRights => $itemAnalysisRights );
		$vars->{item}->{isCluster} = 0;
		
		my $tags = $oTaranisTagging->getTagsByItem( $digest, 'item' );
		$vars->{tags} = $tags;
		
		$tpl = 'assess_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $assessItemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $assessItemHtml,
			itemDigest => uri_escape( $digest, '+/' ),
			insertNew => $insertNew
		} 
	};	
}

sub getAddedToPublication {
	my ( %kvArgs ) = @_;
	
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my @itemDigests = $kvArgs{ids};

	my $publications = $oTaranisAssess->getAddedToPublicationBulk( item_digest => \@itemDigests );

	return {
		params => { 
			publications => $publications
		} 
	};
}

sub refreshAssessPage {
	my ( %kvArgs ) = @_;
	
	$kvArgs{isPageRefresh} = 1;
	
	if ( $kvArgs{isCustomSearch} =~ /^1$/ ) {
		return customSearch( %kvArgs );
	} else {
		return search( %kvArgs );
	}
}

sub displayAssessShortcuts {
	my ( %kvArgs ) = @_;
	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate( 'assess_shortcuts.tt', {}, 1);
	return { dialog => $dialogContent };
}

#### helper subs ####
sub getAssessResults {
	my ( %kvArgs ) = @_;
	
	my $oTaranisAssess = $kvArgs{assessObj};
	my ( @results, %itemMap, @itemDigests );
	tie my %clusterMap, "Tie::IxHash";
	 
	
	my $itemAnalysisRights = getUserRights( entitlement => "item_analysis", username => sessionGet('userid') )->{item_analysis};
	
	my %ia_categories;
	if ( $itemAnalysisRights->{particularization} ) {
		foreach my $cat ( @{ $itemAnalysisRights->{particularization} } ){
			$ia_categories{ uc( $cat ) } = 1;
		}
	}
	
	my $dateStart = ( exists( $kvArgs{dateStart} ) ) ? $kvArgs{dateStart} : undef;
	my $dateStop = ( exists( $kvArgs{dateStop} ) ) ? $kvArgs{dateStop} : undef;
	my $search = ( exists( $kvArgs{search} ) ) ? $kvArgs{search} : undef;
	my $status = ( exists( $kvArgs{status} ) ) ? $kvArgs{status} : undef;
	my $hitsperpage = ( exists( $kvArgs{hitsperpage} ) ) ? $kvArgs{hitsperpage} : 100;
	my $sources = ( exists( $kvArgs{sources} ) ) ? $kvArgs{sources} : undef;
	my $sorting = ( exists( $kvArgs{sorting} ) ) ? $kvArgs{sorting} : undef;
	my $category = ( exists( $kvArgs{category} ) ) ? $kvArgs{category} : [];

	$oTaranisAssess->loadAssessCollection(
		startdate	=> $dateStart, 
		enddate		=> $dateStop, 
		search		=> $search, 
		category	=> getAllowedCategories( @$category ),
		status		=> $status,  
		source		=> $sources,		
		sorting		=> $sorting 
	); 
	
	$oTaranisAssess->{result_count} = 0;
	
	while ( $oTaranisAssess->nextObject() ) {
		my $record = $oTaranisAssess->getObject();
		$record = formatAssessRecord( record => $record, itemAnalysisCategories => \%ia_categories, itemAnalysisRights => $itemAnalysisRights );
		
		push @results, $record;
		push @itemDigests, $record->{digest};
		
		$record->{cluster_id} = undef if ( !$record->{cluster_enabled} );
		
		if ( defined( $record->{cluster_id} ) ) {
			if ( exists( $clusterMap{ $record->{cluster_id} } ) ) {
				$clusterMap{ $record->{cluster_id} }->{ $record->{digest} } = $record->{created}; 	
			} else {
				$clusterMap{ $record->{cluster_id} } = { $record->{digest} => $record->{created} };
			}
		}
		
		if ( defined( $record->{matching_keywords_json} ) ) {
			$record->{matching_keywords} = from_json( $record->{matching_keywords_json} );
		}
		
		$itemMap{ $record->{digest} } = $record;
		$oTaranisAssess->{result_count}++;
	}

	my ( @processedItems, %beenThere );
	my $count = 0;
	my $lastInBatch   = $kvArgs{lastInBatch};
	my $firstInBatch  = $kvArgs{firstInBatch};
	my $startCounting = ! $lastInBatch;
	my $itemsCount = 0;
	
	RESULT:
	foreach my $item ( @results ) {
		$firstInBatch = undef if ( $firstInBatch eq $item->{digest} );
		next RESULT if ( $firstInBatch );
		
		$item->{isCluster} = 0;
		$item->{itemsInClusterCount} = keys %{ $clusterMap{ $item->{cluster_id} } };
		
		if ( $item->{cluster_id} && $item->{itemsInClusterCount} > 1 ) {
			my $isSeed = 1;
			
			my %test = %{ $clusterMap{ $item->{cluster_id} } };
			
			my @sortedClusterItemIdList = reverse sort( { $test{$a} cmp $test{$b} } keys %test );
			unshift @sortedClusterItemIdList, ( pop @sortedClusterItemIdList );

			my $seedTime = $itemMap{ $sortedClusterItemIdList[0] }->{created_epoch};
			my $seedTitle = $itemMap{ $sortedClusterItemIdList[0] }->{title};
			my $seedDigest = $itemMap{ $sortedClusterItemIdList[0] }->{digest};
			
			my $lastUpdateTime = $itemMap{ $sortedClusterItemIdList[1] }->{created_epoch};
			my $lastUpdateTimestamp = $itemMap{ $sortedClusterItemIdList[1] }->{created};

			foreach my $clusteredItemId ( @sortedClusterItemIdList ) {
				if ( exists( $itemMap{ $clusteredItemId } ) && !exists( $beenThere{$clusteredItemId} ) ) {
					$beenThere{$clusteredItemId} = 1;
					$itemsCount++ if ( $isSeed );
					
					if ( $startCounting ) {
						my %clusteredItem = %{ $itemMap{ $clusteredItemId } };
						
						$clusteredItem{itemsInClusterCount} = $item->{itemsInClusterCount};
						$clusteredItem{isCluster} = 1;
						$clusteredItem{isSeed} = $isSeed;
						
						$clusteredItem{seedTime} = $seedTime;
						$clusteredItem{seedTitle} = $seedTitle;
						$clusteredItem{seedDigest} = $seedDigest;
						$clusteredItem{lastUpdateTime} = $lastUpdateTime;
						$clusteredItem{lastUpdateTimestamp} = $lastUpdateTimestamp;

						$clusteredItem{itemsCount} = $itemsCount if ( $isSeed );
						$count++ if ( $isSeed );
						
						push @processedItems, \%clusteredItem;
					}

					$startCounting = 1 if ( $clusteredItemId eq $lastInBatch );
					$isSeed = 0;
				}
			}
		} else {
			$itemsCount++;
			
			if ( $startCounting ) {
				$count++;
				$item->{itemsCount} = $itemsCount;
				push @processedItems, $item;
			}
			$startCounting = 1 if ( $item->{digest} eq $lastInBatch );

		}
		last if ( $count == $hitsperpage );
		
	}

	my @digests          = map $_->{digest}, @processedItems;
    my $tags_per_digest  = Taranis::Tagging->new(Config)->getTagsForAssessDigests(\@digests);
	my $certs_per_digest = $oTaranisAssess->getCertidsForAssessDigests(\@digests);

	foreach my $item (@processedItems) {
		my $digest = $item->{digest};
		$item->{tags}    = $tags_per_digest->{$digest};
		$item->{certids} = $certs_per_digest->{$digest};
	}

	return \@processedItems;
}

sub getAssessSettings {
	my $userid = sessionGet('userid');
	
	my $pageSettings = getSessionUserSettings();

	@assessCategoriesFromSession = @{ $pageSettings->{assess_categories} };
	
	####### Add To Publication Options ########
	my $oTaranisPublication = Publication;
	my @addToPublicationOptions;

	my $eod_pub_type_name = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};
	my $eod_pub_type_id = $oTaranisPublication->getPublicationTypeId( $eod_pub_type_name )->{id}; 

	push @addToPublicationOptions, { 
		publication_type => $eod_pub_type_id, 
		publication_specifics => "media_exposure", 
		display => "End-of-Day Media Exposure"
		};
	
	push @addToPublicationOptions, { 
		publication_type => $eod_pub_type_id, 
		publication_specifics => "vuln_threats", 
		display => "End-of-Day Vulnerabilities and Threats"
		};

	push @addToPublicationOptions, { 
		publication_type => $eod_pub_type_id, 
		publication_specifics => "community_news", 
		display => "End-of-Day Community News"
		};

	##################################

	return { 
		execute_right => right("execute"),
		write_right => right("write"),
		addToPublicationOptions => \@addToPublicationOptions,
		userid => $userid,
		pageSettings => $pageSettings
	};	
} 

sub getAllowedCategories {
	my ( @categories ) = @_;
	
	my @allowedCategories;

	if ( @categories > 0 ) {
		foreach my $categoryId ( @categories ) {
			foreach my $allowedCategory ( @assessCategoriesFromSession ) {
				push @allowedCategories, $categoryId if ( $categoryId == $allowedCategory->{id} );
			}
		}
	} else {
		foreach my $allowedCategory ( @assessCategoriesFromSession ) {
			push @allowedCategories, $allowedCategory->{id};
		}
	}	
	
	return \@allowedCategories;
}

sub formatAssessRecord {
	my ( %kvArgs ) = @_;
	
	my $item = {};
	my $record = $kvArgs{record};

	my %ia_categories = %{ $kvArgs{itemAnalysisCategories} };
	my $itemAnalysisRights = $kvArgs{itemAnalysisRights};
	
	$record->{title} = trim( $record->{title} );
	$record->{description} = $record->{description}; 
	
	if ( $itemAnalysisRights->{write_right} ) {
		if( scalar( %ia_categories ) ) {
			if ( exists( $ia_categories{ uc( $record->{category} ) } ) ) {
				$record->{item_analysis_right} = 1;
			} else {
				$record->{item_analysis_right} = 0;
			}
		} else {
			$record->{item_analysis_right} = 1;
		}
	} else {
		$record->{item_analysis_right} = 0;
	}

	return $record;	
}
1;
