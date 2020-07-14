#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

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

#XXX Yaiks!
my %sessionCategoryIds;

sub _applicableCustomSearches($) {
	my $username = shift;

	my $assessCustomSearch = Taranis::AssessCustomSearch->new(Config);
	my $customSearches = $assessCustomSearch->loadCollection(created_by => $username, is_public => 1);

	my @applicableSearches;
	foreach my $customSearch (@$customSearches) {
		my $categories = $customSearch->{categories} || [];
		next if @$categories
			 && ! grep $sessionCategoryIds{$_->{id}}, @$categories;

		push @applicableSearches, $customSearch;
	}

	\@applicableSearches;
}

sub _status2uriw(@) {
	my @uriw  = (0, 0, 0, 0);
	$uriw[$_] = 1 for @_;
	join '', @uriw;
}

sub _uriw2status($) {
	my @uriw  = split //, $_[0];
	grep $uriw[$_], 0..3;
}


sub _allowed_categories(@) {
	my @categories = @_;

	@categories
	  ? [ grep $sessionCategoryIds{$_}, @categories ]
	  : [ keys %sessionCategoryIds ];
}

sub displayAssess {
	my %kvArgs = @_;
	my $vars;

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAssess   = Taranis::Assess->new( Config );
	my $oTaranisUsers    = Taranis::Users->new( Config );
	my $settings         = _assess_settings();

	my $userSettings = exists $kvArgs{searchkeywords} ? {} #XXX ?
	  : $oTaranisUsers->getUser( $settings->{userid} );

	my (@status, $uriw);
	if (exists $kvArgs{status}) {
		@status   = flat $kvArgs{status};
		$uriw     = _status2uriw @status;
	} elsif ($uriw = $userSettings->{uriw} ) {
		@status   = _uriw2status $uriw;
	} else {
		@status   = 0..3;
		$uriw     = '1111';
	}

	my $dateStart   = $userSettings->{date_start};
	my $dateStop    = $userSettings->{date_stop};
	my $hitsperpage = val_int $userSettings->{hitsperpage} || 100;
	my $sorting     = $userSettings->{assess_orderby} || 'created_desc';
	my $source      = [ flat $userSettings->{source} ];
	my @categories  = flat( $kvArgs{category} || $userSettings->{categoryid} );
	my $search      = $kvArgs{searchkeywords} || $userSettings->{search} || '';

	$vars->{search} = $search;
	$vars->{items}  = _assess_results(
		dateStart 	=> $dateStart,
		dateStop 	=> $dateStop,
		search 		=> $search,
		category 	=> \@categories,
		status 		=> \@status,
		hitsperpage => $hitsperpage,
		sources 	=> $source,
		sorting 	=> $sorting,
		assessObj 	=> $oTaranisAssess
	);

	if ($kvArgs{searchkeywords} || $kvArgs{status} ) {
		$oTaranisUsers->setUser(
			username  => $settings->{userid},
			datestart => formatDateTimeString($dateStart),
			datestop  => formatDateTimeString($dateStop),
			search    => $search,
			category  => (@categories ? "@categories" : undef),
			uriw      => $uriw,
			source    => (@$source ? "@$source" : undef),
			hitsperpage    => $hitsperpage,
			assess_orderby => $sorting,
		);
	}

	$vars->{standardSearchSettings} = {
		dateStart   => $dateStart,
		dateEnd     => $dateStop,
		hitsperpage => $hitsperpage,
		sorting     => $sorting,
		category    => "@categories",
		source      => "@$source",
		uriw        => $uriw,
	};

	$vars->{pageSettings} = $settings->{pageSettings};
	$vars->{sources}      = [ $oTaranisAssess->getDistinctSources( _allowed_categories ) ];
	$vars->{searches}     = _applicableCustomSearches($settings->{userid});
	$vars->{filterButton} = 'btn-assess-search';
	$vars->{resultCount}  = $oTaranisAssess->{result_count};
	$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
	$vars->{execute_right} = $settings->{execute_right};
	$vars->{write_right}   = $settings->{write_right};
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
	my %kvArgs = @_;
	my $vars;

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );
	my $settings    = _assess_settings();

	my $dateStart   = $kvArgs{startdate};
	my $dateStop    = $kvArgs{enddate};
	my $search      = $kvArgs{searchkeywords} || '';
	my $category    = val_int $kvArgs{category} ? [ val_int $kvArgs{category} ] : [];
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;
	my $pageNumber  = val_int $kvArgs{'hidden-page-number'} || 1;
	my $source      = $kvArgs{source} ? [ $kvArgs{source} ] : [];
	my $sorting     = $kvArgs{sorting} || '';

	my @status       = flat $kvArgs{item_status};
	my $lastInBatch  = $kvArgs{lastInBatch};
	my $firstInBatch = $kvArgs{firstInBatch};

	my $items = _assess_results(
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
	my $uriw = _status2uriw @status;

	$oTaranisUsers->setUser(
		username  => $settings->{userid},
		datestart => formatDateTimeString($dateStart),
		datestop  => formatDateTimeString($dateStop),
		search    => $search,
		category  => (@$category ? "@$category" : undef),
		uriw      => $uriw,
		source    => (@$source ? "@$source" : undef),
		hitsperpage    => $hitsperpage,
		assess_orderby => $sorting,
	);

	my $currentItemId = uri_escape( $kvArgs{currentItemID}, '+/');
	if ( ! exists $kvArgs{isPageRefresh} || $user->{assess_autorefresh}) {
		$vars->{filterButton} = 'btn-assess-search';
		$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
		$vars->{execute_right} = $settings->{execute_right};
		$vars->{write_right} = $settings->{write_right};
		$vars->{pageSettings} = $settings->{pageSettings};
		$vars->{renderItemContainer} = 1;
		$vars->{items} = $items;
		$vars->{resultCount} = $oTaranisAssess->{result_count};

		if ($lastInBatch) {
			my $htmlContent = $oTaranisTemplate->processTemplate('assess_items_list.tt', $vars, 1);

			return {
				 params => {
					newItemsHtml => $htmlContent
				}
			};
		}

		my $htmlContent = $oTaranisTemplate->processTemplate('assess.tt', $vars, 1);
		my $htmlFilters;

		if(exists $kvArgs{triggeredByPopstate}) {
			$vars->{standardSearchSettings} = {
				dateStart   => $dateStart,
				dateEnd     => $dateStop,
				hitsperpage => $hitsperpage,
				sorting     => $sorting,
				category    => "@$category",
				source      => "@$source",
				uriw        => $uriw,
			};
			$vars->{sources}  = [ $oTaranisAssess->getDistinctSources( _allowed_categories ) ];
			$vars->{searches} = _applicableCustomSearches($settings->{userid});
			$vars->{search}  = $search;

			$htmlFilters = $oTaranisTemplate->processTemplate('assess_filters.tt', $vars, 1);
		}

		return {
			content => $htmlContent,
			filters => $htmlFilters,
			params => {
				id => $currentItemId,
			}
		};
	} else {
		my $oldResultCount = val_int $kvArgs{resultCount} || 0;
		my $newItemsCount = $oTaranisAssess->{result_count} - $oldResultCount;

		return {
			params => {
				newItemsCount => $newItemsCount
			}
		}
	}
}

