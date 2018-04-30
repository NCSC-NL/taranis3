#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use URI::Escape;
use strict;

my @EXPORT_OK = qw(displayAssessAnalysis linkAssessAnalysis createAssessAnalysis searchAssessAnalysis);

sub assess2analyze_export {
	return @EXPORT_OK; 
}

sub displayAssessAnalysis {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $as = Taranis::Assess->new( Config );
	my $an = Taranis::Analysis->new( Config );
	my $tt = Taranis::Template->new;
	
	my $digest = uri_unescape( $kvArgs{digest} );
	
	$vars->{hasClusteredItems} = ( exists( $kvArgs{hasClusteredItems} ) ) ? $kvArgs{hasClusteredItems} : 0;
	
	# this setting is only used for the unlink feature on Analyze main page
	my $analysisUnlinkId = ( exists( $kvArgs{ul} ) && $kvArgs{ul} ) ? $kvArgs{ul} : undef;
	$vars->{analysisUnlinkId} = $analysisUnlinkId;

	## SETTING UP USER RIGHTS FOR WEBINTERFACE ##		
	my $analysis_rights = getUserRights( 
			entitlement => "analysis", 
			username => sessionGet('userid') 
		)->{analysis};
	
	my $has_analysis_pending_right = 0;
	
	if ( $analysis_rights->{particularization} ) {
		@{ $vars->{analysis_status_options} } = @{ $analysis_rights->{particularization} };
		
		foreach my $right ( @{ $analysis_rights->{particularization} } ) {
			if ( lc( $right ) eq "pending" ) {
				$has_analysis_pending_right = 1;		
			} 
		} 
	} else {
		@{ $vars->{analysis_status_options} } = @{getSessionUserSettings()->{analysis_status_options} }; 
		$has_analysis_pending_right = 1;
	}

	if ( $digest ne "" ) {

		my $item = $as->getItem( $digest );
		my $idstring = "";

		if ( $analysis_rights->{"read_right"} ) {

			my $linkedto_analysis = $an->getRecordsById( table => "item_analysis", item_id => $digest );

			my $analysis_ids;
			foreach my $record ( @$linkedto_analysis ) {
				push @$analysis_ids, $record->{analysis_id};
			}
#TODO: translate below		
	########### ID MATCHING #######################
	#### aan de hand van: digest van item, daar alle id's in identifier
	#### vervolgens kijken of id's in idstring staat van alle analysis
	#### alle gevonden analyses worden in selectie veld getoont
	
			my $ids = $an->getRecordsById( table => "identifier", digest => $digest );
			my @collection;
	
			foreach my $identifier ( @$ids ) {
				$idstring .= $identifier->{identifier}." ";
				push @collection, "%".$identifier->{identifier}."%" if ( $identifier->{identifier} ne "" ); 
			}
			
			## max length of idstring may be 2000
			if ( length( $idstring ) > 2000 ) {
				$idstring = substr( $idstring, 0, 1996 );
				
				$idstring =~ s/(.*)\s+.*?$/$1 .../;
			}

			$vars->{analysis_id_match} = $an->getRelatedAnalysisIdMatch( $analysis_rights, $analysis_ids, @collection ) if( @collection );

	############## KEYWORD MATCHING ################
	
			my @keywords = split(" ", $item->{title} );
			my %words;
			
			for (my $i = 0; $i < @keywords; $i++ ) {
					my $temp = keyword_ok($keywords[$i]);
					$words{$temp} = $temp if ( $temp );
			}
			@keywords = keys %words;

			$vars->{analysis_keyword_match} = $an->getRelatedAnalysisKeywordMatch( $analysis_rights, $analysis_ids, @keywords ) if ( @keywords );

	################### ALL PENDING ANALYSIS #################
			
			if ( $has_analysis_pending_right ) {
				my @pending_analysis;
				
				$an->loadAnalysisCollection( status => [ "pending" ] );
				
				ANALYSIS: 
				while ( $an->nextObject() ) {
					my $analysis = $an->getObject();

					foreach my $id ( @$analysis_ids ) {
						if ( $id eq $analysis->{id} ) {
							next ANALYSIS;
						} 
					}

					push @pending_analysis, $an->getObject();
				}
				$vars->{analysis_no_match} = \@pending_analysis;
			}
			
			$vars->{analysis_pending_right} = $has_analysis_pending_right;
		}

		$vars->{analysis_rights} = $analysis_rights;
		
		$vars->{item} = $item;
		$vars->{ids} = $idstring;
		$vars->{status} = ( $item->{category} =~ /kc/i ) ? $item->{category} : "pending";
		
		$vars->{write_right} = ( right("write") ) 
			? rightOnParticularization( $item->{category} ) 
			: 0;

		$vars->{userid}	= sessionGet('userid');

	} else {
		$vars->{message} = "Item ID is missing. Cannot retrieve item details.";
	}

	my $dialogContent = $tt->processTemplate( "assess2analyze.tt", $vars, 1 );

	return { dialog => $dialogContent };
}

