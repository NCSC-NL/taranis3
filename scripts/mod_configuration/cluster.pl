#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Cluster;
use Taranis::Category;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use JSON;
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw( 
	displayClusters openDialogNewCluster openDialogClusterDetails 
	saveNewCluster saveClusterDetails deleteCluster getClusterItemHtml
);

sub cluster_export {
	return @EXPORT_OK;
}

sub displayClusters {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $cl = Taranis::Cluster->new( Config );
	
	my @clusters = $cl->getCluster();

	$vars->{clusters} = ( $clusters[0] ) ? \@clusters : [];
	$vars->{numberOfResults} = scalar @clusters;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('cluster.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('cluster_filters.tt', $vars, 1);
	
	my @js = ('js/cluster.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewCluster {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		my $ca = Taranis::Category->new( Config );
		@{ $vars->{categories} } = $ca->getCategory( is_enabled => 1 );
		$tpl = 'cluster_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}
	
	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};	
}

sub openDialogClusterDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $cl = Taranis::Cluster->new( Config );
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		$id = $kvArgs{id};
		my $cluster = $cl->getCluster( 'cl.id' => $id );

		if ( exists $cluster->{id} ) {
			$vars->{cluster} = $cluster;
		} else {
			$vars->{message} = $cl->{errmsg};
		}

		my $ca = Taranis::Category->new( Config );
		@{ $vars->{categories} } = $ca->getCategory( is_enabled => 1 );

		$tpl = 'cluster_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};
}

sub saveNewCluster {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") ) {

		my $cl = Taranis::Cluster->new( Config );
		my $ca = Taranis::Category->new( Config );
		if ( !$cl->{dbh}->checkIfExists( { language => lc $kvArgs{language}, category_id => $kvArgs{category} }, "cluster", "IGNORE_CASE" ) ) {
			my $category = $ca->getCategory( id => $kvArgs{category} );
			my $recluster = ( $kvArgs{recluster} ) ? 1 : 0;
			
			if ( $cl->addCluster( 
					language => $kvArgs{language},
					category_id => $kvArgs{category},
					threshold => $kvArgs{threshold},
					timeframe_hours => $kvArgs{timeframe_hours},
					recluster => $recluster
				) 
			) {
				$id = $cl->{dbh}->getLastInsertedId('cluster');
				setUserAction( action => 'add cluster', comment => "Added cluster for category '$category->{name}' with language '" . uc( $kvArgs{language} ) . "'");
			} else {
				$message = $cl->{errmsg};
				setUserAction( action => 'add cluster', comment => "Got error '$message' while trying to add cluster for category '$category->{name}' with language '" . uc( $kvArgs{language} ) . "'");
			}
		} else {
			$message = "A cluster with the same combination of language and category already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};	
}

sub saveClusterDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my $cl = Taranis::Cluster->new( Config );

		my $is_enabled = ( $kvArgs{disable_cluster} ) ? 0 : 1;
		my $recluster = ( $kvArgs{recluster} ) ? 1 : 0;
		
		my %cluster_update = ( 
			id => $kvArgs{id}, 
			category_id => $kvArgs{category},
			threshold => $kvArgs{threshold},
			timeframe_hours => $kvArgs{timeframe_hours},
			language => $kvArgs{language},
			recluster => $recluster,
			is_enabled => $is_enabled 
		);
		
		if ( !$cl->{dbh}->checkIfExists( { language => lc $kvArgs{language}, category_id => $kvArgs{category}, id => { '!=' => $id } } , "cluster", "IGNORE_CASE" )	) {
			my $ca = Taranis::Category->new( Config );
			my $category = $ca->getCategory( id => $kvArgs{category} );
			
			if ( !$cl->setCluster( %cluster_update ) ) {
				$message = $cl->{errmsg};
				setUserAction( action => 'edit cluster', comment => "Got error '$message' while trying to edit cluster for category '$category->{name}' with language '" . uc( $kvArgs{language} ) . "'");
			} else {
				setUserAction( action => 'edit cluster', comment => "Edited cluster for category '$category->{name}' with language '" . uc( $kvArgs{language} ) . "'");				
			} 
		} else {
			$message = "A cluster with the same combination of language and category already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
}

sub deleteCluster {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $cl = Taranis::Cluster->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $cluster = $cl->getCluster( 'cl.id' => $id );

		if ( !$cl->deleteCluster( $kvArgs{id} ) ) {
			$message = $cl->{errmsg};
			setUserAction( action => 'delete cluster', comment => "Got error '$message' while deleting cluster for category '$cluster->{name}' with language '" . uc( $cluster->{language} ) . "'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete cluster', comment => "Deleted cluster for category '$cluster->{name}' with language '" . uc( $cluster->{language} ) . "'");
		}

	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $id
		}
	};
}

sub getClusterItemHtml{
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $cl = Taranis::Cluster->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $cluster = $cl->getCluster( 'cl.id' => $id );
 
	if ( $cluster ) {
		$vars->{cluster} = $cluster;

		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'cluster_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}

1;
