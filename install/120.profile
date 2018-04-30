#!/usr/bin/env perl
# Create the fixed profile component, plus a link to that in the
# user's login profile.

use warnings;
use strict;

use File::Basename           qw(basename);
use Config                   qw(%Config);

use Taranis::Install::Perl   qw(perl5lib perl5man);
use Taranis::Install::Config qw(config_generic installed_versions
	config_release sorted_available_versions become_user_taranis
	appconfig_path);
use Taranis::Install::Git    qw(git_checked_out);

become_user_taranis;

my $generic         = config_generic;
my $taranis_profile = "$generic->{lib}/bash_profile";
my $home            = $generic->{home};
my $user_profile    = "$home/.bash_profile";

# See whether we use git.  The branch label should not be hard-coded!
my $git_src         = "$home/sources/taranis-git";
my $has_git         = git_checked_out $git_src;

my $with_git        = $has_git ? ' (with git)' : '';
print "*   creating login version switch$with_git in $taranis_profile\n";

my $default_version = $generic->{default_version};
my @versions        = sorted_available_versions $default_version;
my $latest_version  = $versions[-1][0];   # latest installed, not git

my @menu;
foreach my $v (@versions) {
	my ($version, $loc, $is_sel) = @$v;
	$loc ||= 'not (yet) installed';
	$loc  .= ' (branch "$GIT_CHECKOUT")' if $version eq 'git';
	push @menu, sprintf "  %1s %-15s %s", ($is_sel ? '*' : ' '), $version, $loc;
}

my @options;
my $newest_man;

foreach (@versions) {
	my ($version, $dist, $is_default) = @$_;
	next if $version eq 'git';

	my $release = config_release $version;

	$dist     ||= "$home/taranis-$version";

	my $perllib = join ':', perl5lib $version;
	my @bin     = grep -d,
		"$home/bin",
		"$home/local-$version/bin",
		"$home/local/bin",
		"$home/taranis-$version/bin";

	# In some environments, login automatically adds ~/man.  We may add
	# that directory again.
	my $man     = join ':', perl5man $version;

	# The git sources do not contain formatted manual-pages, so we provide
	# the manuals of the newest installed release.
	$newest_man = $man;

	unless(-f "$home/taranis-$version/bin/taranis") {
		# not installed yet, may help to add already some things
		my $libdir = "$home/sources/taranis-$version";
		$perllib   = "$perllib:$libdir/pm";
		push @bin, "$libdir/bin";
	}

	my $config_path = join ':', appconfig_path($version);
	my $tmpdir      = $release->{tmp} || $ENV{TMPDIR} || '/tmp';

	my $bin = join ':', @bin;

	push @options, <<_OPTION;
"$version")
	DIST="$dist"
	ADDPERL="$perllib"
	ADDBIN="$bin"
	ADDMAN="$man"
	PHANTOMJS_LIB="\$DIST/PhantomJS"
	APPCONFIG_PATH="$config_path"
	TMPDIR="$tmpdir"
	CLUSTERING="$release->{clustering}"
	;;
_OPTION
}

### GIT SUPPORT

if($with_git) {
	my $config_path    = join ':', appconfig_path('git');

	# Run mostly un-installed/
	my $bin = join ':',
		"$home/bin",
		"$home/local-git/bin",
		"$home/local/bin",
	    '$DIST/bin',
		'$DIST/devel',
		"$home/taranis-git/bin";

	push @options, <<__OPTION_GIT;
git)
	DIST="$git_src"
	ADDPERL="\$DIST/pm:$home/ChartDirector/lib:$home/lib/perl5:$home/lib/perl5/$Config{archname}"
	ADDBIN="$bin"
	ADDMAN="$newest_man"
	PHANTOMJS_LIB="\$DIST/phantomjs"
	APPCONFIG_PATH="$config_path"
	TMPDIR="$generic->{tmp}/$generic->{username}-git"
	CLUSTERING="\$DIST/pm/Taranis/Clustering"
	;;