sub createAssessAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $analysis_id, $analysisUnlinkId, @updateItems, $updateItemsStatus );
	
	my $analysisCreated = 0;
	my $as = Taranis::Assess->new( Config );
	my $an = Taranis::Analysis->new( Config );
	my $oTaranisUsers = Taranis::Users->new( Config );

	my $uriEncodedDigest = $kvArgs{digest};
	my $digest = uri_unescape( $uriEncodedDigest );

	my $item = $as->getItem( $digest );

	my $item_category = $item->{category};

	if ( right("write") && rightOnParticularization( $item_category ) ) {

		# this setting is only used for the unlink feature on Analyze main page
		$analysisUnlinkId = ( exists( $kvArgs{ul} ) && $kvArgs{ul} ) ? $kvArgs{ul} : undef;
		
		my @comments = $kvArgs{description};
		push @comments, $kvArgs{comments} if $kvArgs{comments};

		my $userId   = sessionGet('userid');
		my $user     = $oTaranisUsers->getUser($userId)->{fullname};
		push @comments, "[== Created by $user on ".nowstring(7)." ==]\n";

		withTransaction {
			if ( !$an->addObject( 
				table => "analysis", 
				title => $kvArgs{title}, 
				comments => join("\n\n", @comments),
				idstring => $kvArgs{ids},
				rating => $kvArgs{rating},
				status => $kvArgs{status}
			) ) {
				$message = $an->{errmsg};
			} else {
				$analysis_id = $an->getNextAnalysisID() - 1;
				if ( !$an->linkToItem( $digest, $analysis_id ) ) {
					$message = $an->{errmsg};
				} else {
					$analysisCreated = 1;
				}
				
				if ( exists( $kvArgs{'include-clustered-items'} ) ) {
					
					my @clusterItemIds = ( ref( $kvArgs{clusterItemId} ) =~ /^ARRAY$/ ) ? @{ $kvArgs{clusterItemId} } : $kvArgs{clusterItemId};
					
					foreach my $clusterItemId ( @clusterItemIds ) {
						push @updateItems, $clusterItemId;
						
						if ( $kvArgs{'include-clustered-items'} ) {
							#link all items in cluster to analysis
							if ( !$an->linkToItem( uri_unescape( $clusterItemId ), $analysis_id ) ) {
								$message = $an->{errmsg};
							}
							$updateItemsStatus = 'waitingroom';
						} else {
							#set all items in cluster to status 'read'
							if ( !$as->setItemStatus( digest => uri_unescape( $clusterItemId ), status => 1 ) ) {
							  $message = $as->{errmsg};
							}
							$updateItemsStatus = 'read';
						}
					}
				}
			}

			if ( $analysisUnlinkId && !$an->unlinkItem( $digest, $analysisUnlinkId ) ) {
				$message = $an->{errmsg};
				$analysisCreated = 0;
				$an->{dbh}->{dbh}->rollback();
			} 
		};
	} else {
		$message = "No rights...";
	}

	if ( $analysisCreated ) {
		setUserAction( action => "create analysis", comment => "Created analysis AN-" . substr( $analysis_id, 0, 4 ) . '-' . substr( $analysis_id, 4, 4) . " from '$item->{title}'" );
	} else {
		setUserAction( action => "create analysis", comment => "Got error '$message' while trying to create an analysis from '$item->{title}'" );
	}

	return { 
		params => {
			message => $message,
			itemDigest => $uriEncodedDigest,
			analysis_is_linked => $analysisCreated,
			analysisId => $analysis_id,
			analysisUnlinkId => $analysisUnlinkId,
			updateItems => \@updateItems,
			updateItemsStatus => $updateItemsStatus 
		}
	};
}

