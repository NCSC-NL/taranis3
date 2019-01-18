#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

## Taranis-Session.t: tests for Taranis::Session.
## Doesn't test session expiry, since that's heavily tied to mod_perl.

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Test::Most;

use Taranis::Session qw(sessionGet sessionSet sessionIsActive spawnSession killSession);
use Taranis::TestUtil qw(withDistConfig);


withDistConfig {
	ok(!sessionIsActive, "no session active initially");

	lives_ok {
		killSession;
	} "killSession doesn't complain if no session spawned yet";

	throws_ok {
		sessionGet('foo');
	} qr/no session active/, "sessionGet throws when no session active";

	throws_ok {
		sessionSet('foo');
	} qr/no session active/, "sessionSet throws when no session active";

	spawnSession;

	ok(sessionIsActive, "session active after spawnSession");

	is(sessionSet('foo', 0), 0, "sessionSet returns value (0)");
	is(sessionSet('foo', 3), 3, "sessionSet returns value (non-0)");
	is(sessionGet('foo'), 3, "sessionSet/Get works for scalar");
	sessionSet('foo', [qw(a b c d)]);
	cmp_deeply(sessionGet('foo'), [qw(a b c d)], "sessionSet/Get works for array ref");

	killSession;

	ok(!sessionIsActive, "no session active after kill");

	throws_ok {
		sessionGet('foo');
	} qr/no session active/, "can't sessionGet after killSession";

	lives_ok {
		killSession;
	} "killSession doesn't complain if session already dead";
};

done_testing;
