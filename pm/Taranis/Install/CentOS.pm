# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::CentOS;
use base 'Exporter';

use warnings;
use strict;

use Taranis::Install::Bare qw(wrap_print has_internet);

use Carp     qw(croak);

my $yum  = '/bin/yum';

our @EXPORT = qw(
	centos_package
	centos_packages
);

sub centos_packages(@) {
	my @packages = @_;

	unless(has_internet) {
		print "--> No internet: no attempt to install/update packages.\n";
		return;
	}

	print "*   install CentOS packages:\n";
	wrap_print '    ', join(' ', @packages);

	my @install_opts = qw(
		--assumeyes
		--quiet
	);

	system $yum, 'install', @install_opts, '--', @_
		and die "ERROR: installation of (some) CentOS packages failed.\n";
}

sub centos_package($) {
	centos_packages @_;
}

1;
