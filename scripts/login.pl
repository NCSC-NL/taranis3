#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Crypt::SaltedHash;
use ModPerl::Util;
use HTML::Entities qw(encode_entities);

use Taranis::Users qw(ensureModernHash checkUserPassCombination);
use Taranis::SessionUtil qw(setUserAction);
use Taranis::Session qw(sessionGet sessionIsActive);
use Taranis::Role;
use Taranis::Config;
use Taranis::Template;
use Taranis::FunctionalWrapper qw(Config Role Template Users CGI);
use Taranis qw(scalarParam);
use Taranis::Session qw(sessionCsrfToken sessionIsActive sessionSet spawnSession);


if (sessionIsActive && sessionGet('userid')) {
	# User is logged in.
	print CGI->redirect("/taranis/");
}

if ($ENV{REQUEST_METHOD} eq 'POST' && scalarParam("login_sso_form_submitted")) {
	# SSO login attempt.
	if (sessionIsActive && scalarParam('csrf_token') eq sessionCsrfToken) {
		if (Users->{dbh}->checkIfExists({username => $ENV{REMOTE_USER}, disabled => 0}, "users")) {
			processSuccessfulLogin($ENV{REMOTE_USER});
		} else {
			processFailedLogin($ENV{REMOTE_USER});
		}
	} else {
		showLoginForm("There was an error submitting the login form. Please try again.");
	}
} elsif ($ENV{REQUEST_METHOD} eq 'POST' && scalarParam("login_userpass_form_submitted")) {
	# Normal login attempt.
	if (sessionIsActive && scalarParam('csrf_token') eq sessionCsrfToken) {
		my $username = encode_entities( scalarParam("username") );
		my $password = encode_entities( scalarParam("password") );
		if (checkUserPassCombination($username, $password)) {
			ensureModernHash($username, $password);
			processSuccessfulLogin($username);
		} else {
			processFailedLogin($username);
		}
	} else {
		showLoginForm("There was an error submitting the login form. Please try again.");
	}
} else {
	showLoginForm();
}


sub showLoginForm {
	my ($errorMsg) = @_;

	# Need a session for our anti-CSRF token. If user already has a session, leave it be: we do not (cannot) check the
	# CSRF token here, so if we nuked existing sessions here that would allow an attacker to log users out by CSRF.
	spawnSession if !sessionIsActive;

	my $vars = {
		goto_url => getGotoUrl(),
		csrf_token => sessionCsrfToken,
	};

	if ($errorMsg) {
		$vars->{error} = $errorMsg;
	} elsif (scalarParam('cause') && scalarParam('cause') eq 'nosession') {
		$vars->{error} = 'No active session found, please log in.';
	}

	if (Config->getSetting('sso') =~ /^on$/i and $ENV{REMOTE_USER}) {
		$vars->{sso_user} = $ENV{REMOTE_USER};
	}

	Template->processTemplateWithHeaders("login.tt", $vars);
}

sub processFailedLogin {
	my ($username) = @_;

	Users->logBadLoginAttempt($username);
	showLoginForm("Incorrect username or password");
}

sub processSuccessfulLogin {
	my ($username) = @_;

	if (!Role->getRolesFromUser(username => $username)) {
		return showLoginForm("No roles configured for user $username.");
	}

	spawnSession;  # Replace existing session, just to be on the safe side.
	sessionSet('userid', $username);

	Users->setUser(username  => $username, datestart => undef, datestop  => undef)
		or croak "Failed to update user information during login";

	setUserAction(
		username => $username,
		entitlement => "generic",
		action => "login",
		comment => "Logged in"
	);
	print CGI->redirect(getGotoUrl());
}

sub getGotoUrl {
	return scalarParam('goto') && scalarParam('goto') =~ m{^/taranis/}
		? encode_entities( scalarParam('goto') )
		: "/taranis/";
}