sub linkAssessAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $analysisUnlinkId, $linkToAnalysis, @updateItems, $updateItemsStatus  );
	
	my $analysisLinked = 0;
	my $as = Taranis::Assess->new( Config );
	my $an = Taranis::Analysis->new( Config );
	
	my $uriEncodedDigest = $kvArgs{digest};
	my $digest = uri_unescape( $uriEncodedDigest );
	
	my $item = $as->getItem( $kvArgs{digest} );
	
	my $item_category = $item->{category};

	if ( right("write") && rightOnParticularization( $item_category ) ) {

		# this setting is only used for the unlink feature on Analyze main page
		$analysisUnlinkId = ( exists( $kvArgs{ul} ) && $kvArgs{ul} ) ? $kvArgs{ul} : undef;

		$linkToAnalysis = $kvArgs{analysis};
		my $status = $kvArgs{status};
		my $title = $kvArgs{title};

		withTransaction {
			if ( !$an->linkToItem( $digest, $linkToAnalysis , $status, $title ) ) {
				$message = $an->{errmsg};

			} elsif ( $analysisUnlinkId && !$an->unlinkItem( $digest, $analysisUnlinkId ) ) {
				$message = $an->{errmsg};
				$an->{dbh}->{dbh}->rollback();

			} else {
				$analysisLinked = 1;
				
				if ( exists( $kvArgs{'include-clustered-items'} ) ) {
					
					my @clusterItemIds = ( ref( $kvArgs{clusterItemId} ) =~ /^ARRAY$/ ) ? @{ $kvArgs{clusterItemId} } : $kvArgs{clusterItemId};
					
					foreach my $clusterItemId ( @clusterItemIds ) {
						push @updateItems, $clusterItemId;
						
						if ( $kvArgs{'include-clustered-items'} ) {
							#link all items in cluster to analysis
							if ( !$an->linkToItem( uri_unescape( $clusterItemId ), $linkToAnalysis ) ) {
								$message = $an->{errmsg};
							}
							$updateItemsStatus = 'waitingroom';
						} else {
							#set all items in cluster to status 'read'
							if ( !$as->setItemStatus( digest => uri_unescape( $clusterItemId ), status => 1 ) ) {
							  $message = $as->{errmsg};
							}
							$updateItemsStatus = 'read';
						}
					}
				}
			}
		};

	} else {
		$message = "No rights...";
	}
	
	if ( $analysisLinked ) {
		setUserAction( action => "link to analysis", comment => "Linked '$item->{title}' to analysis AN-" . substr( $linkToAnalysis, 0, 4 ) . '-' . substr( $linkToAnalysis, 4, 4) );
	} else {
		setUserAction( action => "link to analysis", comment => "Got error '$message' while trying to link '$item->{title}' to analysis AN-" . substr( $linkToAnalysis, 0, 4 ) . '-' . substr( $linkToAnalysis, 4, 4) );
	}
	
	return { 
		params => {
			message => $message,
			itemDigest => $uriEncodedDigest,
			analysis_is_linked => $analysisLinked,
			analysisUnlinkId => $analysisUnlinkId,
			linkToAnalysis => $linkToAnalysis,
			updateItems => \@updateItems,
			updateItemsStatus => $updateItemsStatus 
		}
	};
}

sub searchAssessAnalysis {
	my ( %kvArgs ) = @_;
	my $message;
	
	my $an = Taranis::Analysis->new( Config );
		
	my $search = uri_unescape( $kvArgs{search} );
	my $search_status = ( $kvArgs{status} =~ /-any status-/ ) ? "" : $kvArgs{status};
	my $digest = uri_unescape( $kvArgs{digest} );

	my $analysis_rights = getUserRights( 
			entitlement => "analysis", 
			username => sessionGet('userid') 
		)->{analysis};

	my $linkedto_analysis = $an->getRecordsById( table => "item_analysis", item_id => $digest );

	my $analysis_ids;
	foreach my $record ( @$linkedto_analysis ) {
		push @$analysis_ids, $record->{analysis_id};
	}	
	
	my $analysis = $an->searchAnalysis( $search, $search_status, $analysis_rights, $analysis_ids );
	
	return { 
		params => {	analysis => $analysis } 
	};
}

1;
