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

use Taranis::SessionUtil qw(right validCsrfHeaderSupplied getSessionUserSettings currentRequest);
use Taranis::Template;
use Taranis::Config::XMLGeneric;
use Taranis::Config;
use Taranis::Users;
use Taranis::FunctionalWrapper qw(Config CGI Users);
use Taranis::Session qw(sessionGet sessionIsActive updateSessionTTL killSession);
use Taranis qw(scalarParam logErrorToSyslog logDebug encode_entities_deep find_config);


# Allow uploads. Need big max request size (100MB) for sources import function.
$CGI::Simple::DISABLE_UPLOADS = 0;
$CGI::Simple::POST_MAX = 100_000_000;

my $route      = currentRequest;
my $isJson     = $route->{type} eq 'load';
my $isDownload = $route->{type} eq 'loadfile';
my $isShortcut = $route->{type} eq 'goto';
my $isMainPage = !$isJson && !$isDownload;

if (!sessionIsActive || !sessionGet('userid')) {
	# User is not logged in.
	if ($isJson) {
		print CGI->header(-status => 403);
	} else {
		print CGI->redirect("login/?cause=nosession&goto=" . uri_escape($ENV{REQUEST_URI}));
	}
} else {
	my $method = $ENV{REQUEST_METHOD} || '';
	eval {
		# Require valid CSRF token for anything but GET and HEAD requests.
		die 403 unless $method eq 'GET' || $method eq 'HEAD' || validCsrfHeaderSupplied;

		# Make sure you can only get beyond this if the user has read or write right for the requested script.
		# Execute right and particularization has to be figured in the script.
		unless (right('read') || right('write') || $route->{pageName} eq 'logout') {
			die 403;
		}

		if ($isDownload) {
			$method eq 'GET' or die 405;

			# Run action, ignore return value. For downloads, the action is expected to output directly to STDOUT.
			performAction();

		} elsif ($isJson) {
			$method eq 'POST' or die 405;

			my $result;
#XXX MO: Exception logging needs to be reorganized.  Requires quite some work
#    to make this work correctly.  Ajax errors might end-up in
#    /tmp/systemd*apache2*/tmp/taranis-errors
eval {
			$result = performAction();

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
};
if($@) {
	warn "AJAX ERROR: $@";
	if(open my $out, '>>', '/tmp/taranis.errors') {
		use Data::Dumper;
		$out->print("**** ", scalar(localtime), "\n$@", Dumper $result);
	}
}

		} elsif ($isMainPage) {
			$method eq 'GET' or die 405;
			updateSessionTTL;

			# Render main page.
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
			my $fullname = Users->getUserFullname($username) || $username;

			my $vars = {
				user => $username,
				fullname => encode('UTF-8', decode_entities($fullname)),
				pageSettings => getSessionUserSettings(),
				shortcutSettings => $isShortcut ? scalar to_json($shortcutSettings) : undef,
				csrfToken => sessionGet('Taranis::Session/csrf_token'),
			};

			my $tt = Taranis::Template->new;
			$tt->processTemplateWithHeaders("main.tt", $vars);
		} else {
			die 404;
		}
	};
	if (my $exception = $@) {
		(my $statusCode) = $exception =~ /^(\d\d\d)/a;
		if($statusCode < 400 || $statusCode >= 500) {
			# Unexpected internal error.
			logErrorToSyslog
				"Internal error during $method $ENV{REQUEST_URI}: $exception";
			$statusCode = 500;
		}
		print CGI->header(-status => $statusCode);
	}
}

sub performAction {
	#XXX It should not be needed to recompute the $route here, however... mod_cgi is
	# playing tricks with the execution of this module: it wraps the whole code into
	# a sub.  However, all subs are global: "$route does not stay shared" error.
	my $route      = currentRequest;
	my $modName    = $route->{modName}  or die 404;
	my $scriptName = $route->{pageName} or die 404;
	my $subName    = $route->{action}   or die 404;

	my $kvArgs     = {};
	if(my $term = scalarParam('term')) {
		$kvArgs = encode_entities_deep({term => $term});
	} elsif(my $params = scalarParam('params')) {
		$kvArgs = encode_entities_deep(from_json $params);
	}

	my $tool = $kvArgs->{tool} || '';
	$modName !~ /\W/a && $scriptName !~ /\W/a or die 404;
	$modName ne 'tools' || $tool !~ /\W/a or die 404;

	my $scriptBase = "mod_$modName/"
		. ($modName eq 'tools' ? "$tool/" : '')
		. "$scriptName.pl";

	my @scriptDirs = split /\:/, $ENV{MODPERL_PATH};
	(my $scriptFile) = grep -f, map "$_/$scriptBase", @scriptDirs;
	$scriptFile or die 404;

	require $scriptFile;

	no strict 'refs';
	my @exportList = &{"${scriptName}_export"};
	grep $_ eq $subName, @exportList or die 404;

	return $subName->(%$kvArgs);   # function got compiled into this namespace
}

# During 2017, all JSON serializers became "smart" in distinguishing
# between numbers (42) and numbers-as-string ("42").  Javascript finds
# them different!  This broke Taranis.  Destroy the "smart" behavior
# of Perl's JSON modules.
sub _trust_numbers($);
sub _trust_numbers($) {
	for($_[0]) {
		if(!ref) { $_ += 0 if /^\d+$/a }
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
