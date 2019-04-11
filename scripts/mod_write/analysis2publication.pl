#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::SessionUtil qw(right);
use Taranis::Template;
use Taranis::Analysis;
use Taranis::Publication;
use strict;

my @EXPORT_OK = qw(openDialogAnalysisToPublication openDialogAnalysisToPublicationUpdate searchPublicationsAnalysisToPublication);

sub analysis2publication_export {
	return @EXPORT_OK; 
}

sub openDialogAnalysisToPublication {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $ana_id = $vars->{analysis_id} = $kvArgs{id};

	my $advisoryRight = 0;
	my $advisoryForwardRight = 0;
		
	if ( right("write") ) {
		if ( right("particularization") ) {
			foreach my $right ( @{ right("particularization") } ) {
				if ( lc ( $right ) eq "advisory (email)" ) {
					$advisoryRight = 1;
				}
				if ( lc ( $right ) eq "advisory (forward)" ) {
					$advisoryForwardRight = 1;
				}
			} 
		} else {
			$advisoryRight = 1;
			$advisoryForwardRight = 1;
		}

		if((Config->{publish_eod_white} || 'OFF') =~ m/ON/i) {
			# Only accept linked items when we use EOD-White, otherwise constituents
			# do not get informed.
			$vars->{accept_late_links} = 1;
			$vars->{linkedItems} = $oTaranisAnalysis->getLinkedItems($ana_id);
			my $analysis = $oTaranisAnalysis->getRecordsById(table => 'analysis',
				id => $ana_id)->[0];

			my @matches;
			if(my @cve_ids = $analysis->{idstring} =~ m/\b(CVE\S+)/g) {
				@matches = $oTaranisPublication->getRelatedPublications(\@cve_ids, 'advisory', allow_incomplete => 1);
			}
			$vars->{advisories_id_match} = \@matches;
		}

		$vars->{linkedAdvisories} = $oTaranisAnalysis->getLinkedAdvisories( 'pu.status' => { '!=' => 3 }, 'ap.analysis_id' => $ana_id);
		$vars->{linkedItemsContainingAdvisories} = $oTaranisAnalysis->getLinkedItemsContainingAdvisories( 'ia.analysis_id' => $ana_id);
		$tpl = 'analysis2publication.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = 'Sorry, you do not have enough privileges for this action...';
	}
	
	
	$vars->{advisory_right} = $advisoryRight;
	$vars->{advisory_forward_right} = $advisoryForwardRight;
	
	my $dialogContent = $oTaranisTemplate->processTemplate($tpl, $vars, 1);
	
	my @js = (
			'js/publications.js',
			'js/publications_advisory.js',
			'js/publications_advisory_forward.js',
			'js/publications_common_actions.js'
	);
		
	return { 
		dialog => $dialogContent,
		params => {id => $kvArgs{id} },
		js => \@js
	};
}

sub openDialogAnalysisToPublicationUpdate {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );
	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisPublication = Publication;
	
	my $publicationRight = 0;

	my $publicationType = $kvArgs{pubclicationType};
	
	if ( $publicationType =~ /^(advisory|forward)$/ ) {
	
		if ( right("write") ) {
			if ( right("particularization") ) {
				foreach my $right ( @{ right("particularization") } ) {
					if ( lc ( $right ) eq "advisory (email)" && $publicationType =~ /^advisory$/ ) {
						$publicationRight = 1;
					} elsif ( lc ( $right ) eq "advisory (forward)" && $publicationType =~ /^forward$/ ) {
						$publicationRight = 1;
					}
				} 
			}	else {
				$publicationRight = 1;
			}
		}
		
		$vars->{publication_right} = $publicationRight;
	} 

	if ( $publicationRight ) {
		if ( $kvArgs{analysisId} =~ /^\d+$/ ) {
			
			my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", id => $kvArgs{analysisId} )->[0];
			
			my @cve_ids;
			if ( $analysis->{idstring} ) {
				my @ids = split( " ", $analysis->{idstring} );
				foreach ( @ids ) {
					if ( $_ =~ /^CVE.*/i) {
						push @cve_ids, $_;
					}
				}
			}	
			
			if ( @cve_ids && $publicationType =~ /^(advisory|forward)$/ ) {
				$vars->{advisories_id_match} = $oTaranisPublication->getRelatedPublications( \@cve_ids, $publicationType );
			}
			$vars->{publication_type} = $publicationType;
			$vars->{publications_no_match} = $oTaranisPublication->getRelatedPublications( undef, $publicationType );
			$vars->{analysis_id} = $kvArgs{analysisId};
			$vars->{analysis_heading} = $analysis->{title};
			
		} else {
			$vars->{message} = "No valid ID supplied.";
		}
		
		$tpl = 'analysis2publication_update.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = 'Sorry, you do not have enough privileges for this action...';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate($tpl, $vars, 1);
	
	return { 
		dialog => $dialogContent,
		params => { id => $kvArgs{analysisId} } 
	};
} 

sub searchPublicationsAnalysisToPublication {
	my ( %kvArgs ) = @_;
	my $message;
	
	my $oTaranisPublication = Publication;

	my $search = $kvArgs{search};
	my $publicationType = $kvArgs{publicationtype};
	my $id = $kvArgs{id};
	my $include_open = $kvArgs{include_open} || 0;
			
	my $publications = $oTaranisPublication->searchPublishedPublications(
		$search, $publicationType, $include_open);

	$message = $oTaranisPublication->{errmsg};

	return {
		params => {
			id => $id,
			publications => $publications,
			message => $message
		}
	};
}

1;
