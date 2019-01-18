# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

# Starting and stopping the application from the command-line
# Same logic in install/330.apache-links

package Taranis::Command::Control;

use warnings;
use strict;

use Carp;

use Taranis::Command::Apache  qw(apache_control);
use Taranis::Install::Config  qw(config_generic);
use Taranis::Install::Bare    qw(is_redhat is_centos);

use Taranis::Log   ();
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Database);

sub _restart_apache();
sub _enable_vhosts();
sub _disable_vhosts();
sub _enable_cron();
sub _disable_cron();
sub _kill_cron_processes();

my $generic;

Taranis::Commands->plugin(start => {
	handler       => \&start_taranis,
	requires_root => 1,
	getopt        => [ ],
	help          => '',
} );

Taranis::Commands->plugin(stop => {
	handler       => \&stop_taranis,
	requires_root => 1,
	getopt        => [ ],
	help          => '',
} );

Taranis::Commands->plugin(restart => {
	handler       => \&restart_taranis,
	requires_root => 1,
	getopt        => [ ],
	help          => '',
} );


sub start_taranis(%) {
	my %args   = @_;

	my $subcmd = $args{sub_command}
		and confess;

	_enable_vhosts;
	_restart_apache;

	_enable_cron;
}

sub stop_taranis(%) {
	my %args   = @_;

	my $subcmd = $args{sub_command}
		and confess;

	_disable_vhosts;
	_restart_apache;

	_disable_cron;
	_kill_cron_processes;
}

sub restart_taranis(%) {
	my %args   = @_;

	my $subcmd = $args{sub_command}
		and confess;

	_kill_cron_processes;
	_restart_apache;
}

### HELPERS

# When taranis is stopped, its vhost is removed from the apache
# configuration.  Other websites may continue to run.
sub _restart_apache() { apache_control sub_command => 'restart' }

sub _get_vhost_configs() {
	my ($apache) = grep -d,
    	'/etc/apache2/vhosts.d',
    	'/etc/apache2/sites-enabled',
    	'/etc/httpd/vhosts.d',
    	'/etc/httpd/conf.d',
    	'/etc/httpd/conf';

	$apache or die "ERROR: cannot find apache2 vhosts.d\n";

	$generic    ||= config_generic;
	my $lib       = $generic->{lib};       # vhost config is shared
	my $username  = $generic->{username};

	my $base       = $username eq 'taranis' ? '' : 'taranis.';

	( "$apache/$base${username}.conf"    => "$lib/apache_vhosts.conf",
	  "$apache/$base${username}_4u.conf" => "$lib/apache_vhosts4u.conf",
	);
}

sub _enable_vhosts() {
	print "* enable apache vhosts\n";

	my %symlinks = _get_vhost_configs;

	while(my ($from, $to) = each %symlinks) {
		next if -l $from;

		-e $from
			and die "ERROR: $from has been changed manually.\n";

		symlink $to, $from
	        or die "ERROR: cannot install apache vhost $to: $!\n";
	}
}

sub _disable_vhosts() {
	print "* disable apache vhosts\n";

	my %symlinks = _get_vhost_configs;

	while(my ($from, $to) = each %symlinks) {
		-e $from or next;

		-l $from
			or die "ERROR: $from has been changed manually.\n";

		unlink $from
	        or die "ERROR: cannot remove apache vhost $from: $!\n";
	}
}

sub _update_cron(&) {
	my $modify    = shift;

	$generic    ||= config_generic;
	my $username  = $generic->{username};

	my @crontab   = qx(crontab -u $username -l);

	# skip system warning about "do not edit by hand"
	shift @crontab while @crontab && $crontab[0] =~ /^# /;

	$modify->(\@crontab);
	open my $cron, "| crontab -u $username -" or die $!;
	$cron->print(@crontab);
	$cron->close;
}

sub _enable_cron() {
	print "* enabling cron\n";

	_update_cron sub {
		my $lines = shift;
		s/^\#STOP\: ?// for @$lines;
	};
}

sub _disable_cron() {
	print "* disable cron\n";

	_update_cron sub {
		my $lines = shift;

		/\*/ && s/^([^#])/#STOP: $1/ for @$lines;
	};
}

sub _kill_cron_processes() {
	print "* stopping processes started by cron\n";

	$generic      ||= config_generic;
	my $username    = $generic->{username};

	my $service     = is_redhat || is_centos ? 'crond' : 'cron';
	my $cron_status = qx(systemctl status $service);
	my $cron_daemon = $cron_status =~ m! PID: ([0-9]+) ! ? $1 : undef;

	unless($cron_daemon) {
		warn "cannot detect cron daemon\n";
		return;
	}

	my @cron_scripts = qx(pgrep --parent $cron_daemon);
	my @running;

	foreach my $script_id (@cron_scripts) {
		chomp $script_id;
		push @running, qx(pgrep --parent $script_id --uid $username);
	}
	chomp for @running;

	@running or return;

	print "The following processes will be stopped:\n";
	my $running = join ',', @running;
	print qx(ps -f --pid $running);

	kill TERM => @running;
}

1;
