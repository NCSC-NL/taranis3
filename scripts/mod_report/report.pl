#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Publication;
use Taranis::Report::ContactLog;
use Taranis::Report::IncidentLog;
use Taranis::Report::SpecialInterest;
use Taranis::Report::ToDo;
use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use strict;

my @EXPORT_OK = qw(displayReportOptions);

sub report_export {
	return @EXPORT_OK;
}

sub displayReportOptions {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;

	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
	my $TaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
	my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
	my $oTaranisPublication = Publication;
	
	my $limitPerCategory = 5;
	$vars->{contactLogs} = $oTaranisReportContactLog->getContactLog( limit => $limitPerCategory );
	$vars->{todos} = $oTaranisReportToDo->getToDo( done_status => {'!=' => 100}, limit => $limitPerCategory );
	$vars->{incidentLogs} = $TaranisReportIncidentLog->getIncidentLog( 'ril.status' => [1,2],  limit => $limitPerCategory );
	$vars->{specialInterests} = $oTaranisReportSpecialInterest->getSpecialInterest( date_start => { '<' => \'NOW()' }, date_end => { '>' => \'NOW()' }, limit => $limitPerCategory );
	
	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eos}->{email};
	my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
	
	$vars->{publications} = $oTaranisPublication->loadPublicationsCollection( 
		table => 'publication_endofshift',
		status => [0,1,2],
		date_column	=> "created_on",
		publicationType => $typeId,
	);

	my $publishedPublications = $oTaranisPublication->loadPublicationsCollection(
		table => 'publication_endofshift',
		status => [3],
		hitsperpage => 5,
		offset => 0,
		date_column	=> "created_on",
		publicationType => $typeId,
	);

	push @{ $vars->{publications} }, @$publishedPublications;

	my $htmlContent = $oTaranisTemplate->processTemplate('report_options.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('report_options_filters.tt', $vars, 1);
	
	my @js = (
		'js/report_contact_log.js',
		'js/report_incident_log.js',
		'js/report_special_interest.js',
		'js/report_todo.js',
		'js/publications.js',
		'js/report.js'
	);
	
	return { content => $htmlContent,  filters => $htmlFilters, js => \@js };
}

1;
