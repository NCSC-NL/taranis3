# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Tools;

use warnings;
use strict;

use Carp          qw(confess);
use Capture::Tiny qw(capture_merged);

use Taranis       qw(find_config);
use Taranis::FunctionalWrapper qw(Database);

my %handlers = (
	'run-backends' => \&tools_run_backends
);

Taranis::Commands->plugin(tools => {
	handler       => \&tools_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l=s'
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  run-backends         run the external scripts configured inside the website

OPTIONS:
  -l -log FILENAME     alternative destination for log (maybe '-' or /dev/null)
__HELP
} );

sub tools_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub tools_run_backends($) {
	my $args   = shift;

	@{$args->{files} || []} == 0
		or die "ERROR: no filenames expected.\n";

	my $logger    = Taranis::Log->new('run-external-tools', $args->{log});

	my $main_conf = Taranis::Config->new;
	my $tools_fn  = find_config $main_conf->{toolsconfig}
		or die "ERROR: cannot find tools config '$main_conf->{toolsconfig}'\n";

	my $tools     = Taranis::Config->new($tools_fn);
	foreach my $tool (@$tools) {
		my $command_line = $tool->{backend}
			or next;

		my $name = $tool->{toolname};

		$logger->info("Running external tool '$name'\n");
		my ($output, $rc) = capture_merged {
			system $command_line;
			$?;
		 };

		$logger->print($output);

		#XXX needs to decode $?
 		$logger->info("Tool '$name' returned $?");
	}

	$logger->close;
}

1;
