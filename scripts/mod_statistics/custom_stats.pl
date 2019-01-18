#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Statistics;
use Taranis::Category;
use Taranis::Config;
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw(:all);
use Tie::IxHash;
use JSON;
use HTML::Entities qw(decode_entities);
use strict;

my @EXPORT_OK = qw( displayCustomStats getCustomStats );

sub custom_stats_export {
	return @EXPORT_OK;
}

my $st = Taranis::Statistics->new();
my $noStatsFoundMessage = 'There are no statistics for the specified period. Please change &#39;Start date&#39; and/or &#39;End date&#39;';

sub displayCustomStats {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $st = Taranis::Statistics->new( Config );
		
	$vars->{analysisStatus} = getSessionUserSettings()->{analysis_status_options};
	$vars->{platforms} = $st->getListOfShPlatforms();

	$vars->{todaysDate} = nowstring( 5 );
	
	my @js = ( 'js/custom_stats.js' ); 
	my $htmlContent = $tt->processTemplate('custom_stats.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('custom_stats_filters.tt', $vars, 1);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub getCustomStats {
	my ( %kvArgs) = @_;
	my ( $message, $stats );
	
	if ( !$kvArgs{'stat'} ) {
		$message = 'illigal operation';
	} else {
		my $stat = $kvArgs{'stat'};
		my $sub = \&$stat; 
		
		eval {
			
			my $input = from_json( decode_entities( $kvArgs{input} ) );
	
			my $title = $kvArgs{title};
	
			$stats = $sub->( $input, $title );
		};
		
		if ( $@ ) {
			$message = 'Cannot find specified statistics.<br />' . $@;
		}
	}	
	
	return {
		params => {
			message => $message,
			stats => $stats
		}
	};
}



## ASSESS
sub itemsCollectedCategory {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	my $ca = Taranis::Category->new();

	my @categories = $ca->getCategory( 'is_enabled' => 1 );
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			my $clusters;
			
			# first: create clusters (and check if given dates are valid), second: get the statistics, third delete current statistics image
			# if one fails it will generate an error which will be sent to the browser
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getItemsCollectedPerCategoryClustered( $clusters, \@categories, $st->searchInArchive( $input->{startDate} ) ) ) 
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getTotalOfItemsCollectedPerCategory( $input->{startDate}, $input->{endDate}, \@categories, $st->searchInArchive( $input->{startDate} ) ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
					
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getItemsCollectedPerCategoryClustered( $clusters, \@categories, $st->searchInArchive( $input->{startDate} ) ) )
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutput( $stats, $title, 1, 1 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}

	return $toBrowser;
}

