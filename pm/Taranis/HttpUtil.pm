# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::HttpUtil;

## Taranis::HttpUtil: HTTP-related utility functions.

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use LWP::UserAgent;
use IO::Socket::SSL;
use URI;
use HTTP::Cookies;

use Taranis qw(normalizePath trim find_config);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(lwpRequest);


# Create an LWP object with sensible defaults from our configuration.
sub setupGenericLWP {
	my $constructor = shift || sub { LWP::UserAgent->new };

	my $lwp = $constructor->();
	$lwp->ssl_opts( IO::Socket::SSL::default_ca() );
	$lwp->protocols_allowed( ['http', 'https'] );
	$lwp->timeout( Config->{timeout} );
	$lwp->agent( Config->{useragent_string} );

	my $cookies = find_config(Config->{cookie_jar});
	$lwp->cookie_jar({ file => $cookies });

	if (Config->{proxy} =~ /^ON$/i) {
		my @no_proxy = map { trim $_ } split(/,/, Config->{no_proxy});
		$lwp->no_proxy( @no_proxy );
		$lwp->proxy( ['http', 'https'], Config->{proxy_host} ) if Config->{proxy_host};
	}

	return $lwp;
}

# LWP doesn't appear to support https SNI (Server Name Indication)
# when working with a proxy (as of 2015/12, LWP version 6.13).
# lwpRequest works around this by forcing the 'SSL_hostname' option of
# the underlying IO::Socket::SSL library.
# Since ssl_opts/SSL_hostname is a property of the LWP::UserAgent object,
# not of the request, we create a fresh LWP
# object for each request.
#
# Argument $opts is passed on to LWP, except for the optional
# $opts{lwp_constructor}, which supplies an alternative LWP object
# construction function.
#
# Argument $method is the method that will be called on LWP::UserAgent
# This usually, but not always, corresponds to a lowercased HTTP method
# name (e.g. 'get', 'post').
sub lwpRequest {
	my ($method => $url, %opts) = @_;

	my $lwp = setupGenericLWP(delete $opts{lwp_constructor});
	if (URI->new($url)->scheme eq 'https') {
		$lwp->ssl_opts(SSL_hostname => scalar URI->new($url)->host);
	}

	# For POST requests, default to x-www-form-urlencoded for convenience.
	if ($method eq 'post') {
		%opts = (
			content_type => 'application/x-www-form-urlencoded',
			%opts,
		);
	}
	return $lwp->$method($url, %opts);
}

1;
