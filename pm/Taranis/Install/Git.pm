# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Git;
use base 'Exporter';

use warnings;
use strict;

use Carp       qw(confess);

use Taranis::Install::Config  qw(config_generic sort_versions);

#TODO convert to Git::Repository

our @EXPORT = qw(
	git_checked_out
	git_checkout
	git_last_tag
	git_init_config
	git_releases
);

sub git_checked_out($) {
	my $dir = shift;
	-d $dir or return;

	my $branch = qx(cd '$dir' && git rev-parse --abbrev-ref HEAD 2>/dev/null);
	chomp $branch;
	$branch;
}

sub git_last_tag($) {
	my $dir = shift;
	my $tag = qx(cd '$dir' && git describe --abbrev=0 2>/dev/null);
	chomp $tag;
	$tag;
}

sub git_checkout($$) {
	my ($dir, $need_version) = @_;
	my $has_version = git_checked_out $dir;
	$has_version
		or die "ERROR: git sources not available.\n";

	$has_version ne $need_version
		or return;

	my $git_tag  = 'release-' . $need_version;
	print "*   checking out git branch '$git_tag'.\n";

	system "cd '$dir' && git checkout '$git_tag' 2>/dev/null"
		and die "ERROR: cannot not checkout '$git_tag'.\n";
}

sub git_init_config($) {
	my $dir = shift;
	system "cd '$dir' && git config pull.rebase true"
		and die "ERROR: cannot init git config.\n";
}

# Returns the matching git releases, sorted by version
sub git_releases($;$) {
	my ($dir, $pattern) = @_;
	$pattern ||= qr/./;

	my @all_branches = qx(cd '$dir' && git branch -r 2>/dev/null);
	@all_branches
		or die "ERROR: cannot see any release branches.\n";

	my %releases;
	foreach my $branch (@all_branches) {
		my ($version) = $branch =~ m!^\s*origin/release-(.*)!;
		$releases{$version}++
			if $version && $version =~ $pattern;
	}

	sort_versions keys %releases;
}

1;