sub customSearch {
	my %kvArgs = @_;
	my $vars;

	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $settings    = _assess_settings();

	my $lastInBatch = $kvArgs{lastInBatch};
	my $searchId    = val_int $kvArgs{'custom-search-id'};

	my $items       = [];
	if ($searchId) {
		my $assessCustomSearch = Taranis::AssessCustomSearch->new(Config);
		my $searchSettings = $assessCustomSearch->getSearch($searchId);

		my $startDate = $searchSettings->{startdate_plainformat};
		my $endDate   = $searchSettings->{enddate_plainformat};

		$items = _assess_results(
			dateStart 	=> $startDate,
			dateStop 	=> $endDate,
			search 		=> $searchSettings->{keywords},
			category 	=> $searchSettings->{categories},
			status 		=> [ _uriw2status $searchSettings->{uriw} ],
			hitsperpage => val_int $searchSettings->{hitsperpage} || 100,
			pageNumber	=> val_int $kvArgs{'hidden-page-number'}  || 1,
			sources 	=> $searchSettings->{sources},
			sorting 	=> $searchSettings->{sortby},
			assessObj 	=> $oTaranisAssess,
			lastInBatch	=> $lastInBatch,
			firstInBatch => $kvArgs{firstInBatch},
		);

		$vars->{filterButton} = 'btn-custom-search' if $items;
	}

	my $oTaranisUsers = Taranis::Users->new( Config );
	my $user          = $oTaranisUsers->getUser( $settings->{userid} );
	my $currentItemId = uri_escape( $kvArgs{currentItemID}, '+/');

	if(! exists $kvArgs{isPageRefresh} || $user->{assess_autorefresh}) {
		$vars->{pageSettings} = $settings->{pageSettings};
		$vars->{addToPublicationOptions} = $settings->{addToPublicationOptions};
		$vars->{execute_right} = $settings->{execute_right};
		$vars->{write_right} = $settings->{write_right};
		$vars->{renderItemContainer} = 1;
		$vars->{items} = $items;
		$vars->{resultCount} = $oTaranisAssess->{result_count};

		if($lastInBatch) {
			my $htmlContent = $oTaranisTemplate->processTemplate('assess_items_list.tt', $vars, 1);

			return {
				 params => {
					newItemsHtml => $htmlContent
				}
			};
		}

		# add filters section when browser back button is used
		my $showCustomSearch = 0;
		my $htmlFilters;

		if ( exists $kvArgs{triggeredByPopstate} ) {
			$vars->{sources} = [ $oTaranisAssess->getDistinctSources( _allowed_categories ) ];
            $vars->{searches} = _applicableCustomSearches($settings->{userid});
			$vars->{customSearchID} = $searchId;

			$htmlFilters = $oTaranisTemplate->processTemplate('assess_filters.tt', $vars, 1),
			$showCustomSearch = 1;
		}

		return {
			content => $oTaranisTemplate->processTemplate('assess.tt', $vars, 1),
			filters => $htmlFilters,
			params => {
				id => $currentItemId,
				showCustomSearch => $showCustomSearch,
			}
		};
	}

	my $oldResultCount = val_int $kvArgs{resultCount} || 0;
	my $newItemsCount = $oTaranisAssess->{result_count} - $oldResultCount;

	return {
		params => {
			newItemsCount => $newItemsCount,
		}
	};
}

