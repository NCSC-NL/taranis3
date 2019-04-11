#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use CGI::Simple;
use JSON;

use Taranis::Session qw(sessionIsActive);
use Taranis::FunctionalWrapper qw(CGI);


# Simple utility allowing client-side JavaScript to see whether the user has a valid (logged-in, non-expired, working)
# session, and e.g. redirect him to the login page if not.

print CGI->header(-type => 'application/json');
print to_json({
	session_ok => sessionIsActive() ? JSON::true : JSON::false
});
