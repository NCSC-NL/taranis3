#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Assess;
use Taranis::Analysis;
use Taranis::Database qw(withTransaction);
use Taranis::Template; 
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use URI::Escape;
use JSON;
use strict;

my @EXPORT_OK = qw(addAnalysis displayBulkAnalysis);

sub assess_bulk_export {
	return @EXPORT_OK; 
}

sub displayBulkAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $vars );
	my $oTaranisTemplate = Taranis::Template->new;

	my $analysis_rights = getUserRights( 
		entitlement => "analysis", 
		username => sessionGet('userid') 
	)->{analysis};
	
	$vars->{hasClusteredItems} = $kvArgs{hasClusteredItems};
	$vars->{action} = ( $kvArgs{action} =~ /^(bulk|multiple)$/ ) ? $kvArgs{action} : undef; 
	
	if ( $analysis_rights->{particularization} ) {
		@{ $vars->{analysis_status_options} } = @{ $analysis_rights->{particularization} };
	} else {
		@{ $vars->{analysis_status_options} } = @{getSessionUserSettings()->{analysis_status_options} }; 
	}

	my $dialogContent = $oTaranisTemplate->processTemplate('status_selection.tt', $vars, 1);
	
	return { dialog => $dialogContent };
}

sub addAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, @ids, @updateItems );
	my $analysisAddedd = 0;
	
	if ( $kvArgs{action} =~ /^(bulk|multiple)$/i ) {
		if ( 
			right("write")
			&& $kvArgs{'bulk-analysis-rating'} =~ /[1-4]/i
		) {
	
			my $oTaranisAssess = Taranis::Assess->new( Config );
			my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	
			withTransaction {
				my $analysis_id;
		
				@ids = @{ $kvArgs{id} };
				my $status = $kvArgs{'bulk-analysis-status'};
				my $rating = $kvArgs{'bulk-analysis-rating'};
				my $cntr = 0;
				my ($title, $description);

				foreach my $unescapedId ( @ids ) {
					my $id = uri_unescape( $unescapedId );
					push @updateItems, $id;
					$cntr++;

					if ($cntr == 1 || $kvArgs{action} =~ /^multiple$/i ) {

						my $alt_title = $kvArgs{'bulk-analysis-title-alt'} ||'';
						s/^\s+//,s/\s+$// for $alt_title;

						if(length $alt_title) {
							$title = $alt_title;
							$description = '';
						} else {
							my $item_id = $kvArgs{action}=~ /^multiple$/i
								? $id : $kvArgs{'bulk-analysis-title'};
							my $item = $oTaranisAssess->getItem($item_id);
							$title = $item->{title};
							$description = $item->{description};
						}
			
						if ( !$oTaranisAnalysis->addObject( 
							table => "analysis", 
							title => $title, 
							comments => $description,
							status => $status, 
							rating => $rating
							) 
						) {
							$message = $oTaranisAnalysis->{errmsg};
							setUserAction( action => 'create analysis', comment => "Got error '$message' while trying to create an analysis from '$title'");
						} else {
							$analysis_id = $oTaranisAnalysis->getNextAnalysisID() - 1;
							setUserAction( action => 'create analysis', comment => "Created analysis AN-" . substr( $analysis_id, 0, 4 ) . '-' . substr( $analysis_id, 4, 4) . " from '$title'" );
						}
					}
					
					if ( exists( $kvArgs{clusterItemMapping} ) ) {
						my $jsonClusterItemMapping = $kvArgs{clusterItemMapping};
						$jsonClusterItemMapping =~ s/&quot;/"/g;
						my $clusterItemMapping = from_json( $jsonClusterItemMapping );

						if ( exists( $clusterItemMapping->{$unescapedId} ) ) {
						
							foreach my $clusterItemId ( @{ $clusterItemMapping->{$unescapedId} } ) {
								push @updateItems, uri_unescape( $clusterItemId );
								if ( !$oTaranisAnalysis->linkToItem( uri_unescape( $clusterItemId ), $analysis_id ) ) {
									$message = $oTaranisAnalysis->{errmsg};
								}
							}
						}
					}
					
					if ( !$oTaranisAnalysis->linkToItem( $id, $analysis_id ) ) {
						$message = $oTaranisAnalysis->{errmsg};
						setUserAction( action => "link to analysis", comment => "Got error '$message' while trying to link '$title' to analysis AN-" . substr( $analysis_id, 0, 4 ) . '-' . substr( $analysis_id, 4, 4) );
					} else {
						$analysisAddedd = 1;
						$title ||= $oTaranisAssess->getItem($id);
						setUserAction( action => "link to analysis", comment => "Linked '$title' to analysis AN-" . substr( $analysis_id, 0, 4 ) . '-' . substr( $analysis_id, 4, 4) );
					}
				}
			};
	
		} else {
			$message = "Sorry, you do not have enough privileges to do a bulk or multiple analysis...";
		}
	} else {
		$message = "Illegal bulk analysis action!";
	}
		
	return { 
		params => { 
			message => $message,
			analysis_is_added => $analysisAddedd,
			ids => \@updateItems
		}
	};
}

1;
