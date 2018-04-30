#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use strict;

my @EXPORT_OK = qw(displayToolOptions);

sub toolspage_export {
	return @EXPORT_OK;
}

sub displayToolOptions {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisToolsConfig = Taranis::Config::XMLGeneric->new( Config->{toolsconfig}, "toolname", "tools" );

	my $unsortedTools = $oTaranisToolsConfig->loadCollection(); 
	
	if ( $unsortedTools ) {
		my @sortedTools = sort { $$a{'toolname'} cmp $$b{'toolname'} } @$unsortedTools;
		$vars->{tools} = \@sortedTools;
	} 
	
	my $htmlContent = $oTaranisTemplate->processTemplate('tools_options.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('tools_options_filters.tt', $vars, 1);
	
	my @js = (
		'js/toolspage.js'
	);
	
	return { content => $htmlContent,  filters => $htmlFilters, js => \@js };
}

1;
