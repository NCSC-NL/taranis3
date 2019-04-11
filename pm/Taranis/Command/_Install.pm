# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

# Command the install scripts
#
# Do not use non-core modules here, because this is called during
# taranis-bootstrap as well.  For installed Taranis, we have the
# smart Taranis::Command::Install wrapper.

package Taranis::Command::_Install;
use base 'Exporter';

use warnings;
use strict;

our @EXPORT = qw(
	run_install
);

use File::Basename qw(basename);
use File::Glob     qw(bsd_glob);

sub run_install(%) {
	my %args = @_;

	my $username = $args{username};
	$username ne 'root'
		or die "ERROR: cannot install software under root\n";

	my $home     = $args{home};
	-d $home
		or die "ERROR: home $home does not exist.\n";

	my $script_dirs = $args{scripts} || [];
	@$script_dirs
		or die "ERROR: please tell me where the install scripts are.\n";

	my $use_internet = $args{internet} // 1;
	my $from_git     = $args{from_git} // 0;

	my %scripts;
	foreach my $script_dir (@$script_dirs) {
		foreach my $script (bsd_glob "$script_dir/[0-9]*") {
			my $base = basename $script;
			$scripts{$base} ||= $script;   # first coming wins
		}
	}
	my @scripts = @scripts{sort keys %scripts};

	my $version = $args{version}
		or die "ERROR: the version to install is not specified.";

	# Communicate settings to the 'setup-release' script, which runs after a
	# minimal number of system packages have been installed.
	$ENV{TARANIS_USERNAME} = $username;
	$ENV{TARANIS_VERSION}  = $version;
	$ENV{TARANIS_HOME}     = $home;
	$ENV{TARANIS_INTERNET} = $use_internet ? 'yes' : 'no';
	$ENV{TARANIS_FROM_GIT} = $from_git     ? 'yes' : 'no';
	$ENV{TARANIS_MIGRATE}  = $args{migrate} || '';

	umask 022;

	foreach my $script (@scripts) {
		print "*** running $script\n";
		system $script
			and die "Installation stopped\n";
	}
}

1;
