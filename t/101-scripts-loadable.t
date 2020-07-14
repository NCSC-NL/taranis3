#!/usr/bin/env perl
# check that all mod_perl scripts are loadable

use warnings;
use strict;

use Test::More;
use File::Find qw(find);
use Data::Dumper;

use lib '../pm', 'pm';

sub check_loading() {
	my $mod = $File::Find::name;
	-f $mod or return;
	$mod =~ m!^./scripts/mod_.*/.*\.pl$! or return;

	if(my $child = fork) {
		waitpid $child, 0;
		my $rc = ($? >> 8) & 0xff;
		ok $rc==0, "$mod $rc";
		return;
	}

	my $success = do $mod;
	exit($success ? 0 : 1);   # between processes, rc=0 means 'OK'
}

find { wanted => \&check_loading, no_chdir => 1, follow => 0 }, './scripts';

done_testing;