sub itemsCollectedStatus {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {

			if ( 
				( $stats = $st->getTotalOfItemsCollectedPerStatus() )
				&& $st->deletePreviousStatImages()
			) {
				
				foreach my $status ( keys %$stats ) {
					$stats->{$status} = { total => $stats->{$status} };					
				}
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getTotalOfItemsCollectedPerStatus() )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;					
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			if ( $stats = $st->getTotalOfItemsCollectedPerStatus() ) {
				
				foreach my $status ( keys %$stats ) {
					$stats->{$status} = { total => $stats->{$status} };					
				}
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutput( $stats, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;
}

sub itemsSources {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/pie/) {
			if ( 
				( $stats = $st->getSourcesMailed( $input->{startDate}, $input->{endDate}, $st->searchInArchive( $input->{startDate} ) ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			
			if ( $stats = $st->getSourcesMailed( $input->{startDate}, $input->{endDate}, $st->searchInArchive( $input->{startDate} ) ) ) {

				if ( scalar %$stats ) {
					
					my %statsForTextPresentation;
					tie %{ $statsForTextPresentation{'x times mailed'} }, "Tie::IxHash"; 
					
					foreach my $source ( keys %$stats ) {
						$statsForTextPresentation{'x times mailed'}->{$source} = $stats->{$source};
					}		
					
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}

	return $toBrowser;
}

## ANALYZE
sub analysesTotal {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAnalysesClustered( $clusters ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'bar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAnalysesClustered( $clusters ) ) 
			) {
				if ( scalar %$stats ) {
					
					my %statsForTextPresentation;
					tie %{ $statsForTextPresentation{Analyses} }, "Tie::IxHash";
					 
					foreach my $cluster ( keys %$stats ) {
						$statsForTextPresentation{Analyses}->{$cluster} = $stats->{$cluster} ;
					}
					
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;
}

sub analysesStatus {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	my $statuses = $input->{selectedStatusLeft};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {

			if ( 
				( $stats = $st->getTotalOfAnalysesPerStatus( $statuses ) )
				&&  $st->deletePreviousStatImages()
			) {
				
				foreach my $status ( keys %$stats ) {
					$stats->{$status} = { status => $stats->{$status} };
				}
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getTotalOfAnalysesPerStatus( $statuses ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			if ( $stats = $st->getTotalOfAnalysesPerStatus( $statuses ) ) {
				
				if ( scalar %$stats ) {
					my %statsForTextPresentation;
					tie %{ $statsForTextPresentation{Analyses} }, "Tie::IxHash"; 
					
					foreach my $status ( keys %$stats ) {
						$statsForTextPresentation{Analyses}->{$status} = $stats->{$status};
					}
									
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;
}

sub analysesCreatedClosed {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	my @statuses = $input->{selectedStatusLeft};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAnalysesCreatedClosed( $clusters, @statuses ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'bar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAnalysesCreatedClosed( $clusters, \@statuses ) ) 
			) {
				
				if ( scalar %$stats ) {
					my %statsForTextPresentation;
					tie %{ $statsForTextPresentation{Hours} }, "Tie::IxHash";
					 
					foreach my $cluster ( keys %$stats ) {
						$statsForTextPresentation{Hours}->{$cluster} = $stats->{$cluster} ;
					}
					
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;	
}

sub analysesSourcesUsed {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			if ( 
				( $stats = $st->getSourcesUsedInAnalyses( $input->{startDate}, $input->{endDate} ) ) 
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {				
					foreach my $source ( keys %$stats ) {
						$stats->{$source} = { sources => $stats->{$source} };					
					}				
					
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getSourcesUsedInAnalyses( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {	
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			if ( $stats = $st->getSourcesUsedInAnalyses( $input->{startDate}, $input->{endDate} ) ) {
				
				if ( scalar %$stats ) {
					my %statsForTextPresentation;
					
					tie %{ $statsForTextPresentation{Analyses} }, "Tie::IxHash";
					foreach my $status ( keys %$stats ) {
						$statsForTextPresentation{Analyses}->{$status} = $stats->{$status};
					}
	
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;
}

## ADVISORIES
sub advisoriesClassification {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	tie my %register, "Tie::IxHash";
	%register = ( 
		'H/H' => 1,
		'H/M' => 1,
		'H/L' => 1,
		'M/H' => 1,
		'M/M' => 1,
		'M/L' => 1,
		'L/H' => 1,
		'L/M' => 1,
		'L/L' => 1
	);
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByClassificationClustered( $clusters ) ) 
				&& $st->deletePreviousStatImages()
			) {
			
				my $statsFound = 0;
				
				tie my %statsForBarPresentation, "Tie::IxHash";
				
				foreach my $version ( keys %$stats ) {
					
					tie %{ $statsForBarPresentation{ $version } }, "Tie::IxHash";
					
					foreach my $cluster ( keys %{ $stats->{ $version } } ) {
						
						foreach my $classification ( keys %register ) {
			
							if ( exists( $stats->{ $version }->{ $cluster }->{ $classification } ) ) {
								push @{ $statsForBarPresentation{ $version }->{ $classification } }, $stats->{ $version }->{ $cluster }->{ $classification };
								$statsFound = 1;									 
							} else {
								push @{ $statsForBarPresentation{ $version }->{ $classification } }, '0';
							}
						}
					}
				}

				tie %{ $statsForBarPresentation{labels} }, "Tie::IxHash";
				$statsForBarPresentation{labels} = [ keys %{ $stats->{'1.00'} } ];

				if ( $statsFound ) {
					$toBrowser = $st->createBarPresentation( \%statsForBarPresentation, $title, 'stackedMultiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getAdvisoriesByClassification( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByClassificationClustered( $clusters ) )
			) {

				my $statsFound = 0;
				
				tie my %statsForTextPresentation, "Tie::IxHash";
				
				foreach my $version ( keys %$stats ) {

					tie %{ $statsForTextPresentation{ $version } }, "Tie::IxHash";
					
					foreach my $cluster ( keys %{ $stats->{ $version } } ) {
						
						tie %{ $statsForTextPresentation{ $version }->{ $cluster } }, "Tie::IxHash";
									
						foreach my $classification ( keys %register ) {
			
							if ( exists( $stats->{ $version }->{ $cluster }->{ $classification } ) ) {
								$statsForTextPresentation{ $version }->{ $cluster }->{ $classification } = $stats->{ $version }->{ $cluster }->{ $classification };
								$statsFound = 1;									 
							} else {
								$statsForTextPresentation{ $version }->{ $cluster }->{ $classification } = '0';
							}
						}
					}
				}

				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutputAdvisoriesByClassification( \%statsForTextPresentation, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}

	return $toBrowser;	
}

#TODO: fix x as label buiten plot area
sub advisoriesSentToCount {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	my @dates = split( ' ', $input->{selectedWeek} );
	
	my $startDate = $dates[0];
	my $endDate = $dates[2];

	for ( $input->{presentation} ) { 
		if (/bar/) {
		
			if ( 
				( $stats = $st->getAdvisoriesSentToCount( $startDate, $endDate	) ) 
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$st->{statImageHeight} += 150;
					$st->{xAxisFontAngleAlternative} = 70;
					
					$toBrowser = $st->createBarPresentation( $stats, $title, 'bar', 1 );
					
					$st->{xAxisFontAngleAlternative} = 30;
					$st->{statImageHeight} -= 150;
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			if ( $stats = $st->getAdvisoriesSentToCount( $startDate, $endDate ) ) {
				if ( scalar %$stats ) {				
					my %statsForTextPresentation;
					
					tie %{ $statsForTextPresentation{'nr of adressess'} }, "Tie::IxHash";
					foreach my $advisory ( keys %$stats ) {
						$statsForTextPresentation{'nr of adressess'}->{$advisory} = $stats->{$advisory};
					}
	
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;
}

sub advisoriesAuthor {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByAuthorClustered( $clusters ) ) 
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {	
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar', '0' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getAdvisoriesByAuthor( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {	
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
				
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByAuthorClustered( $clusters ) ) 
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutput( $stats, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;	
}

sub advisoriesDate {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, 'week' ) )
				&& ( $stats = $st->getAdvisoriesByDate( $clusters, 'bar' ) ) 
				&& $st->deletePreviousStatImages()
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar', '0' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			my $clusters;
			if (
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, 'week' ) ) 
				&& ( $stats = $st->getAdvisoriesByDate( $clusters, 'pie' ) )
				&& $st->deletePreviousStatImages()
			) {
				
				my $statsFound = 0;
				
				foreach my $count ( values %$stats ) {
					$statsFound = 1 if ( $count );
				} 
				
				if ( $statsFound ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
				
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, 'week' ) )
				&& ( $stats = $st->getAdvisoriesByDate( $clusters, 'text' ) ) 
			) {
				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutput( $stats, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;	
}

sub advisoriesPlatform {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByPlatformClustered( $clusters, $input->{selectedPlatforms} ) ) 
				&& $st->deletePreviousStatImages()
			) {
				
				my $statsFound = 0;

				tie my %statsForBarPresentation, "Tie::IxHash";
				
				my $firstRun = 1;
				foreach my $platform ( keys %$stats ) {
					
					tie %{ $statsForBarPresentation{ $platform } }, "Tie::IxHash" if ( $firstRun );
					
					foreach my $cluster ( @$clusters ) {
						
						if ( !exists( $stats->{ $platform }->{ $cluster->{cluster} } ) ) {
							$statsForBarPresentation{ $platform }->{ $cluster->{cluster} } = 0;
						} else {
							$statsForBarPresentation{ $platform }->{ $cluster->{cluster} } = $stats->{ $platform }->{ $cluster->{cluster} };
							$statsFound = 1;
						}

					}
					$firstRun = 1;
				}

				if ( $statsFound ) {
					$toBrowser = $st->createBarPresentation( \%statsForBarPresentation, $title, 'multiBar', '0' );

				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			
			my $clusters;
			
			if (
				( $stats = $st->getAdvisoriesByPlatform( $input->{startDate}, $input->{endDate}, $input->{selectedPlatforms} ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {

			my $clusters;
						
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByPlatformClustered( $clusters, $input->{selectedPlatforms} ) ) 
			) {
				
				my $statsFound = 0;
				
				tie my %statsForTextPresentation, "Tie::IxHash";
				
				foreach my $platform ( keys %$stats ) {
					
					tie %{ $statsForTextPresentation{ $platform } }, "Tie::IxHash";
					
					foreach my $cluster ( @$clusters ) {

						if ( !exists( $stats->{ $platform }->{ $cluster->{cluster} } ) ) {
							$statsForTextPresentation{ $platform }->{ $cluster->{cluster} } = 0;
						} else {
							$statsForTextPresentation{ $platform }->{ $cluster->{cluster} } = $stats->{ $platform }->{ $cluster->{cluster} };
							$statsFound = 1;
						}
						
						$statsForTextPresentation{ $platform }->{ $cluster->{cluster} } = 
									( !exists( $stats->{ $platform }->{ $cluster->{cluster} } ) ) ? 0 : $stats->{ $platform }->{ $cluster->{cluster} };
					}
				}
				
				if ( $statsFound ) {
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;	
}

sub advisoriesShType {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesPerShTypeClustered( $clusters ) ) 
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					tie my %statsForBarPresentation, "Tie::IxHash";
					
					foreach my $shType ( keys %$stats ) {
						
						tie %{ $statsForBarPresentation{ $shType } }, "Tie::IxHash";
						
						foreach my $cluster ( @$clusters ) {
							
							$statsForBarPresentation{ $shType }->{ $cluster->{cluster} } = 
								( !exists( $stats->{ $shType }->{ $cluster->{cluster} } ) ) ? 0 : $stats->{ $shType }->{ $cluster->{cluster} };
						}
					}

					$toBrowser = $st->createBarPresentation( \%statsForBarPresentation, $title, 'multiBar', '0' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
		
			if ( 
				( $stats = $st->getAdvisoriesPerShType( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {

			my $clusters;
						
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesPerShTypeClustered( $clusters ) ) 
			) {

				if ( scalar %$stats ) {
					tie my %statsForTextPresentation, "Tie::IxHash";
					
					foreach my $shType ( keys %$stats ) {
						
						tie %{ $statsForTextPresentation{ $shType } }, "Tie::IxHash";
						
						foreach my $cluster ( @$clusters ) {
							
							$statsForTextPresentation{ $shType }->{ $cluster->{cluster} } = 
								( !exists( $stats->{ $shType }->{ $cluster->{cluster} } ) ) ? 0 : $stats->{ $shType }->{ $cluster->{cluster} };
						}
					}

					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;	
}

sub advisoriesConstituentType {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesPerConstituentTypeClustered( $clusters ) ) 
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					tie my %statsForBarPresentation, "Tie::IxHash";
					
					foreach my $constituentType ( keys %$stats ) {
						
						tie %{ $statsForBarPresentation{ $constituentType } }, "Tie::IxHash";
						
						foreach my $cluster ( @$clusters ) {
							
							$statsForBarPresentation{ $constituentType }->{ $cluster->{cluster} } = 
								( !exists( $stats->{ $constituentType }->{ $cluster->{cluster} } ) ) ? 0 : $stats->{ $constituentType }->{ $cluster->{cluster} };
						}
					}
	
					$toBrowser = $st->createBarPresentation( \%statsForBarPresentation, $title, 'multiBar', '0' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
		
			if ( 
				( $stats = $st->getAdvisoriesPerConstituentType( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {

			my $clusters;
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesPerConstituentTypeClustered( $clusters ) ) 
			) {
				
				if ( scalar %$stats ) {
					tie my %statsForTextPresentation, "Tie::IxHash";
					
					foreach my $constituentType ( keys %$stats ) {
						
						tie %{ $statsForTextPresentation{ $constituentType } }, "Tie::IxHash";
						
						foreach my $cluster ( @$clusters ) {
							
							$statsForTextPresentation{ $constituentType }->{ $cluster->{cluster} } = 
								( !exists( $stats->{ $constituentType }->{ $cluster->{cluster} } ) ) ? 0 : $stats->{ $constituentType }->{ $cluster->{cluster} };
						}
					}

					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;		
}

sub advisoriesDamage {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};
	
	for ( $input->{presentation} ) { 
		if (/line/) {
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByDamageDescriptionClustered( $clusters ) ) 
				&& $st->deletePreviousStatImages()
			) {

				if ( scalar %$stats ) {
					tie my %statsForBarPresentation, "Tie::IxHash";
	
					my $firstRun = 1;
					foreach my $damageDescription ( keys %$stats ) {
						
						foreach my $cluster ( @$clusters ) {
							
							push @{ $statsForBarPresentation{labels} } , $cluster->{cluster} if ( $firstRun );
							
							if ( exists( $stats->{ $damageDescription }->{ $cluster->{cluster} } ) ) {
								push @{ $statsForBarPresentation{ $damageDescription } }, $stats->{ $damageDescription }->{ $cluster->{cluster} };									 
							} else {
								push @{ $statsForBarPresentation{ $damageDescription } }, '0';
							}
						}
						$firstRun = 0;
					}

					$toBrowser = $st->createMultiLineChart( \%statsForBarPresentation, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/pie/) {
			if ( 
				( $stats = $st->getAdvisoriesByDamageDescription( $input->{startDate}, $input->{endDate} ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createPieChart( $stats, $title );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		} elsif (/text/) {
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getAdvisoriesByDamageDescriptionClustered( $clusters ) )
			) {

				if ( scalar %$stats ) {
					tie my %statsForTextPresentation, "Tie::IxHash";
	
					my $firstRun = 1;
					foreach my $damageDescription ( keys %$stats ) {
						
						tie %{ $statsForTextPresentation{ $damageDescription } }, "Tie::IxHash";
						
						foreach my $cluster ( @$clusters ) {
							
							if ( exists( $stats->{ $damageDescription }->{ $cluster->{cluster} } ) ) {
								$statsForTextPresentation{ $damageDescription }->{ $cluster->{cluster} } = $stats->{ $damageDescription }->{ $cluster->{cluster} };									 
							} else {
								$statsForTextPresentation{ $damageDescription }->{ $cluster->{cluster} } = '0';
							}
						}
						$firstRun = 0;
					}
				
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 1, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}

	return $toBrowser;		
}

## OTHER
sub otherPublicationCreatedPublished {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getPublicationsTimeTillPublished( $clusters ) )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			my $clusters;
			
			if ( 
				( $clusters = $st->createClusters( $input->{startDate}, $input->{endDate}, $input->{clustering} ) )
				&& ( $stats = $st->getPublicationsTimeTillPublished( $clusters ) ) 
			) {
				
				if ( scalar %$stats ) {
					$toBrowser = $st->createTextOutput( $stats, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}

			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;
}

sub otherSentToConstituentsPhotoUsage {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	my @dates = split( ' ', $input->{selectedWeek} );
	
	my $startDate = $dates[0];
	my $endDate = $dates[2];

	for ( $input->{presentation} ) { 
		if (/bar/) {
		
			if ( 
				( $stats = $st->getSentToConstituentsPhotoUsage( $startDate, $endDate	) ) 
				&& $st->deletePreviousStatImages()
			) {
				
				my $statsFound = 0;

				tie my %statsForBarPresentation, "Tie::IxHash";
				tie my %advisories, "Tie::IxHash";
				
				foreach my $photoOption ( keys %$stats ) {
					foreach my $advisory ( keys %{ $stats->{ $photoOption } } ) {
						$advisories{ $advisory } = 'dummy';
					}
				} 
				
				foreach my $photoOption ( keys %$stats ) {
					foreach my $advisory ( keys %advisories ) {
						if ( exists( $stats->{ $photoOption }->{ $advisory } ) ) {
							push @{ $statsForBarPresentation{ $photoOption } }, $stats->{ $photoOption }->{ $advisory };
							$statsFound = 1;
						} else {
							push @{ $statsForBarPresentation{ $photoOption } }, '0';
						}
					}
				}				
					
				if ( $statsFound ) {
					$statsForBarPresentation{labels} = [ keys %advisories ];
	
					$st->{statImageHeight} += 150;
					$st->{xAxisFontAngleAlternative} = 70;
	
					$toBrowser = $st->createBarPresentation( \%statsForBarPresentation, $title, 'percentageBar', 1 );
	
					$st->{xAxisFontAngleAlternative} = 30;
					$st->{statImageHeight} -= 150;
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}				
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			if ( $stats = $st->getSentToConstituentsPhotoUsage( $startDate, $endDate ) ) {
				
				my $statsFound = 0;
				tie my %statsForBarPresentation, "Tie::IxHash";
				tie my %advisories, "Tie::IxHash";
				
				foreach my $photoOption ( keys %$stats ) {
					foreach my $advisory ( keys %{ $stats->{ $photoOption } } ) {
						$advisories{ $advisory } = 'dummy';
					}
				} 
				
				foreach my $photoOption ( keys %$stats ) {
					foreach my $advisory ( keys %advisories ) {
						if ( exists( $stats->{ $photoOption }->{ $advisory } ) ) {
							$statsForBarPresentation{ $photoOption }->{ $advisory } = $stats->{ $photoOption }->{ $advisory };
							$statsFound = 1;
						} else {
							$statsForBarPresentation{ $photoOption }->{ $advisory } = '0';
						}
					}
				}						
				
				if ( $statsFound ) {
					$toBrowser = $st->createTextOutput( \%statsForBarPresentation, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}	
		}
	}
	
	return $toBrowser;	
}

sub otherTop10ShConstituents {
	my ( $input, $title ) = @_;
	my ( $stats, $toBrowser );
	undef $st->{statInfo};

	for ( $input->{presentation} ) { 
		if (/bar/) {
			
			if ( 
				( $stats = $st->getTop10ShConstituents() )
				&& $st->deletePreviousStatImages()
			) {
				
				if ( scalar %$stats ) {
					foreach my $sh ( keys %$stats ) {
						$stats->{$sh} = { 'Software / Hardware' => $stats->{$sh} };					
					}		
					
					$toBrowser = $st->createBarPresentation( $stats, $title, 'multiBar' );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}
		} elsif (/text/) {
			
			my $clusters;
			
			if ( $stats = $st->getTop10ShConstituents() ) {
				if ( scalar %$stats ) {
					my %statsForTextPresentation;
					
					tie %{ $statsForTextPresentation{'Software / Hardware'} }, "Tie::IxHash";
					foreach my $sh ( keys %$stats ) {
						$statsForTextPresentation{'Software / Hardware'}->{$sh} = $stats->{$sh};
					}
	
					$toBrowser = $st->createTextOutput( \%statsForTextPresentation, $title, 0, 0 );
				} else {
					$toBrowser->{error} = $noStatsFoundMessage;
				}
			} else {
				$toBrowser->{error} = $st->{errmsg};
			}			
		}
	}

	return $toBrowser;
}

## chart editing functions
sub rotatePieChart {
	my ( $input ) = @_;
	my $toBrowser;
	
	undef $st->{statInfo};

	my $statsData = $st->order_from_json( $input->{stats}, $input->{jsonHashOrder} );
	
	$st->{pieChartRotateAngle} += 45;
	
	if ( $st->deletePreviousStatImages() ) {
		$toBrowser = $st->createPieChart( $statsData, $input->{title} );	
	} else {
		$toBrowser->{error} = $st->{errmsg};
	}

	return $toBrowser;
}

sub increasePieChart {
	my ( $input ) = @_;
	my $toBrowser;
	
	undef $st->{statInfo};

	my $statsData = $st->order_from_json( $input->{stats}, $input->{jsonHashOrder} );
	
	$st->{pieChartRadius} += 10;
	
	if ( $st->deletePreviousStatImages() ) {
		$toBrowser = $st->createPieChart( $statsData, $input->{title} );	
	} else {
		$toBrowser->{error} = $st->{errmsg};
	}

	return $toBrowser;	
}

sub decreasePieChart {
	my ( $input ) = @_;
	my $toBrowser;
	
	undef $st->{statInfo};

	my $statsData = $st->order_from_json( $input->{stats}, $input->{jsonHashOrder} );
	
	$st->{pieChartRadius} -= 10;
	
	if ( $st->deletePreviousStatImages() ) {
		$toBrowser = $st->createPieChart( $statsData, $input->{title} );	
	} else {
		$toBrowser->{error} = $st->{errmsg};
	}

	return $toBrowser;	
}

sub xAxisTitleBarChart {
	my ( $input ) = @_;
	my $toBrowser;
	
	undef $st->{statInfo};
	
	my $statsData = $st->order_from_json( $input->{stats}, $input->{jsonHashOrder} );

	my $xAxisFontAngle = ( $input->{xAxisFontAngle} ) ? 0 : 1;

	if ( $st->deletePreviousStatImages() ) {
		$toBrowser = $st->createBarPresentation( $statsData, $input->{title}, $input->{barType}, $xAxisFontAngle );	
	} else {
		$toBrowser->{error} = $st->{errmsg};
	}

	return $toBrowser;	
}

sub xAxisTitleLineChart {
	my ( $input ) = @_;
	my $toBrowser;
	
	undef $st->{statInfo};
	
	my $statsData = $st->order_from_json( $input->{stats}, $input->{jsonHashOrder} );

	my $xAxisFontAngle = ( $input->{xAxisFontAngle} ) ? 0 : 1;

	if ( $st->deletePreviousStatImages() ) {
		$toBrowser = $st->createMultiLineChart( $statsData, $input->{title}, $xAxisFontAngle );	
	} else {
		$toBrowser->{error} = $st->{errmsg};
	}

	return $toBrowser;	
}

1;
