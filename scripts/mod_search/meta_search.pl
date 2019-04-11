#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use Taranis::MetaSearch;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Users qw();
use Time::Local;
use Taranis qw(:all);

sub _check_date($);

my @js = (
	'js/jquery.timepicker.min.js',
	'js/assess.js', 
	'js/assess_details.js', 
	'js/assess_filters.js',
	'js/assess2analyze.js',
	'js/analyze.js', 
	'js/analyze_filters.js',
	'js/analyze_details.js',
	'js/analysis2publication.js',
	'js/publications.js',
	'js/publications_filters.js',
	'js/publications_advisory.js',
	'js/publications_advisory_forward.js',
	'js/publications_eow.js',
	'js/publications_eod.js',
	'js/publications_eos.js',
	'js/publications_common_actions.js',
	'js/publish_details.js',
	'js/tab_in_textarea.js',
);

my @EXPORT_OK = qw( doMetaSearch showAdvancedSearchSettings doAdvancedMetaSearch );

sub meta_search_export {
	return @EXPORT_OK;
}

sub doMetaSearch {
	my ( %kvArgs ) = @_;	
	my ( $vars );

	my $ms = Taranis::MetaSearch->new;
	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );
	
	my $searchOk = 0;
	my $hitsperpage = 100;
	my $resultCount = 0;
	
	my $searchString = trim $kvArgs{search};
	my $pageNumber   = $kvArgs{'hidden-page-number'} && $kvArgs{'hidden-page-number'} =~ /^\d+$/
		? $kvArgs{'hidden-page-number'}
		: 1;
	
	if($searchString) {
		my $results = $ms->search(
			search_field => $searchString,
			item         => { searchArchive => 0 },
			analyze      => { searchAnalyze => 1 },
			publication  => { searchAllProducts => 1 },
			publication_advisory   => { status => 3 },
			publication_endofweek  => { status => 3 },
			publication_endofshift => { status => 3 },
			publication_endofday   => { status => 3 },
		);

		if($results) {
			$resultCount = @$results;
			$searchOk    = 1;

			my $page     = ($pageNumber - 1) * $hitsperpage;
			$vars->{search_results} = [ splice @$results, $page, $hitsperpage ];
		} else {
			$vars->{error} = $ms->{errmsg};
		}
	
		$vars->{filterButton} = 'btn-metasearch';
		$vars->{page_bar} = $tt->createPageBar( $pageNumber, $resultCount, $hitsperpage );
	}

	foreach my $status ( sort split( ",", Config->{analyze_status_options} ) ) {
		push @{ $vars->{an_status} }, trim( $status );
	}

	@{ $vars->{item_categories} } = @{ getSessionUserSettings()->{assess_categories} };
	@{ $vars->{item_sources} } = $ms->getDistinctSources();

	$us->getUsersList();
	while ( $us->nextObject() ) {
		push @{ $vars->{publication_users} }, $us->getObject();
	}

	my $htmlContent = $tt->processTemplate( 'meta_search.tt', $vars, 1 );
	my $htmlFilters = $tt->processTemplate( 'meta_search_filters.tt', $vars, 1 );

	return { 
		content => $htmlContent, 
		filters => $htmlFilters,
		js => \@js, 
		params => {
			advisoryPrefix => getSessionUserSettings()->{advisory_prefix},
			keywords => $ms->{keywords} || []
		}
	};
}

sub showAdvancedSearchSettings {
	my ( %kvArgs ) = @_;	
	my ( $vars );
	
	my $ms = Taranis::MetaSearch->new;
	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );
	
	foreach my $status ( sort split( ",", Config->{analyze_status_options} ) ) {
		push @{ $vars->{an_status} }, trim( $status );
	}

	@{ $vars->{item_categories} } = @{ getSessionUserSettings()->{assess_categories} };
	@{ $vars->{item_sources} } = $ms->getDistinctSources();

	$us->getUsersList();
	while ( $us->nextObject() ) {
		push @{ $vars->{publication_users} }, $us->getObject();
	}

	my $htmlContent = $tt->processTemplate( 'meta_search.tt', $vars, 1 );
	my $htmlFilters = $tt->processTemplate( 'meta_search_filters.tt', $vars, 1 );

	return { 
		content => $htmlContent, 
		filters => $htmlFilters,
		js => \@js
	};
}

my %search_groups = (
	as  => {group => 'item', fields =>
		[ qw/searchAssess category source status searchArchive/] },
	an  => {group => 'analyze', fields => [ qw/searchAnalyze status rating/ ]},
	pr  => {group => 'publication', fields => [ qw/status created_by approved_by published_by/ ]},
	adv => {group => 'publication_advisory',   fields => [ qw/searchAdvisory probability damage/ ]},
	eow => {group => 'publication_endofweek',  fields => [ qw/searchEndOfWeek/ ]},
	eos => {group => 'publication_endofshift', fields => [ qw/searchEndOfShift/ ]},
	eod => {group => 'publication_endofday',   fields => [ qw/searchEndOfDay/ ]},
);

sub doAdvancedMetaSearch {
	my ( %kvArgs ) = @_;
	my ( $vars );
	
	my $ms = Taranis::MetaSearch->new;
	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );
	
	my $searchOk = 0;
	my $hitsperpage = 100;
	my $resultCount = 0;

	my $searchString = trim $kvArgs{search};
	my $pageNumber   = $kvArgs{'hidden-page-number'} && $kvArgs{'hidden-page-number'} =~ /^\d+$/
		? $kvArgs{'hidden-page-number'}
		: 1;

	if($searchString) {
		my %search = (
			search_field => $searchString,
			publication  => { searchAllProducts => 0 },
		);

		if(my $start_date = _check_date($kvArgs{startdate})) {
			$search{start_time} = "$start_date 000000";
		}
		if(my $end_date = _check_date($kvArgs{enddate})) {
			$search{end_time} = "$end_date 235959";
		}

		foreach my $field (sort keys %kvArgs) {
			my $value = trim $kvArgs{$field}              or next;
			my ($prefix, $column) = split(/_/, $field, 2) or next;
			my $config = $search_groups{$prefix}          or next;
			grep $column eq $_, @{$config->{fields}}      or next;

			$search{$config->{group}}{$column} = $value;
		}

		my $results = $ms->search(%search);
		if($results) {
			$resultCount = @$results;
			$searchOk    = 1;

			my $page     = ($pageNumber - 1) * $hitsperpage;
			$vars->{search_results} = [ splice @$results, $page, $hitsperpage ];
		} else {
			$vars->{error} = $ms->{errmsg};
		}

		$vars->{filterButton} = 'btn-meta-search-advanced-search';
		$vars->{page_bar} = $tt->createPageBar($pageNumber, $resultCount, $hitsperpage);
	}

	my $htmlContent = $tt->processTemplate( 'meta_search.tt', $vars, 1 );
	
	return { 
		content => $htmlContent, 
		js => \@js, 
		params => {
			advisoryPrefix => getSessionUserSettings()->{advisory_prefix},
			keywords => $ms->{keywords} || []
		}
	};	
}

sub _check_date($) {
	my $dateString = shift or return;
	my ($day, $month, $year) = $dateString =~ /^(\d\d)-(\d\d)-(\d{4})$/
		or return;

	eval{ timelocal(0,0,0,$day, $month-1, $year) };

	return $@ ? undef : "$year$month$day";
}

1;
