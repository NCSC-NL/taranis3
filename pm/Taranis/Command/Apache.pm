# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Apache;
use base 'Exporter';

use warnings;
use strict;

our @EXPORT_OK = qw(apache_control);

use Carp        qw(confess);

Taranis::Commands->plugin(apache => {
    handler       => \&apache_control,
    requires_root => 1,
	sub_commands  => [ qw/start stop restart/ ],
    getopt        => [ ],
    help          => <<'__HELP',
SUBCOMMANDS:
  start           start the server, if not yet running
  restart         restart the server if not yet running, restart otherwise
  stop            stop the apache server
__HELP
} );

sub apache_control(%) {
	my %args = @_;

	@{$args{files} || []}==0
		or die "ERROR: no filenames expected.\n";

	my $subcmd = $args{sub_command} or confess;

	system 'apachectl', $subcmd
		and die "ERROR: apache2ctl $subcmd failed with: $!\n";
}

1;
