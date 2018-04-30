# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Ubuntu;
use base 'Exporter';

use warnings;
use strict;

use Taranis::Install::Bare qw(wrap_print has_internet);

use Carp     qw(croak);

my $apt  = '/usr/bin/apt-get';

our @EXPORT = qw(
	ubuntu_package
	ubuntu_packages
);

sub ubuntu_packages(@) {
	my @packages = @_;

	unless(has_internet) {
		print "--> No internet: no attempt to install/update packages.\n";
		return;
	}

	print "*   install Ubuntu packages:\n";
	wrap_print '    ', join(' ', @packages);

	my @install_opts = qw(
		--assume-yes
		--quiet
	);

	system $apt, 'install', @install_opts, '--', @_
		and die "ERROR: installation of (some) Ubuntu packages failed.\n";
}

sub ubuntu_package($) {
	ubuntu_packages @_;
}

1;
