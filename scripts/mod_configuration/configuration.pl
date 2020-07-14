#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw(displayConfigurationOptions);

sub configuration_export {
	return @EXPORT_OK;
}

sub displayConfigurationOptions {
	my ( %kvArgs) = @_;
	my ( $vars );
	
	my $tt = Taranis::Template->new;


	$vars->{pageSettings} = getSessionUserSettings();

	my $htmlFilters = $tt->processTemplate('configuration_filters.tt', $vars, 1); 
	my $htmlContent = $tt->processTemplate('configuration.tt', $vars, 1);

	my @js = (
		'js/configuration.js'
	);

	return { content => $htmlContent,  filters => $htmlFilters, js => \@js };
}

1;
