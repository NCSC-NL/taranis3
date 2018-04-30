# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::RequestRouting;

## Taranis::RequestRouting: parsing for the /(load|loadfile)/modName/pageName/action path of JSON requests done by the
## webinterface's client-side JavaScript.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;

use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(currentRequest);


sub currentRequest {
	my $parts = _requestPathParts();
	return {
		type        => $parts->[0],
		modName     => $parts->[1],
		pageName    => $parts->[2],
		action      => $parts->[3],
	};
}

# _requestPathParts: chop leading Taranis path (usually "/taranis") off the current request URI, chop off the query
# string, and split the remainder on slashes.
# '/taranis/load/foo/bar?quux' => ['load', 'foo', 'bar']
sub _requestPathParts {
	my $scriptroot = Config->{scriptroot};
	$scriptroot .= '/' unless $scriptroot =~ m{/$};

	croak "request not within scriptroot"
		unless substr($ENV{REQUEST_URI}, 0, length $scriptroot) eq $scriptroot;

	my $path = substr($ENV{REQUEST_URI}, length $scriptroot);
	$path =~ s/\?.*//g;
	return [split m{/}, $path];
}
