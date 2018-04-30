# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use warnings;
use strict;

package Taranis::Lock;

use Fcntl     qw(:flock);

use Taranis::Install::Config qw(config_release);

# We need a separate lock file and pid file to avoid race condiftions
# and locks which stay when the process ends.  The pid file is informational
# only.

sub lockProcess($) {
	my ($class, $name) = @_;

	my $config = config_release;
	my $run    = $config->{run};

	my $pidfn  = "$run/$name.pid";
	my $lockfn = "$run/$name.lock";

	open my $lock, '>>', $lockfn
		or die "ERROR: cannot create lockfile $lockfn: $!\n";

	unless(flock $lock, LOCK_EX|LOCK_NB) {
		my $rc  = $!;
		my $pid = 'unknown process';
		if(open my $pidfh, '<', $pidfn) {
			$pid = $pidfh->getline || '(empty pidfile)';
			chomp $pid;
		}
		die "ERROR: $name locked by process $pid: $rc\n";
	}

	open my $pidfh, '>', $pidfn
		or die "ERROR: cannot write pid to $pidfn: $!\n";

	$pidfh->print("$$\n");
	$pidfh->close;

	my $self = bless {
		name   => $name,
		pidfn  => $pidfn,
		lockfn => $lockfn,
		lock   => $lock,
	}, $class;

	$self;
}

sub unlock() {
	my $self = shift;
	unlink $self->{pidfn};

	my $lock = delete $self->{lock} or return;
	flock $lock, LOCK_UN;
}

sub processIsRunning($) {
	my ($class, $name) = @_;
	if(my $lock = eval { $class->lockProcess($name) }) {
		$lock->unlock;
		return 0;
	}

	my $config = config_release;
	my $pidfn  = "$config->{run}/$name.pid";

	open my $pidfh, '<', $pidfn
		or return undef;

	my $pid = $pidfh->getline;
	$pidfh->close;

	chomp $pid;
	$pid;
}

sub DESTROY() {
	shift->unlock;
}

1;
