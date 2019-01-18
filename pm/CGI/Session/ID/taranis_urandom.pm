# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package CGI::Session::ID::taranis_urandom;

## CGI::Session::ID::taranis_urandom: ID generator for CGI::Session.
##
## Thin wrapper around &Taranis::generateToken.
## Usage: CGI::Session->load('id:taranis_urandom', ...)  # CGI::Session will prepend 'CGI::Session::ID::'.
##
## The default CGI::Session ID generators are quite insecure, being based on rand() and such. We could use
## CGI::Session::ID::crypt_openssl, that's not included in the default CGI::Session distribution, and it seems
## a shame to introduce another dependency when we can just use &Taranis::generateToken.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Taranis qw(generateToken);


our @ISA = qw(CGI::Session::ErrorHandler);


sub generate_id {
    return generateToken(32);
}

1;
