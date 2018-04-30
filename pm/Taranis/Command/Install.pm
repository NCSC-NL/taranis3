# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Install;

use warnings;
use strict;

use File::Spec::Functions    qw(rel2abs);
use English                  qw($EUID $PROGRAM_NAME);
use POSIX                    qw(getpwuid);

use Taranis::Command::_Install qw(run_install);
use Taranis::Install::Bare   qw(unpack_tar version_from_filename);
use Taranis::Install::Config qw(config_generic config_release taranis_sources);
use Taranis::Install::Git    qw(git_last_tag git_checkout);

Taranis::Commands->plugin(install => {
	handler       => \&taranis_install,
	requires_root => 1,
	getopt        => [
    	'home|h=s',
    	'internet!',   # --no-internet
		'scripts|s=s',
    	'version|v=s',
		'git!',
	],
	help          => <<'__HELP',
OPTIONS:
  -h --home DIR         where to install
  -s --scripts PATH     path of scripts to be run (run sorted, [0-9]*)
  -v --version STRING   version to installed (default from current directory)
  --no-internet         do not check external sources for update
  --git --no-git        use latest from release-VERSION branch

Without <tarfile>, the sources are taken from the current directory.
__HELP
} );

sub taranis_install(%) {
	my %args    = @_;

	my $files       = $args{files} || [];
	@$files < 2
		or die "ERROR: you can only install one tar-ball at a time\n";
	my $tarball     = $files->[0];

	my $enforce_git = $args{git};
	my $version     = $args{version};
	my @script_dirs = split /\:/, $args{scripts} || '';

	my $generic     = config_generic $::setup_generic;
	my $home        = $generic->{home};
	my $sources     = "$home/sources";
	my $git_src     = "$sources/taranis-git";

	if($tarball) {
		($version, $enforce_git, @script_dirs) = ();
		$version = version_from_filename $tarball
			or die "ERROR: Cannot derive version name from '$tarball'\n";
		 unpack_tar $tarball => $sources;
	}

	my $username = $generic->{username} || getpwuid $EUID;
	my ($userid, $realhome) = (getpwnam $username)[0,7];
	defined $userid
    	or die "ERROR: cannot find taranis user '$username'.\n";

	$home eq $realhome
    	or print "WARNING: installing Taranis outside the user's home directory.\n";

	my $from_git = 0;
	if(!defined $version) {
		$version ||= $ENV{TARANIS_VERSION} || $generic->{default_version};

	} elsif($version eq 'git') {
		# When we are in git, we derive the version from the last tag.
		my $tag = git_last_tag $git_src || 'no tag';
		$tag    =~ m/^(?i:release-|v)([a-z0-9.\-]+)$/
			or die "ERROR: cannot determine version from git tag '$tag'";

		$version  = $1;
		$from_git = 1;

	} elsif($enforce_git) {
		# Installed via a package, upgraded to git
		-d "$git_src/.git" or die <<__GIT_INSTALL;
ERROR: git not available.  First run as user $username:
	taranis git init
__GIT_INSTALL

		# The version should correspond to (the last part of) a tag

		# take the latest code from a branch in git
		git_checkout $git_src, $version;

		$from_git = 1;
	} elsif($version) {
		# Re-install a package
		-d "$sources/taranis-$version"
			or die "ERROR: package $version is not available.\n";
	}

	$version or die <<'__DETECT_VERSION';

ERROR: I tried to be smart, but still could not determine which version
       you want to have installed.  Please use the '--version' option.

__DETECT_VERSION

	unless(@script_dirs) {
		# It is acceptable when the same directory gets included (maybe
		# with different paths via symlinks) more than once.
		# The order of the directories, however, is very important: only
		# the first script found with a basename will be run.

		@script_dirs = grep -d, map "$_/install",
			'.',
			"$home/local-$version",
			"$home/local",
			($from_git ? $git_src : "$sources/taranis-$version"),
			;
	}

	print "*   start installing version $version\n";

	run_install
		home     => $home,
		internet => $args{internet} // 1,
		scripts  => \@script_dirs,
		username => $username,
		version  => $version,
		from_git => $from_git;
}

1;
