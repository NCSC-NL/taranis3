#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

# make sure we are in a sane environment.
$ENV{MOD_PERL} or die "GATEWAY_INTERFACE not Perl!";

use File::Basename qw(dirname);
use ModPerl::Registry;
use Apache2::ServerUtil;
use Apache::DBI;
#use Apache::AuthDBI;

=pod

use Taranis::Config;
my $cfg      = Taranis::Config->new();

# Refuse to run if critical config settings are missing.
{
	my @mandatory_settings = qw/session_secure_cookie dbname/;  # TODO: expand this list, there are many more.
	my @missing_mandatory_settings = grep { !$cfg->{$_} } @mandatory_settings;
	if (@missing_mandatory_settings) {
		die "Mandatory settings missing in taranis.conf.xml: " .
			join(", ", map("<$_>", @missing_mandatory_settings));
	}
}

if (!$ENV{HTTPS} and $cfg->{session_secure_cookie} =~ /^yes$/) {
	# Session cookie secure flag is on, but by the looks of it we're not running on HTTPS. If indeed we're not running
	# on HTTPS, then login won't work. Leave a warning in the log to maybe help the admin.
	# (We're just guessing here, since there's no surefire way to tell if we're running on HTTPS. If we're not,
	# then it's a pretty nasty problem to debug, so err on the side of too much info.)
	Apache2::ServerUtil->server->warn(
		q{Taranis: looks like I may be running on unencrypted HTTP. } .
		q{Are you sure <session_secure_cookie> should be set to YES in } .
		'taranis.conf.xml' .
		" ?"
	);
}

my $user     = $cfg->{'dbuser'};
my $name     = $cfg->{'dbname'};
my $pass     = $cfg->{'dbpasswd'};
my $dbhost   = $cfg->{'dbhost'};
my $dbi      = $cfg->{'dbi'};
my $dbdriver = $cfg->{'dbdriver'};
my $dbport   = $cfg->{'dbport'};
my $sslmode = ( $cfg->{'dbsslmode'} =~ /^(disable|allow|prefer|require)$/ ) ? $cfg->{'dbsslmode'} : 'prefer';

# optional configuration for Apache::DBI.pm:

# choose debug output: 0 = off, 1 = quiet, 2 = chatty
#$Apache::DBI::DEBUG = 2;

# configure all connections which should be established during server startup.
# keep in mind, that if the connect does not succeeed, your server won't start
# until the connect times out (database dependent) !
# you may use a DSN with attribute settings specified within
Apache::DBI->connect_on_init("$dbi:$dbdriver(AutoCommit=>1):dbname=$name;host=$dbhost;port=$dbport;sslmode=$sslmode", "$user", "$pass");

# configure the ping behavior of the persistent database connections
# you may NOT not use a DSN with attribute settings specified within
# $timeout = 0  -> always ping the database connection (default)
# $timeout < 0  -> never  ping the database connection
# $timeout > 0  -> ping the database connection only if the last access
#                  was more than timeout seconds before
#Apache::DBI->setPingTimeOut("dbi:driver:database", $timeout);


# optional configuration for Apache::AuthDBI.pm:

# choose debug output: 0 = off, 1 = quiet, 2 = chatty
#$Apache::AuthDBI::DEBUG = 2;

# set lifetime in seconds for the entries in the cache
#Apache::AuthDBI->setCacheTime(0);

# set minimum time in seconds between two runs of the handler which cleans the cache
#Apache::AuthDBI->setCleanupTime(-1);

# use shared memory of given size for the cache
#Apache::AuthDBI->initIPC(50000);


use ModPerl::MethodLookup;
ModPerl::MethodLookup::preload_all_modules();
#use ModPerl::Registry();

=cut

1;
