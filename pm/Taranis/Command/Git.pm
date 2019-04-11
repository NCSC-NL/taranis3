# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Git;

use warnings;
use strict;

use Carp        qw(confess);

use Taranis::Install::Config qw(config_generic);
use Taranis::Install::Git    qw(git_checked_out git_checkout git_archive
	git_releases git_init_config git_last_tag git_taranis_version);

sub _git_init($);

my $repo_private = 'git@github.com:NCSC-NL/taranis.git';
my $repo_public  = 'git@github.com:NCSC-NL/taranis3.git';

Taranis::Commands->plugin(git => {
	handler       => \&git_control,
	sub_commands  => [ qw/init release/ ],
	getopt        => [
		'dest|d=s',
		'private|p!',
		'repo|r=s',
		'version|v=s',
		'version-base|b=s'
	],
	help          => <<'__HELP',
SUBCOMMANDS:
  init    [-bdprv]
  release [-v]

OPTIONS:
  -b --version-base STR  use newest compatible release, f.i  '3.3'
  -d --dest DIRECTORY    where to start archive (default ~/source/taranis-git)
  -r --repo URL          where the git repository is
  -v --version STRING    overrule the tag found in git
  -p --private           use the private archive (branch develop)
__HELP
} );

my %handlers = (
	init    => \&_git_init,
	release => \&_git_release,
);

sub git_control() {
	my %args = @_;

	@{$args{files}}==0
		or die "ERROR: no filenames expected.\n";

	my $subcmd = $args{sub_command} or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub _git_init($) {
	my $args = shift;
	my $repo     = $args->{repo};
	my $version  = $args->{version};
	my $versbase = $args->{'version-base'};

	print "*** start-up developing Taranis code via github.\n";

	my $generic  = config_generic $::setup_generic;
	my $dest     = $args->{dest} || "$generic->{home}/sources/taranis-git";

	if(-d "$dest/.git") {
		print "*   git already cloned into $dest\n";
	} elsif($args->{private}) {
		$repo ||= $repo_private;
		print "*   cloning private git into $dest\n";
		system git => clone =>
			'--branch' => 'develop',
			'--', $repo, $dest
			and die "ERROR: could not git-clone into $dest: $!\n";
	} else {
		$repo ||= $repo_public;
		print "*   cloning public git into $dest\n";
		system git => clone =>
			'--', $repo, $dest
			and die "ERROR: could not git-clone into $dest: $!\n";
	}

	git_init_config $dest;

	if($version) {
		print "*   checkout release $version\n";
		git_checkout $dest, $version;
	} elsif($versbase) {
		my @releases = git_releases $dest, qr/^\Q$versbase/;
		@releases
			or die "ERROR: not releases in set '$versbase'.\n";

		$version = $releases[-1];
		print "*   checkout release $version, latest in $versbase.\n";
		git_checkout $dest, $version;
	} else {
		# No specific version checked-out.
		#XXX  Maybe we should take a # version from the default_version
		#     can easily jump from a tarball installed into the git update.
		return;
	}

	#XXX call install automatically once?
	print "\n";
	print "*** For the sources go to $dest\n";
	print "*** and then run 'bin/taranis install'\n";
	print "*** run 'taranis restart' after each change in *.pm\n";
}

sub _git_release($) {
	my $args = shift;

	my $generic    = config_generic $::setup_generic;
	my $git_src    = "$generic->{home}/sources/taranis-git";
	my $version_fn = "$git_src/pm/Taranis/Version.pm";

	my ($version, $tag);
	if($version    = $args->{version}) {
		$tag       = git_last_tag $git_src;
	} else {
		my $branch = git_checked_out $git_src;
		$branch =~ m/^release-/
			or die "ERROR: specify version or switch to release branch\n";

		$tag       = git_last_tag $git_src;
		$tag =~ /^(?:release-|v)(.*)/i
			or die "ERROR: last tag '$tag' is does not contain a version\n";

		$version = $1;
	}

	my $tarball = "/tmp/taranis-$version.tar.gz";
	git_archive $git_src, $tag, $tarball;

	print "Produced release in $tarball\n";
}

1;
