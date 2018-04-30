#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized redefine);

use URI::Escape;
use JSON;
use CGI::Simple;
use Encode qw(decode encode);
use HTML::Entities qw(decode_entities);

use Taranis::SessionUtil qw(right validCsrfHeaderSupplied getSessionUserSettings);
use Taranis::Template;
use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::Users;
use Taranis::FunctionalWrapper qw(Config CGI Users);
use Taranis::Session qw(sessionGet sessionIsActive updateSessionTTL killSession);
use Taranis::RequestRouting qw(currentRequest);
use Taranis qw(scalarParam logErrorToSyslog logDebug encode_entities_deep find_config);


# Allow uploads. Need big max request size (100MB) for sources import function.
$CGI::Simple::DISABLE_UPLOADS = 0;
$CGI::Simple::POST_MAX = 100_000_000;

my $isJson     = currentRequest->{type} eq 'load';
my $isDownload = currentRequest->{type} eq 'loadfile';
my $isShortcut = currentRequest->{type} eq 'goto';
my $isMainPage = !$isJson && !$isDownload;

if (!sessionIsActive || !sessionGet('userid')) {
	# User is not logged in.
	if ($isJson) {
		print CGI->header(-status => 403);
	} else {
		print CGI->redirect("login/?cause=nosession&goto=" . uri_escape($ENV{REQUEST_URI}));
	}
} else {
	eval {
		# Require valid CSRF token for anything but GET and HEAD requests.
		die 403 unless $ENV{REQUEST_METHOD} =~ /^GET|HEAD$/ or validCsrfHeaderSupplied;

		# Make sure you can only get beyond this if the user has read or write right for the requested script.
		# Execute right and particularization has to be figured in the script.
		unless (right('read') || right('write') || currentRequest->{pageName} eq 'logout') {
			die 403;
		}

		if ($isDownload) {
			die 405 unless $ENV{REQUEST_METHOD} eq 'GET';

			# Run action, ignore return value. For downloads, the action is expected to output directly to STDOUT.
			performAction();

		} elsif ($isJson) {
			die 405 unless $ENV{REQUEST_METHOD} eq 'POST';

eval {
			my $result = performAction();

			if (lc Config->{testmode} eq 'on') {
				my $json = to_json({page => $result});
				$json =~ s/^(.{1000})....+/$1.../g;

				logDebug(
					"JSON request to $ENV{REQUEST_URI}: " .
					join('    &    ', map {uri_unescape $_} split(/\&/, CGI->query_string)) .
					"\n--> Response: $json\n"
				);
			}

			sendJsonResponse($result);
}; warn "AJAX ERROR: $@" if $@;

		} elsif ($isMainPage) {
			die 405 unless $ENV{REQUEST_METHOD} eq 'GET';

			updateSessionTTL;

			# Render main page.
			my $tt = Taranis::Template->new;
			my $shortcutSettings;

			if ($isShortcut) {
				my $fn = find_config(Config->{shortcutsconfig});
				my $shortcuts = Taranis::Config::XMLGeneric->new(
					$fn, "shortcut", "shortcuts"
				);
				my ($shortcut) = $ENV{REQUEST_URI} =~ m{goto/(.*?)/?$}i;
				$shortcutSettings = $shortcuts->getElement($shortcut) or die 404;
			}

			my $username = sessionGet('userid');
			my $user     = Users->getUser($username);
			my $fullname = $user ? decode_entities($user->{fullname}) : $username;

			my $vars = {
				user => $username,
				fullname => encode('UTF-8', $fullname),
				pageSettings => getSessionUserSettings(),
				shortcutSettings => $isShortcut ? scalar to_json($shortcutSettings) : undef,
				csrfToken => sessionGet('Taranis::Session/csrf_token'),
			};

			$tt->processTemplateWithHeaders("main.tt", $vars);
		} else {
			die 404;
		}
	};
	if (my $exception = $@) {
		# HTTP 4XX Client Error (e.g. 404 Not Found) is ok; don't log or make a fuss about those.
		my $statusCode;
		unless (($statusCode) = $exception =~ /^(4[0-9]{2})/) {
			# Something, somewhere raised an exception that wasn't caught, and wasn't an innocent 4XX; this shouldn't
			# occur unless something is wrong internally, so log it and return 500 Internal Server Error.
			logErrorToSyslog
				'Internal error during ' . $ENV{REQUEST_METHOD} . ' request to ' . $ENV{REQUEST_URI} . ': '
				. $exception;
			$statusCode = 500;
		}
		print CGI->header(-status => $statusCode);
	}
}

sub performAction {
	my $modName    = currentRequest->{modName}  or die 404;
	my $scriptName = currentRequest->{pageName} or die 404;
	my $subName    = currentRequest->{action}   or die 404;

	my $kvArgs;
	if (scalarParam('term')) {
		$kvArgs = encode_entities_deep({ 'term' => scalarParam('term') });
	} else {
		$kvArgs = scalarParam('params') ? encode_entities_deep(from_json scalarParam('params')) : {};
	}

	die 404 unless $modName =~ /^[A-Za-z_\d]+$/ && $scriptName =~ /^[A-Za-z_\d]+$/;
	die 404 if $modName eq 'tools' && $kvArgs->{tool} =~ /[^A-Za-z_\d]/;

	my $scriptBase = "mod_$modName/"
		. ($modName eq 'tools' ? "$kvArgs->{tool}/" : '')
		. "$scriptName.pl";

	my @scriptDirs = split /\:/, $ENV{MODPERL_PATH};
	(my $scriptFile) = grep -f, map "$_/$scriptBase", @scriptDirs;
	$scriptFile or die 404;

	require $scriptFile;

	# Get the list of subroutines which are available.
	# Every script must have a subroutine which returns @EXPORT_OK.  The name of the subroutine is the name of the
	# script plus a suffix '_export', i.e. the export subroutine of assess.pl is &assess_export.
	# The "&{\&{<subName>}}" is a dirty way to call subroutine by name without "use strict" complaining. It would
	# complain if we just did &{<subName>}. We really shouldn't be calling subroutines by user-supplied names.
	my @exportList = &{\&{$scriptName . '_export'}};

	die 404 unless grep { $_ eq $subName } @exportList;
	return &{\&{$subName}}(%$kvArgs);
}

# During 2017, all JSON serializers became "smart" in distinguishing
# between numbers (42) and numbers-as-string ("42").  Javascript finds
# them different!  This broke Taranis.  Destroy the "smart" behavior
# of Perl's JSON modules.
sub _trust_numbers($);
sub _trust_numbers($) {
	for($_[0]) {
		if(!ref) { $_ += 0 if /^[0-9]+$/ }
		elsif(ref eq 'ARRAY') { _trust_numbers $_ for @$_ }
		elsif(ref eq 'HASH')  { _trust_numbers $_ for values %$_ }
	}
}

sub sendJsonResponse {
	my ($page) = @_;
	_trust_numbers $page;

	print CGI->header(-type => 'application/json');
	print to_json({page => $page});
}
