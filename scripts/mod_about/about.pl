#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use strict;

my @EXPORT_OK = qw( displayAbout );

sub about_export {
	return @EXPORT_OK;
}

sub displayAbout {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	
	my $htmlContent = $tt->processTemplate('about.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('about_filters.tt', $vars, 1);
	
	return { content => $htmlContent, filters => $htmlFilters };	
}
1;
