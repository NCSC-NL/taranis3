#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(rightOnParticularization);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Assess;
use Taranis::Tagging;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use URI::Escape;
use HTML::Entities qw(encode_entities);
use strict;

my @EXPORT_OK = qw(openDialogAssessDetails getRelatedId);

sub assess_details_export {
	return @EXPORT_OK; 
}

sub openDialogAssessDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $itemAnalysisRight );

	my $as = Taranis::Assess->new( Config );
	my $tt = Taranis::Template->new;
	my $tg = Taranis::Tagging->new( Config );

	my $digest = $kvArgs{digest};

	my $is_archived = ( exists( $kvArgs{is_archived} ) ) ? $kvArgs{is_archived} : 0;

	my $item = $as->getItem( $digest, $is_archived );

	if ( rightOnParticularization( $item->{category} ) ) {

		if ( !$item ) {
			$item = $as->getItem( $digest, 1 );
		}
	 
		for ( $item->{status} ) {
			if (/0/) { $item->{status} = "Unread"; }
			elsif (/1/) { $item->{status} = "Read"; }
			elsif (/2/) { $item->{status} = "Important"; }
			elsif (/3/) { $item->{status} = "Waitingroom"; }
		}
		$vars->{item} = $item;

		my $item_analysis_rights = getUserRights( 
				entitlement => "item_analysis", 
				username => sessionGet('userid') 
			)->{item_analysis};
	
		$itemAnalysisRight = 0;

		if ( $item_analysis_rights->{write_right} ) {
			if ( $item_analysis_rights->{particularization} ) {
				foreach my $cat ( @{ $item_analysis_rights->{particularization} } ) {
					if ( lc( $item->{category} ) eq lc( $cat ) ) {
						$itemAnalysisRight = 1;
					}
				}
			} else {
				$itemAnalysisRight = 1;		
			}
		} 

		# Case preserving uniq of certids
		my %ids;
		if(my $i = $item->{identifier}) {
			$ids{uc $i} = $i;
		}
	
		my $related_ids = $as->getRelatedIds($digest);
		$ids{uc $_} ||= $_ for @$related_ids;
	
		my @ids_sort = sort keys %ids;
		$vars->{id_string} = @ids_sort ? join(' ', @ids_sort) : 'None';
		$vars->{id_string_arr} = \@ids_sort;

		#### ID MATCHING ###
	
		my $id_match = $as->getRelatedItemsIdMatch( $digest );
	
		if ( @{ $id_match } ) {
			for (my $i = 0; $i < @{ $id_match }; $i++ ) {
	
				$id_match->[$i]->{title} = encode_entities( $id_match->[$i]->{title} );
				$id_match->[$i]->{description} = encode_entities( $id_match->[$i]->{description} );
				$id_match->[$i]->{date} = substr( $id_match->[$i]->{item_date}, 0, 10 );
				$id_match->[$i]->{'time'} = substr( $id_match->[$i]->{item_date}, 11, 9 );						
			}
			$vars->{id_match} = $id_match;
		}

		#### KEYWORD MATCHING ###
	
		my @keywords = split(" ", $item->{title});
		my %words;
	
		for ( my $i = 0; $i < @keywords; $i++ ) {
			my $temp = keyword_ok($keywords[$i]);
			$words{$temp} = $temp if ( $temp );
		}
		@keywords = keys %words;
		if ( @keywords ) {
			my $key_match = $as->getRelatedItemsKeywordMatch( $digest, @keywords );
			if ( @{ $key_match } ) {
				for (my $i = 0; $i < @{ $key_match }; $i++ ) {

					$key_match->[$i]->{title} = $key_match->[$i]->{title};
					$key_match->[$i]->{description} = $key_match->[$i]->{description};
					$key_match->[$i]->{date} = substr( $key_match->[$i]->{item_date}, 0, 10 );
					$key_match->[$i]->{'time'} = substr( $key_match->[$i]->{item_date}, 11, 9 );						
				}
				$vars->{key_match} = $key_match;
			}
		}

		$vars->{analyze_right} = ( !$is_archived && $itemAnalysisRight ) ? 1 : 0;

		my $tags = $tg->getTagsByItem( $digest, "item" );
		$vars->{tags}	= "@$tags";
		
		$tpl = "assess_details.tt";
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = "No rights...";
	}

	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return { 
		dialog => $dialogContent, 
		params => {	digest => uri_escape( $digest, '+/' ) }  
	};

}

sub getRelatedId {
	my ( %kvArgs ) = @_;
	my $as = Taranis::Assess->new( Config );

	my $id = $kvArgs{id};	
	
	my $description = $as->getRelatedIdDescription("$id");
    	
    if ( !$description ) {
    	$description = { type => 'UNKNOWN', description => $as->{errmsg}, type => '', phase => '', status=> '', identifier => $id, ids => [] };
    }
	
	return {
		params => { %$description }
	};
}

1;
