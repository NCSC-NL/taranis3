#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Analysis;
use Taranis::Tagging;
use URI::Escape;
use strict;

my @EXPORT_OK = qw(openDialogAnalyzeJoin joinAnalysis);

sub analyze_join_export {
	return @EXPORT_OK;
}

sub openDialogAnalyzeJoin {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $tt = Taranis::Template->new;
	
	if ( right("write") ) {
		
		$vars->{pageSettings} = getSessionUserSettings();
	
		my $an = Taranis::Analysis->new( Config );
		
		my %status;
		my @titles;
		my @ids = @{ $kvArgs{id} };
		my %owners;
		$vars->{analysisIds} = \@ids;
		
		foreach my $id ( @ids ) {
			if ( length( $id ) == 8 ) {
				my $record = $an->getRecordsById( table => "analysis", id => $id )->[0];
				push @titles, $record->{title};
				$status{ $record->{status} } = 1;
				if ( $record->{owned_by} && !exists( $owners{ $record->{owned_by} } ) ) {
					$owners{ $record->{owned_by} } = 1;
				}
			}
		}
		
		@{ $vars->{owneroptions} } = keys %owners;
		
		$vars->{titleoptions} = \@titles;
		if ( keys( %status ) > 1 ) {
			$vars->{status} = "Pending";
		} else {
			$vars->{status} =  [ keys( %status ) ]->[0];
		}

		$tpl = 'analyze_join.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = 'No rights...';
	}
	
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1);
	
	return { dialog => $dialogContent };
}

sub joinAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $newAnalysis, $newAnalysisId, $vars );
	
	my $an = Taranis::Analysis->new( Config );
	my $tg = Taranis::Tagging->new( Config );
	my $tt = Taranis::Template->new;
	
	my $analysisJoined = 0;

	my @ids = @{ $kvArgs{'analyze-join-id'} };
		
	if ( right("write") ) {

		my $title = ( $kvArgs{title_alternative} ) ? trim( uri_unescape( $kvArgs{title_alternative} ) ) : uri_unescape( $kvArgs{title} );

		withTransaction {
			if ( $an->addObject( table => 'analysis', title => $title, status => lc( $kvArgs{status} ) ) ) {
				$newAnalysisId = $an->getNextAnalysisID() - 1;
				
				my ( $newAnalysisIdstring, $newAnalysisComments, $idstring );
				
				my $newAnalysisRating = 1;

				my %tags;
				my %unique_item_ids;
			
				foreach my $id ( @ids ) {
					if ( length( $id ) == 8 ) {
					
						my $analysis = $an->getRecordsById( table => "analysis", id => $id )->[0];
						
						$newAnalysisComments .= "\n[=== Comments from joined analysis AN-"
							. substr( $id, 0, 4 ) . "-"
							. substr( $id, 4, 4 )
							. " ===]\n"
							. $analysis->{comments} . "\n";

						$idstring .= $analysis->{idstring};

						$newAnalysisRating = $analysis->{rating} if ( $analysis->{rating} > $newAnalysisRating && $analysis->{rating} ne 4 );

						my $existingAnalysisComments = "[=== WARNING: this analysis was joined into AN-"
							. substr( $newAnalysisId, 0, 4 ) . "-"
							. substr( $newAnalysisId, 4, 4 )
							. " ===]\n\n"
							. $analysis->{comments};
						
						$an->setAnalysis( 
							id => $id, 
							status => "joined", 
							comments => $existingAnalysisComments,
							joined_into_analysis => $newAnalysisId
						);

						my $item_analysis_records = $an->getRecordsById( table => "item_analysis", analysis_id => $id );
						
						foreach my $iar ( @$item_analysis_records ) {
							if ( !exists( $unique_item_ids{ $iar->{item_id} } ) ) { 

								$unique_item_ids{ $iar->{item_id} } = 1;
								if ( !$an->addObject( 
									table => "item_analysis", 
									analysis_id => $newAnalysisId, 
									item_id => $iar->{item_id} 
								)) {
									$message = $an->{errmsg};
								} else {
									$analysisJoined = 1;
								}
							}
						}
					
						$tg->loadCollection( "ti.item_id" => $id, "ti.item_table_name" => "analysis" );
					
						while ( $tg->nextObject() ) {
							my $tag = $tg->getObject();
							$tags{ $tag->{id} } = 1;
						}
					
						$tg->removeItemTag( $id, "analysis" );
					}
				}

				my @ids_from_idstring = split( " ", $idstring );
				foreach ( sort( @ids_from_idstring ) ) {
					$newAnalysisIdstring .= " ".$_ if ( $newAnalysisIdstring !~ /$_/gi );
				}
			
				$newAnalysisComments .= "\n[=== New comments ===]\n";
				
				my $owner = ( exists( $kvArgs{owner} ) ) ? $kvArgs{owner} : undef; 
				
				if ( !$an->setAnalysis( 
					id => $newAnalysisId, 
					comments => $newAnalysisComments, 
					idstring => $newAnalysisIdstring,
					rating => $newAnalysisRating,
					owned_by => $owner
				)) {
					$message = $an->{errmsg};
					$analysisJoined = 0;
				} else {
					$analysisJoined = 1;
				}
			
				my @addTags = keys %tags;
				foreach my $tag_id ( @addTags ) {
					if (  !$tg->setItemTag( $tag_id, "analysis", $newAnalysisId ) ) {
						$message .= $tg->{errmsg};
						$analysisJoined = 0;
					}
				}
			} else {
				$message = $an->{errmsg};
				$analysisJoined = 0;
			}
		};
		
		$newAnalysis = $an->getRecordsById( table => "analysis", id => $newAnalysisId );
		
	} else {
		$message = 'No Rights...';
	}

	my $joinedAnlyses = '';
	$joinedAnlyses .= 'AN-' . substr( $_, 0, 4 ) . '-' . substr( $_, 4, 4) . ', ' for @ids; 
	$joinedAnlyses =~ s/, $//;

	if ( $analysisJoined ) {
		setUserAction( action => "join analysis", comment => "Joined analyses $joinedAnlyses to new analysis AN-" . substr( $newAnalysisId, 0, 4 ) . '-' . substr( $newAnalysisId, 4, 4) );
	} else {
		setUserAction( action => "join analysis", comment => "Got error '$message' while trying to join analyses $joinedAnlyses");
	}

	return { 
		params => { 
			message => $message,
			analysisJoined => $analysisJoined,
			ids => \@ids,
			newAnalysisId => $newAnalysisId		
		}
	};
}
1;
