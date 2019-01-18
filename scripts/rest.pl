#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use warnings;

use Taranis qw(:all);
use Taranis::FunctionalWrapper qw(CGI);
use Taranis::Config;
use Taranis::REST;
use Taranis::REST::AccessToken;
use Taranis::Users;

use CGI::Simple;
use Encode;
use JSON;
use HTML::Entities qw(decode_entities);

use Data::Dumper;
sub _send_response($);
sub _logged_in_command($$$);
sub _login($$$);
sub _logout($$);

#XXX This is a mod_perl script, which therefore gets wrapped in a function.
#    You cannot access global variabels from subs defined here, because
#    they will complain about "will not stay shared"

my $config  = Taranis::Config->new;
my $request = CGI;
my $session = Taranis::REST->new($config);

# sets access token as side-effect
my $uri     = $session->cleanURI($ENV{REQUEST_URI});

my $method  = CGI->request_method;
if($method eq 'GET') {
	_logged_in_command($session, $request, $uri);

} elsif($method eq 'POST') {
	if(my $token = $session->getSuppliedToken) {
		#XXX It is a bit weird to logout by calling the same procedure.
		_logout($session, $token);
	} else {
		_login($session, $request, $uri);
	}
} else {
    print CGI->header( -status => '405 Method not allowed');
}

exit 0;

####

sub _send_response($) {
	my $data     = shift;
	my $response = decode_entities_deep($data);
	print CGI->header('application/json');
	print encode("UTF-8", to_json $response);
}

sub _logged_in_command($$$) {
	my ($session, $request, $uri) = @_;
	my $token = $session->getSuppliedToken;
	unless($token) {
		print CGI->header( -status => '417 No access token');
		return;
	}

	my $access_tokens = Taranis::REST::AccessToken->new;
	unless($token eq 'none' || $access_tokens->isValidToken($token)) {
		# User is not logged in
		print CGI->header( -status => '401 Unauthorized');
		return;
	}

	$access_tokens->setAccessToken(token => $token, last_access => \'NOW()')
		if $token ne 'none';

	unless($session->isRouteAllowed($uri, $token, $request)) {
		# User has no rights for requested resource.
		print CGI->header( -status => $session->{errmsg} );
		return;
	}

	my $results  = $session->route($uri, $request) // {};
	$results     = { result => $results } if ref $results ne 'HASH';
	_send_response($results);

	# update last_access 
	$access_tokens->setAccessToken(token => $token, last_access => \'NOW()');
}

sub _login($$$) {
	my ($session, $request, $uri) = @_;

	unless($session->isRouteAllowed($uri, undef, $request)) {
		print CGI->header( -status => $session->{errmsg} );
		return;
	}

	my $results  = $session->route($uri, $request) || {};
	_send_response($results);
}

sub _logout($$) {
	my ($session, $token) = @_;
	my $access_tokens = Taranis::REST::AccessToken->new;
	$access_tokens->deleteAccessToken($token);
	print CGI->header( -status => '200 OK');
}