sub addToPublication {
	my %kvArgs = @_;
	my $message;

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
	my %kvArgs = @_;
	my $message;

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
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $oTaranisAssess = Taranis::Assess->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisTagging = Taranis::Tagging->new( Config );

	my $digest      = $kvArgs{id};
	my $insertNew   = $kvArgs{insertNew};
 	my $is_archived = $kvArgs{is_archived} || 0;
	my $item        = $oTaranisAssess->getItem( $digest, $is_archived );

	if ( $item ) {
		my $itemAnalysisRights = getUserRights( entitlement => "item_analysis",
			username => sessionGet('userid') )->{item_analysis};

		my %ia_categories;
		if (my $p = $itemAnalysisRights->{particularization} ) {
			$ia_categories{uc $_} = 1 for @$p;
		}

		$vars = _assess_settings();
		$vars->{renderItemContainer} = $insertNew;
		$vars->{item} = _format_record(
			record => $item,
			itemAnalysisCategories => \%ia_categories,
			itemAnalysisRights => $itemAnalysisRights
		);
		$vars->{item}{isCluster} = 0;

		my $tags = $oTaranisTagging->getTagsByItem($digest, 'item');
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
	my (%kvArgs) = @_;

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
	my %kvArgs = @_;
	$kvArgs{isPageRefresh} = 1;
	$kvArgs{isCustomSearch}==1 ? customSearch(%kvArgs) : search(%kvArgs);
}

sub displayAssessShortcuts {
	my %kvArgs = @_;
	my $oTaranisTemplate = Taranis::Template->new;
	my $dialogContent = $oTaranisTemplate->processTemplate( 'assess_shortcuts.tt', {}, 1);
	return { dialog => $dialogContent };
}

sub _assess_results {
	my %kvArgs = @_;

	my $oTaranisAssess = $kvArgs{assessObj};

	my $username = sessionGet('userid');
	my $itemAnalysisRights = getUserRights(entitlement => "item_analysis", username => $username)->{item_analysis};

	my %ia_categories;
	if(my $p = $itemAnalysisRights->{particularization} ) {
		$ia_categories{ uc $_ } = 1 for @$p;
	}

	my $hitsperpage = $kvArgs{hitsperpage} || 100;

	$oTaranisAssess->loadAssessCollection(
		startdate	=> $kvArgs{dateStart},
		enddate		=> $kvArgs{dateStop},
		search		=> $kvArgs{search},
		category	=> _allowed_categories(flat $kvArgs{category}),
		status		=> $kvArgs{status},
		source		=> $kvArgs{sources},
		sorting		=> $kvArgs{sorting},
	);

	$oTaranisAssess->{result_count} = 0;

	my (@results, %itemMap);
	tie my %clusterMap, "Tie::IxHash";

	while ( $oTaranisAssess->nextObject() ) {
		my $record = $oTaranisAssess->getObject();
		$record = _format_record( record => $record,
			itemAnalysisCategories => \%ia_categories,
			itemAnalysisRights => $itemAnalysisRights
		);
		my $digest = $record->{digest};

		push @results, $record;

		$record->{cluster_id} = undef if !$record->{cluster_enabled};

		if (my $cluster_id =  $record->{cluster_id}) {
			$clusterMap{$cluster_id}{$digest} = $record->{created};
		}

		if (my $matches = $record->{matching_keywords_json} ) {
			$record->{matching_keywords} = from_json($matches);
		}

		$itemMap{$digest} = $record;
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
		$firstInBatch = undef if $firstInBatch eq $item->{digest};
		next RESULT if $firstInBatch;

		my $cluster_map = $clusterMap{$item->{cluster_id}} || {};
		my $items_in_cluster = keys %$cluster_map;

		$item->{isCluster} = 0;
		$item->{itemsInClusterCount} = $items_in_cluster;

		if ( $item->{cluster_id} && $items_in_cluster > 1 ) {
			my $isSeed = 1;

			my @sortedClusterItemIdList = sort { $cluster_map->{$b} cmp $cluster_map->{$a} }
				keys %$cluster_map;

			unshift @sortedClusterItemIdList, pop @sortedClusterItemIdList;  #XXX ??

			my $seed   = $itemMap{ $sortedClusterItemIdList[0] };
			my $last   = $itemMap{ $sortedClusterItemIdList[1] };

			foreach my $clusteredItemId ( @sortedClusterItemIdList ) {
				next if $beenThere{$clusteredItemId}++;

				my $item_map = $itemMap{$clusteredItemId} or next;
				$itemsCount++ if $isSeed;

				if ( $startCounting ) {
					my %clusteredItem = (
						%$item_map,
						isSeed     => $isSeed,
						seedTime   => $seed->{created_epoch},
						seedTitle  => $seed->{title},
						seedDigest => $seed->{digest},
						isCluster  => 1,
						itemsInClusterCount => $items_in_cluster,
						lastUpdateTime      => $last->{created_epoch},
						lastUpdateTimestamp => $last->{created},
					);

					$clusteredItem{itemsCount} = $itemsCount if $isSeed;
					$count++ if $isSeed;

					push @processedItems, \%clusteredItem;
				}

				$startCounting = 1 if $clusteredItemId eq $lastInBatch;
				$isSeed = 0;
			}
		} else {
			$itemsCount++;

			if ( $startCounting ) {
				$count++;
				$item->{itemsCount} = $itemsCount;
				push @processedItems, $item;
			}
			$startCounting = 1 if $item->{digest} eq $lastInBatch;

		}
		last if $count == $hitsperpage;
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

sub _assess_settings {

	my $pageSettings = getSessionUserSettings();

	# Ugly left-over from old code: a global :-(
	%sessionCategoryIds = map +($_->{id} => 1),
		@{$pageSettings->{assess_categories} || []};

	# Publication Options

	my $eod_pub_type_id = Publication->getPublicationTypeId(eod => 'email');

	my @addToPublicationOptions;
	push @addToPublicationOptions, {
		publication_type => $eod_pub_type_id,
		publication_specifics => "media_exposure",
		display => "End-of-Day Media Exposure",
	};

	push @addToPublicationOptions, {
		publication_type => $eod_pub_type_id,
		publication_specifics => "vuln_threats",
		display => "End-of-Day Vulnerabilities and Threats",
	};

	push @addToPublicationOptions, {
		publication_type => $eod_pub_type_id,
		publication_specifics => "community_news",
		display => "End-of-Day Community News",
	};

	return {
		execute_right => right("execute"),
		write_right => right("write"),
		addToPublicationOptions => \@addToPublicationOptions,
		userid => sessionGet('userid'),
		pageSettings => $pageSettings,
	};
}

sub _format_record {
	my %kvArgs = @_;
	my $record = $kvArgs{record};

	my $ia_categories      = $kvArgs{itemAnalysisCategories} || {};
	my $itemAnalysisRights = $kvArgs{itemAnalysisRights};

	$record->{title} = trim( $record->{title} );
	$record->{item_analysis_right} = $itemAnalysisRights->{write_right}
		&& (!keys %$ia_categories || $ia_categories->{ uc( $record->{category} ) } )
		? 1 : 0;

	return $record;
}
1;
