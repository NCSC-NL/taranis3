# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::RedHat;
use base 'Exporter';

use warnings;
use strict;

use Taranis::Install::Bare qw(wrap_print has_internet get_os_info);

use Carp           qw(croak);
use File::Basename qw(basename);

my $epel_v7 = 'http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm';

my $yum  = '/usr/bin/yum';

our @EXPORT = qw(
	redhat_package
	redhat_packages
	redhat_init_epel
);

sub redhat_packages(@) {
	my @packages = @_;

	unless(has_internet) {
		print "--> No internet: no attempt to install/update packages.\n";
		return;
	}

	print "*   install RedHat packages:\n";
	wrap_print '    ', join(' ', @packages);

	my @install_opts = qw(
		--assumeyes
		--quiet
	);

	system $yum, 'install', @install_opts, '--', @_
		and die "ERROR: installation of (some) RedHat packages failed.\n";
}

sub redhat_package($) {
	redhat_packages @_;
}

sub redhat_init_epel() {
	my $os = get_os_info;
	my $os_version = $os->{VERSION_ID} || $os->{VERSION};

	if($os_version !~ /^7/) {
		redhat_package 'epel-release';
		return;
	}

	# RedHat7 does not come with an epel-release installer.

	my @repos = qx($yum repolist);
	if(grep /^epel\b/, @repos) {
		print "*   epel repository already installed.\n";
		return;
	}

	unless(has_internet) {
		print "--> No internet: no attempt to install epel-release.\n";
		return;
	}

	my $rpm  = ($ENV{TMPDIR} || '/tmp') . '/' . basename($epel_v7);
	unless(-f $rpm) {
		print "*   collecting epel-release configuration into $rpm\n";

		system 'wget', '--output-document' => $rpm, '--', $epel_v7
			and die "ERROR: cannot collect $epel_v7 with wget\n";
	}

	print "*   installing epel repository from $rpm\n";

	system 'rpm', '-ivh', $rpm
		and die "ERROR: cannot install epel repository.\n";
}

1;
