#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Database qw(withTransaction);
use Taranis::Tagging;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(CGI Config);
use Taranis qw(:all);
use CGI::Simple;
use URI::Escape;
use JSON;
use strict;

my @EXPORT_OK = qw(getList setTags getTags openDialogTagsDetails);

sub tag_export {
	return @EXPORT_OK; 
}

sub getList {
	my ( %kvArgs ) = @_;

	my $oTaranisTagging = Taranis::Tagging->new( Config );
	my $tags = $oTaranisTagging->getTags( $kvArgs{term} );

	my $labelsPerTag = $oTaranisTagging->getDossierLabelsPerTag();
	my @foundTags;
	foreach my $tag ( @$tags ) {
		my $label = ( exists( $labelsPerTag->{$tag} ) ) ? $labelsPerTag->{$tag} : '';
		push @foundTags, { value => $tag, label => $label };
	}

	print CGI->header(
		-type => 'application/json',
	);
	print to_json( \@foundTags );

	return {};
}

sub setTags {
	my ( %kvArgs ) = @_;	

	my $oTaranisTagging = Taranis::Tagging->new( Config );
	
	my $tags_str = $kvArgs{tags};
	my $table = $kvArgs{t_name};
	my $item_id = $kvArgs{item_id};

	my $message = "";
	
	$tags_str =~ s/,$//;
	
	my @tags = split( ',', $tags_str );
	
	withTransaction {
		TAG: foreach my $t ( @tags ) {
			$t = trim( $t );

			my $tag_id;
			if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $t }, "tag", "IGNORE_CASE" ) ) {
				$oTaranisTagging->addTag( $t );
				$tag_id = $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
			} else {
				$tag_id = $oTaranisTagging->getTagId( $t );
				
				if ( $oTaranisTagging->{dbh}->checkIfExists( 
					{ tag_id => $tag_id, item_table_name => $table, item_id => $item_id }, 
					"tag_item", 
					"IGNORE_CASE" 
				) ) {
					next TAG;
				}
			}
			
			if ( !$oTaranisTagging->setItemTag( $tag_id, $table, $item_id ) ) {
				$message = $oTaranisTagging->{errmsg};
			}
		}

		if ( !$oTaranisTagging->removeItemTag( $item_id, $table, \@tags ) ) {
			$message = $oTaranisTagging->{errmsg};
		}
		
		$oTaranisTagging->cleanUp();
	};
	
	my $tagsHTML;
	if ( !$message ) {
		my $oTaranisTemplate = Taranis::Template->new;
		$tagsHTML = $oTaranisTemplate->processTemplate( 'tags.tt', { tags => \@tags, removeWrapper => 1 }, 1);
	}
		
	return { 
		params => { 
			message => $message,
			tagsHTML => $tagsHTML
		} 
	};
}

sub openDialogTagsDetails {
	my ( %kvArgs ) = @_;

	my ( $vars );
	
	my $oTaranisTemplate = Taranis::Template->new;
	
	if ( $kvArgs{id} && $kvArgs{t_name} ) {
		my $id = $kvArgs{id};
		my $oTaranisTagging = Taranis::Tagging->new( Config );
		
		my $tags = $oTaranisTagging->getTagsByItem( $id, $kvArgs{t_name} );
		$vars->{tags} = $tags;
		
		my $dossierLabelsPerTag = $oTaranisTagging->getDossierLabelsPerTag();
		
		my %dossiers;
		foreach my $tag ( keys %$dossierLabelsPerTag ) {
			if ( exists( $dossiers{ $dossierLabelsPerTag->{$tag} } ) ) {
				push @{ $dossiers{ $dossierLabelsPerTag->{$tag} } }, $tag;
			} else {
				$dossiers{ $dossierLabelsPerTag->{$tag} } = [ $tag ];
			}
		}
		
		$vars->{dossiers} = keys %dossiers ? \%dossiers : undef;
		
	} else {
		$vars->{message} = 'Invalid input!';
	}
	
	my $dialogContent = $oTaranisTemplate->processTemplate( 'tags_details.tt', $vars, 1);
	
	return { 
		dialog => $dialogContent
	};
}

sub getTags {
	my ( %kvArgs ) = @_;
	
	my $tags = [];
	
	if ( $kvArgs{ids} && $kvArgs{t_name} ) {
		my @ids = $kvArgs{ids};
		my $oTaranisTagging = Taranis::Tagging->new( Config );
		
		$tags = $oTaranisTagging->getTagsByItemBulk( item_id => \@ids, item_table_name => $kvArgs{t_name} );
		
	}
	return { 
		params => { 
			tags => $tags
		} 
	};
}
1;
