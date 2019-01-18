# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Config;
use base 'Exporter';

use warnings;
use strict;
use utf8;

use Carp       qw(confess);
use English    qw($EUID);
use File::Glob qw(bsd_glob);
use POSIX      qw(setuid setgid);

use Taranis::Install::Util qw(read_json write_json);

our @EXPORT = qw(
	set_default_release
	config_release save_config_release
	config_generic save_config_generic
	installed_versions sort_versions
	sorted_available_versions
	newest_installed_version is_newest_version
	taranis_sources become_user_taranis
	taranis_config_fn taranis_config
	appconfig_path
);

my (%_config_releases, $_config_generic, $_taranis_config);

sub config_generic(;$) {
	my $filebase = shift;

	return $_config_generic
		if $_config_generic;

	unless($filebase) {
		my $home  = $ENV{TARANIS_HOME} || $ENV{HOME} or die "No HOME";
		$filebase = "$home/etc/setup-generic";
	}

	my $generic   = read_json "$filebase.json";
	$generic->{filebase} = $filebase;

	$_config_generic = $generic;
}

sub save_config_generic($) {
	my $generic  = $_config_generic = shift;
	my $filebase = $generic->{filebase};
	$generic->{last_update} = localtime;

	my $filename = "$filebase.json";
	write_json $filename, $generic;
	$filename;
}

sub config_release(;$) {
	my $generic  = config_generic;
	my $version  = shift || $generic->{default_version}
		or die "ERROR: don't know which release";

	return $_config_releases{$version}
		if $_config_releases{$version};

	my $filebase = "$generic->{etc}/setup-$version";

	my $release  = read_json "$filebase.json";
	$release->{filebase} = $filebase;
	$_config_releases{$version} = $release;
}

sub save_config_release($) {
	my $release  = shift;
	my $version  = $release->{version} or confess;

	my $generic  = config_generic;
	my $filebase = $release->{filebase}
		||= "$generic->{etc}/setup-$version";

	$release->{last_update} = localtime;
	$_config_releases{$version} = $release;

	my $filename = "$filebase.json";
	write_json $filename, $release;
	$filename;
}

sub set_default_release(%) {
	my %set = @_;
	my $version = $set{release_version}
		or die "ERROR: release version required\n";

	my $generic = eval { config_generic } || {};
	my $user    = $generic->{username}
		= $set{username}
		|| $generic->{username}
		|| ($EUID==0 ? 'taranis' : getpwuid($EUID));

	my $home    = $generic->{home}
		= $set{home}
		|| $generic->{home}
		|| (getpwnam $user)[7];

	my $etc     = $generic->{etc} ||= "$home/etc";
	$generic->{filebase} ||= $set{filebase} || "$etc/setup-generic";
	$generic->{default_version} = $version;

	save_config_generic $generic;
}

sub installed_versions() {
	my $generic = config_generic;

	my $home    = $generic->{home} or confess;
	my %versions;
	foreach my $subdir (bsd_glob "$home/taranis-*") {
		$versions{$1} = $subdir if $subdir =~ m{/taranis-([0-9a-z.-]+)$};
	}

	\%versions;
}

# The actual numeric representation does not matter, as long
# as it gives us the expected order.
sub _version_order_code($) {
	my $version = shift;

	$version  =~ m/^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-(rc|alpha|beta)([0-9]+))?$/
		or return "9999-$version";

	my $set
	 = ! $4          ? 'Z'
	 : $4 eq 'alpha' ? 'A'
	 : $4 eq 'beta'  ? 'B'
	 : $4 eq 'rc'    ? 'R'
	 : confess;

	sprintf "%03d%03d%03d%s%03d", $1, $2, $3, $set, ($5 || 0);
}

sub sort_versions(@) {
	my %order = map +(_version_order_code($_), $_), @_;
	@order{sort keys %order};
}

sub newest_installed_version() {
	my $versions = installed_versions;
	my $newest   = (sort_versions keys %$versions)[-1];
	defined $newest ? ($newest, $versions->{$newest}) : ();
}

sub is_newest_version($) {
	my $version  = shift;
	my ($newest) = newest_installed_version;
	defined $newest ? $version eq $newest : 1;
}

# Produces a table which can be used for selection.  When a version
# is provided, it will get added to the right place in the table (unless
# it already exists).  In that case, the mentioned version will have a
# true value in the third column.
sub sorted_available_versions(;$) {
	my $this_version = shift // '';

	my $versions     = installed_versions;
	$versions->{$this_version} ||= '';

	map +[ $_, $versions->{$_}, $_ eq $this_version ],
		sort_versions keys %$versions;
}

sub taranis_sources($) {
	my $version  = shift;

	my $generic  = config_generic;
	my $release  = config_release $version;

	my $from_git = $ENV{TARANIS_FROM_GIT} || 'no';
	if($from_git eq 'no') {
		# Installed from source package
		my $unpacked = "$release->{sources}/taranis-$version";
		return $unpacked if -d $unpacked;
		die "ERROR: cannot find sources for $version.\n";
	}

	# Try to retrieve from git
	my $git_src  = "$generic->{home}/sources/taranis-git";
	-d $git_src or die <<_NO_GIT;
ERROR: version $version from is not available.
       You may consider to configure GIT as source for your installations.
	       su -l $generic->{username} -c "taranis git init"
_NO_GIT

	# Only one of the installation scripts checks whether we have the
	# correct release checked-out.
	$git_src;
}

sub become_user_taranis() {
	my $generic = config_generic;

	my ($userid, $groupid, $home) = (getpwnam $generic->{username})[2,3,7];
	defined $userid or die "no user $generic->{username}\n";
	setgid $groupid;
	setuid $userid;
	$ENV{HOME} = $home;
}

sub appconfig_path(;$) {
	my $version = shift;
	my $generic = config_generic;

	my $release = config_release $version;

	grep -d,
		$release->{extension},
		$generic->{extension},
		$generic->{home};
}

sub taranis_config_fn() {
	my $generic = config_generic;
	"$generic->{etc}/taranis.conf.xml";
}

sub taranis_config() {
	# For install scripts below 220 (which install perl modules), dependencies
	# for this function may not be present yet.
	eval "require Taranis::Config" or die $@;
	$_taranis_config ||= Taranis::Config->new(taranis_config_fn);
}

1;
