# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Install;

use warnings;
use strict;

use File::Spec::Functions    qw(rel2abs);
use English                  qw($EUID $PROGRAM_NAME);
use POSIX                    qw(getpwuid);
use File::Remove             qw(remove);
use Cwd                      qw(getcwd);

use Taranis::Command::_Install qw(run_install);
use Taranis::Install::Bare   qw(unpack_tar version_from_filename);
use Taranis::Install::Config qw(config_generic config_release taranis_sources
	sort_versions installed_versions);
use Taranis::Install::Git    qw(git_last_tag git_checkout git_checked_out);

sub taranis_remove(%);

Taranis::Commands->plugin(install => {
	handler       => \&taranis_install,
	requires_root => 1,
	getopt        => [
    	'home|h=s',
    	'internet!',   # --no-internet
		'remove|r=s',
		'scripts|s=s',
    	'version|v=s',
		'git!',
	],
	help          => <<'__HELP',
USAGE:
  taranis install [-hsv] [<tarball>]
  taranis install --remove <version>

OPTIONS:
  -h --home DIR         where to install
  -r --remove VERSION   do not install, but remove version
  -s --scripts PATH     path of scripts to be run (run sorted, [0-9]*)
  -v --version STRING   version to installed (default from current directory)
  --no-internet         do not check external sources for update
  --git --no-git        use latest from release-VERSION branch

Without <tarfile>, the sources are taken from the current directory.
__HELP
} );

sub taranis_install(%) {
	my %args    = @_;

	return taranis_remove(%args)
		if $args{remove};

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

		if(-d "$sources/taranis-$version") {
			print "*   reusing already unpacked sources\n";
		} else {
			unpack_tar $tarball => $sources;
		}
	}

	my $username = $generic->{username} || getpwuid $EUID;
	my ($userid, $realhome) = (getpwnam $username)[0,7];
	defined $userid
    	or die "ERROR: cannot find taranis user '$username'.\n";

	$home eq $realhome
    	or print "WARNING: installing Taranis outside the user's home directory.\n";

	my $from_git = 0;
	$version ||= version_from_filename(getcwd)
			 ||= $ENV{TARANIS_VERSION}
			 ||  $generic->{default_version};

	if($version eq 'git') {
		# release-3.4 is public release, take as is package
		# release-3.5-rc is volatile; use latest from git without copying
		# other (develop etc) are also volatile

		my $branch = git_checked_out $git_src
			or die "ERROR: want to use git, but not found in $git_src\n";

		if($branch =~ /^release-/ && $branch !~ /-rc$/) {
			# for public release branches, the version is in the last tag
			my $tag  = (git_last_tag $git_src) || 'no tag';
			$version = $tag =~ m/^v([a-z0-9.\-]+)$/ ? $1 : confess $tag;

		}

		$from_git = 1;

	} elsif($enforce_git) {
		# take the latest code from a branch in git
		my $tag = git_checkout $git_src, $version;
		$version = $tag =~ m/^v([a-z0-9.\-]+)$/ ? $1 : confess $tag;
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

sub taranis_remove(%) {
	my %args = @_;

	my $files   = $args{files} || [];
	! @$files or die "ERROR: no file arguments expected\n";

	my $running_version = $ENV{TARANIS_VERSION} || '';

	my $version = $args{remove};
	$version ge '3.4'
		or die "Versions before 3.4 cannot be removed this way.\n";
		
	my $config  = eval { config_release $version };
	if($@) {
		my $installed  = installed_versions;
		delete $installed->{$running_version};
		keys %$installed
			or die "There are no versions to be deleted.\n";

		my $versions = join '", "', sort_versions(keys %$installed);
		die "Version \"$version\" is not installed.  Pick from \"$versions\".\n";
	}

	$version ne $running_version
		or die "ERROR: You cannot remove the version selected at login.\n";

	my @entries = grep defined && length,
		$config->{logs},
		$config->{tmp},
		$config->{install},
		$config->{install4u},
		taranis_sources($version),
		undef,
		"$config->{filebase}.json";

	print "*   removing $version\n        ", join "\n        ", @entries;

	remove \1, @entries;

	print "    done\n";
	print "    rerunning install for $running_version\n";

	taranis_install version => $running_version;
}

1;
