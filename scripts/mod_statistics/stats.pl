#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(CGI Config Database);
use Taranis::Template;
use Taranis::Statistics;
use CGI::Simple;
use JSON;
use strict;

my @EXPORT_OK = qw( displayStatisticsOptions displayStats searchStats loadImage );

sub stats_export {
	return @EXPORT_OK;
}

sub displayStatisticsOptions {
	my ( %kvArgs) = @_;
	my ( $vars );
	
	my $tt = Taranis::Template->new;
	
	my $st = Taranis::Statistics->new( Config );
	$vars->{statsCategories} = $st->getStatsCategories();

	$vars->{canCreateStatistics} = $Taranis::Statistics::chartDirectorAvailable;

	$vars->{pageSettings} = getSessionUserSettings();
	
	my $htmlFilters = $tt->processTemplate('stats_options_filters.tt', $vars, 1); 
	my $htmlContent = $tt->processTemplate('stats_options.tt', $vars, 1);

	return { content => $htmlContent,  filters => $htmlFilters};
}

sub displayStats {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $st = Taranis::Statistics->new( Config );
	my $statsType = ( exists( $kvArgs{statstype} ) && $kvArgs{statstype} ) ? $kvArgs{statstype} : undef;
	
	$vars->{stats_categories} = $st->getStatsCategories();
	$vars->{stats} = $st->loadCollection( category => $statsType );

	foreach ( @{ $vars->{stats} } ) {
		$_->{image_src} = to_json( { object_id => $_->{object_id}, file_size => $_->{file_size} } );
	}
	
	my $pageTitle; 
	if ( $statsType ) {
		$pageTitle = ( $statsType =~ /statistics/i ) ? $statsType : $statsType .' Statistics';
	} else {
		$pageTitle = 'All Statistics';
	}
	
	$vars->{stats_selected} = $statsType;
	$vars->{page_title} = $pageTitle;
	
	my @js = ('js/stats.js');
	my $htmlContent = $tt->processTemplate('stats.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('stats_filters.tt', $vars, 1);
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub searchStats {
	my ( %kvArgs) = @_;
	my ( $vars );
	
	my $tt = Taranis::Template->new;
	my $st = Taranis::Statistics->new( Config );
	my $statsType = ( exists( $kvArgs{statstype} ) && $kvArgs{statstype} ) ? $kvArgs{statstype} : undef;
	
	$vars->{stats_categories} = $st->getStatsCategories();
	$vars->{stats} = $st->loadCollection( category => $statsType );

	foreach ( @{ $vars->{stats} } ) {
		$_->{image_src} = to_json( { object_id => $_->{object_id}, file_size => $_->{file_size} } );
	}

	my $htmlContent = $tt->processTemplate('stats.tt', $vars, 1);

	return { content => $htmlContent };	
}

sub loadImage {
	my ( %kvArgs ) = @_;
	my $dbh = Database;

	my $objectId = $kvArgs{object_id};
	my $fileSize = $kvArgs{file_size};
	my $image;
	my $mode = $dbh->{dbh}->{pg_INV_READ};
	
	withTransaction {
		my $lobj_fd = $dbh->{dbh}->func($objectId, $mode, 'lo_open');

		$dbh->{dbh}->func( $lobj_fd, $image, $fileSize, 'lo_read' );
	};

	print CGI->header(
		-type => 'image/png',
		-content_length => $fileSize,
	);
	binmode STDOUT;
	print $image;
}
1;
