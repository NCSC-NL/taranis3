#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis::SessionUtil qw(setUserAction);
use Taranis::Session qw(killSession);

my @EXPORT_OK = qw(logoutUser);

sub logout_export {
	return @EXPORT_OK;
}

sub logoutUser {
	my ( %kvArgs ) = @_;
	my ( $message, $vars );

	setUserAction( action => 'logout', comment => 'Logged out');

	killSession;

	return { js => ['js/logout.js']};
}
1;
