# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Session;

## Taranis::Session: wrapper around CGI::Session.
##
## Synopsis:
##
## use Taranis::Session qw(sessionGet sessionSet sessionIsActive spawnSession killSession updateSessionTTL);
##
## spawnSession;                                 # Start new session, implicitly killing the current session (if any).
## sessionSet('userid', 'johnny');               # Implicitly flushes data to disk.
## say "Hello, " . sessionGet('userid');
## updateSessionTTL;                             # "Touch" session so that it won't expire for Config->{session_expire}
##                                               # more time.
## killSession;                                  # Delete session (and flush the deletion to disk).
## say sessionGet('userid');                     # Will throw exception, because there is no session.
## say sessionGet('userid') if sessionIsActive;  # A safer version.
##
## Sessions expire after Config->{session_expire} time has passed; call updateSessionTTL() to update the timestamp and
## thus extend the lifetime of the session. Note that this differs from CGI::Session's expiry mechanism; CGI::Session
## updates its timestamp every time the session is opened. We don't want that: when our client-side JavaScript decides
## to refresh some data in the background, that shouldn't extend the session lifetime (otherwise the session would
## never expire).


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Apache2::RequestUtil;
use CGI::Session qw(-ip_match);
use CGI::Simple;

use Taranis qw(generateToken str2seconds tmp_path);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config CGI);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(sessionCsrfToken sessionGet sessionSet sessionIsActive spawnSession killSession updateSessionTTL);

my $session_dsn  = 'driver:file;id:taranis_urandom';
my $sessions_dir = tmp_path 'sessions';
my %session_opts = ( Directory => $sessions_dir );

# Fetch user's session, if he has one and it hasn't expired.
sub _sessionLoad {
	my $sessionRef = _sessionStorageRef();

	if (!$$sessionRef) {
		# May die when the session file disappeared unexpectedly.
		#XXX error should be logged.
		$$sessionRef = eval {CGI::Session->load($session_dsn, CGI, \%session_opts)}
			or return undef;

		# Only check for session expiry the first time we load an existing session from the datastore, i.e. no more
		# than once per HTTP request. If we did it for every call, we might kill a session halfway during a request,
		# which would be very mean to the caller.
		_killSessionIfExpired()
			# Expiring won't work, and doesn't make sense, when we're running outside CGI (e.g. in a cronjob), so don't
			# even try.
			if $ENV{MOD_PERL};
	}

	# CGI::Session->load returns an object even if there is no session. Ignore such 'empty' session objects.
	if ($$sessionRef->is_empty) {
		$$sessionRef = undef;
	}

	return $$sessionRef;
}

sub _killSessionIfExpired {
	my $sessionRef = _sessionStorageRef();
	return if $$sessionRef->is_empty;

	killSession() if
		# ... it hasn't been active in more than {session_expire} time.
		time > _expiryInSeconds() + (sessionGet('Taranis::Session/last_activity') || 0);
}

# CGI::Session will expire the session only when the session hasn't been used at all for a while. We have client-side
# JS doing refresh requests all the time, and we don't want that to keep the session alive forever.
# Therefore, keep track of session activity ourselves.
sub updateSessionTTL {
	croak "updateSessionTTL: no active session" unless sessionIsActive();
	sessionSet('Taranis::Session/last_activity', time);
}

sub sessionIsActive {
	return !!_sessionLoad();
}

# Fetch session parameter.
sub sessionGet {
	my ($key) = @_;

	my $session = _sessionLoad() or croak "sessionGet: no session active";
	return $session->param($key);
}

# Set session parameter.
sub sessionSet {
	my ($key, $val) = @_;

	my $session = _sessionLoad() or croak "sessionSet: no session active";
	$session->param($key, $val);
	$session->flush;
	return $val;
}

# Nuke current session, if any.
sub killSession {
	my $sessionRef = _sessionStorageRef();
	if ($$sessionRef) {
		$$sessionRef->delete;
		$$sessionRef->flush;
	}
}

sub sessionCsrfToken {
	return sessionGet('Taranis::Session/csrf_token');
}

# Spawn new session.
sub spawnSession {
	killSession() if sessionIsActive();

	my $sessionRef = _sessionStorageRef();
	$$sessionRef = CGI::Session->new($session_dsn, CGI, \%session_opts)
		or die "Error creating session: " . CGI::Session->errstr;

	# Set cookie.
	my $is_secure = (Config->{session_secure_cookie} =~ /^yes$/i);
	my $cookie = $$sessionRef->cookie(-httponly => 1, -secure => $is_secure);
	print CGI->header(-cookie => $cookie);

	# Set CGI::Session expiry. Do this after setting the cookie, so that the cookie doesn't get an expiry time, which
	# would change it from a session cookie (expires when the browser closes) into a persistent cookie (has expiry
	# time, but survives browser close/reopen).
	$$sessionRef->expire(_expiryInSeconds());

	# Set our own expiry.
	updateSessionTTL();

	sessionSet('Taranis::Session/csrf_token', generateToken(32));

	return $$sessionRef;
}

sub _sessionStorageRef {
	# Use mod_perl's pnotes, or a simple state variable, depending on whether we're running under mod_perl.
	# mod_perl's pnotes makes sure that our session object get destroyed at the end of the Apache request. Otherwise it
	# would be reused for other requests (by other users!), which would be very bad.
	state $state_session;

	# -> request requires Apache config  "PerlOptions +GlobalRequest"
	return $ENV{MOD_PERL} ? \Apache2::RequestUtil->request->pnotes->{"Taranis::Session/session"} : \$state_session;
}

# Cast Config->{session_expire} to seconds.
sub _expiryInSeconds {
	my $expString = Config->{session_expire};
	if ($expString =~ /^\d+$/) {
		carp "unitless <session_expire> values are deprecated - assuming '$expString' means '${expString}s'";
		$expString .= 's';
	}
	return eval { str2seconds($expString) }
		|| croak "invalid value for <session_expire>: '$expString'";
}

1;
