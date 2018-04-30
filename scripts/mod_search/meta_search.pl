#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::MetaSearch;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Users qw();
use Time::Local;
use Taranis qw(:all);
use strict;

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

	my $ms = Taranis::MetaSearch->new( Config );
	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );
	
	my $searchOk = 0;
	my $hitsperpage = 100;
	my $resultCount = 0;
	
	my $searchString = $kvArgs{search};
	my $searchSettings = $ms->dissectSearchString( $searchString );

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;
	
	if ( $searchSettings ) {
		my %searchDBSettings;
		$searchDBSettings{item}->{archive} = 0;
		$searchDBSettings{analyze}->{searchAnalyze} = 1;
		$searchDBSettings{publication}->{searchAllProducts} = 1;
		$searchDBSettings{publication_advisory}->{status} = 3;
		$searchDBSettings{publication_endofweek}->{status} = 3;
		$searchDBSettings{publication_endofshift}->{status} = 3;
		$searchDBSettings{publication_endofday}->{status} = 3;
		
		if ( $vars->{search_results} = $ms->search( $searchSettings, \%searchDBSettings ) ) {
			$searchOk = 1;
		}	else {
			$vars->{error} = $ms->{errmsg};
		}
	
		$resultCount = ( $searchOk ) ? scalar( @{ $vars->{search_results} } ) : 0;
		
		if ( $searchOk ) {

			my $startLength = ( $pageNumber - 1 ) * $hitsperpage;
			my $endOffset =  $pageNumber * $hitsperpage; 

			splice( @{ $vars->{search_results} }, $endOffset );	
			splice( @{ $vars->{search_results} }, 0, $startLength );
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
	
	my $ms = Taranis::MetaSearch->new( Config );
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

sub doAdvancedMetaSearch {
	my ( %kvArgs ) = @_;
	my ( $vars );
	
	my $ms = Taranis::MetaSearch->new( Config );
	my $tt = Taranis::Template->new;
	my $us = Taranis::Users->new( Config );
	
	my $searchOk = 0;
	my $hitsperpage = 100;
	my $resultCount = 0;

	my $searchString = $kvArgs{search};
	my $searchSettings = $ms->dissectSearchString( $searchString );

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	if ( $searchSettings ) {

		my %searchDBSettings;

		if ( exists( $kvArgs{startdate} ) && $kvArgs{startdate} =~ /^\d\d-\d\d-\d{4}$/ ) {
			$searchDBSettings{startDate} = ( checkDate( $kvArgs{startdate} ) ) ? $kvArgs{startdate}: undef;
		}
		if ( exists( $kvArgs{enddate} ) && $kvArgs{enddate} =~ /^\d\d-\d\d-\d{4}$/ ) {
			$searchDBSettings{endDate} = ( checkDate( $kvArgs{enddate} ) ) ? $kvArgs{enddate}: undef;
		}
		
		my %allowedFields = (
			as => [ 'category', 'source', 'status', 'archive' ],
			an => [ 'status', 'rating', 'searchAnalyze' ],
			pr => [ 'status', 'created_by', 'approved_by', 'published_by' ],
			adv => [ 'probability', 'damage', 'searchAdvisory' ],
			eow => [ 'searchEndOfWeek' ],
			eos => [ 'searchEndOfShift' ],
			eod => [ 'searchEndOfDay' ]
		);

		my $searchAssess = ( exists( $kvArgs{as_searchAssess} ) ) ? 1 : 0;
		my $searchPublications = ( exists( $kvArgs{pr_searchAllProducts} ) ) ? 1 : 0;
		
		FIELD:foreach my $field ( keys %kvArgs ) {
			next if ( 
				$field eq 'search' 
				|| $field eq 'startdate' 
				|| $field eq 'enddate' 
				|| $field eq 'hidden-page-number'  
				|| $kvArgs{$field} eq '' 
			);
			
			my $setting;
			
			$field =~ /^(.*?)_(.*)/i;
			
			my $prefix = $1;
			my $column_name = $2;

			for ( $prefix ) {
				if (/as/) {
					if ( $searchAssess && grep( /^$column_name$/, @{ $allowedFields{as} } ) ) {
						$setting = "item";	
					} else {
						next FIELD;
					}
				} elsif (/an/) {
					if ( grep( /^$column_name$/, @{ $allowedFields{an} } ) ) {
						$setting = "analyze";
					} else {
						next FIELD;
					}
				} elsif (/pr/) {
					if ( $searchPublications && grep( /^$column_name$/, @{ $allowedFields{pr} } ) ) {
						$setting = "publication";
					} else {
						next FIELD;
					}
				} elsif (/adv/) {
					if ( $searchPublications && grep( /^$column_name$/, @{ $allowedFields{adv} } ) ) {
						$setting = "publication_advisory";
					} else {
						next FIELD;
					}
				} elsif (/eow/) {
					if ( $searchPublications && grep( /^$column_name$/, @{ $allowedFields{eow} } ) ) {
						$setting = "publication_endofweek";
					} else {
						next FIELD;
					}
				} elsif (/eos/) {
					if ( $searchPublications && grep( /^$column_name$/, @{ $allowedFields{eos} } ) ) {
						$setting = "publication_endofshift";
					} else {
						next FIELD;
					}
				} elsif (/eod/) {
					if ( $searchPublications && grep( /^$column_name$/, @{ $allowedFields{eod} } ) ) {
						$setting = "publication_endofday";
					} else {
						next FIELD;
					}
				}
			}

			$searchDBSettings{$setting}->{$column_name} = $kvArgs{$field};
		}
		$searchDBSettings{publication}->{searchAllProducts} = 0;

		if ( $vars->{search_results} = $ms->search( $searchSettings, \%searchDBSettings ) ) {
			$searchOk = 1;
		}	else {
			$vars->{error} = $ms->{errmsg};
		}

		$resultCount = ( $searchOk ) ? scalar( @{ $vars->{search_results} } ) : 0;
		
		if ( $searchOk ) {

			my $startLength = ( $pageNumber - 1 ) * $hitsperpage;
			my $endOffset =  $pageNumber * $hitsperpage; 

			splice( @{ $vars->{search_results} }, $endOffset );	
			splice( @{ $vars->{search_results} }, 0, $startLength );
		}
		$vars->{filterButton} = 'btn-meta-search-advanced-search';
		$vars->{page_bar} = $tt->createPageBar( $pageNumber, $resultCount, $hitsperpage );
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

# expects a string as dd-mm-yyyy
sub checkDate {
	my ( $dateString ) = @_;

	$dateString =~ s/-//g;
	my ( $day, $month, $year ) = unpack( "A2 A2 A4", $dateString );
	
	eval{ 
	    timelocal(0,0,0,$day, $month-1, $year);
	};

	return ( $@ ) ? 0 : 1;
}
1;