__OPTION_GIT
}

my $menu    = join "\n", @menu;
my $options = join "\n", @options;
my $genlib  = $generic->{perl_lib};

open my $profile, '>:encoding(utf8)', $taranis_profile
	or die "ERROR: cannot write $taranis_profile: $!\n";

my $script = basename __FILE__;
my $match_versions = join " | ", map "'$_->[0]'", @versions;

$profile->print(<<_PROFILE);
#!/bin/bash
# This file is generated with $script during install.

# You may modify your own ~/.bash_profile  Other changes may need to go
# to etc/startup-*  and rerun install.

umask 022

DEFAULT_VERSION="$generic->{default_version}"
GIT_CHECKOUT=\$(cd "$git_src" 2>/dev/null && git rev-parse --abbrev-ref HEAD);

if [ "\$TARANIS_VERSION" = latest ]
then TARANIS_VERSION='$latest_version'
fi

while [ -z "\$TARANIS_VERSION" ]
do
	echo "
Which version of Taranis do you want to use?
$menu";

	read -p "pick a version from above: [\$DEFAULT_VERSION]: " TARANIS_VERSION
	[ -z "\$TARANIS_VERSION" ] && TARANIS_VERSION="\$DEFAULT_VERSION";

	case "\$TARANIS_VERSION" in
	$match_versions )
		;;
	*)  echo "ERROR: version not installed, try again." >&2
		TARANIS_VERSION=
		;;
	esac
done

case "\$TARANIS_VERSION" in
$options
esac

export TARANIS_VERSION PHANTOMJS_LIB APPCONFIG_PATH TMPDIR CLUSTERING

if [ -z "\$PERL5LIB" ]     # keep "." from path!
then PERL5LIB="\$ADDPERL"
else PERL5LIB="\$ADDPERL:\$PERL5LIB"
fi
export PERL5LIB

export MANPATH="\$ADDMAN:\$MANPATH"
export PATH="\$ADDBIN:\$PATH"
export PHANTOMJS="$generic->{phantomjs}/bin/phantomjs"
export SOURCE_ICONS="$generic->{source_icons}"
export STATS_IMAGES="$generic->{custom_stats}"

# Be able to run 'cpan -i' as user taranis to install or fix modules
export PERL_MM_OPT='INSTALL_BASE="$home"';    # Makefile.PL based dists
export PERL_MB_OPT='--install_base "$home"';  # BUILD.PL based dists

if which prompt 2>/dev/null >/dev/null
then PS1="\\\$(prompt '\$DIST')"
fi

_PROFILE

if(my $scls = $ENV{X_SCLS}) {
	if(my $postgres = (grep /postgres/, split ' ', $scls)[0]) {
		$profile->print("source scl_source enable $postgres\n");
	}
}

$profile->close
	or die "ERROR while writing $taranis_profile\n";

my $include_profile = "source $taranis_profile\n";
if( ! -f $user_profile ) {
	print "*   created new $user_profile\n";
	open my $up, ">:encoding(utf8)", $user_profile
		or die "ERROR: cannot create $user_profile: $!\n";

	$up->print(<<_HEADER);
# You may add lines to this file.  Taranis installation will only
# modify $include_profile
echo "=="
echo "== Welcome to TARANIS maintenance"
echo "=="
$include_profile
_HEADER
	$up->close;
} else {
	open my $up, "<:encoding(utf8)", $user_profile
		or die "ERROR: cannot read $user_profile: $!\n";
	my $found = grep $_ eq $include_profile, $up->getlines;
	$up->close;

	if($found) {
		print "*   taranis profile already in $user_profile\n";
	} else {
		print "*   taranis profile added to $user_profile\n";
		open my $up, ">>:encoding(utf8)", $user_profile
			or die "ERROR: cannot read $user_profile: $!\n";
		$up->print($include_profile);
		$up->close;
	}
}

exit 0;
