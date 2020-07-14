#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis::Template;

my $tt = Taranis::Template->new();

$tt->processTemplateWithHeaders( "not_found.tt", {} );
print $tt->{errmsg};
