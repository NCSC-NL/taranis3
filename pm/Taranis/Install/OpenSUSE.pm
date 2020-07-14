# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::OpenSUSE;
use base 'Exporter';

use warnings;
use strict;

use Taranis::Install::Bare qw(wrap_print has_internet get_os_info);

use Carp     qw(croak);

my $zypper  = '/usr/bin/zypper';

our @EXPORT = qw(
	opensuse_package
	opensuse_packages
	is_tumbleweed
);

sub opensuse_packages(@) {
	my @packages = @_;

	unless(has_internet) {
		print "--> No internet: no attempt to install/update packages.\n";
		return;
	}

	print "*   install openSUSE packages:\n";
	wrap_print '    ', join(' ', @packages);

	my @install_opts = qw(
		--auto-agree-with-licenses
		--no-recommends
		--force-resolution
		--no-confirm
	);

	#XXX even when quiet, still produces a blank line.
	system $zypper, '--quiet', 'install', @install_opts, '--', @_
		and die "ERROR: installation of (some) opensuse packages failed.\n";
}

sub opensuse_package($) {
	opensuse_packages @_;
}

sub is_tumbleweed() {
	get_os_info->{ID} =~ /tumbleweed/i
}

1;
