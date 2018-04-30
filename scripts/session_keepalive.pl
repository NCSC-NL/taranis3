#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use CGI::Simple;

use Taranis::Session qw(updateSessionTTL sessionIsActive);
use Taranis::SessionUtil qw(validCsrfHeaderSupplied);
use Taranis::FunctionalWrapper qw(CGI);


# session_keepalive.pl: extend client's session lifetime.
# Apart from requests to session_keepalive.pl, the session lifetime is only automatically extended when we get a
# mainpage request. Therefore, client code is expected to POST to session_keepalive.pl now and then when the user is
# active (moving his mouse, typing, etc).

unless ($ENV{REQUEST_METHOD} eq 'POST') {
	print CGI->header(-status => 405);
	exit;
}

unless (sessionIsActive and validCsrfHeaderSupplied) {
	print CGI->header(-status => 403);
	exit;
}

updateSessionTTL;

print CGI->header(-status => 204);  # HTTP 204 No Content.
exit;
