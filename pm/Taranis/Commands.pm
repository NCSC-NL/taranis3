# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Commands;
use base 'Exporter';

use warnings;
use strict;

use Taranis qw(scan_for_plugins);

=head1 NAME

Taranis::Commands - administer plugins for sub-commands of taranis

=head1 SYNOPSIS

  my $p = commands_load_plugins;
  my $config = commands_find_plugin $name;
  commands_plugin_use;

=head1 DESCRIPTION

The C<taranis> command line instruction follows the same strategy as
popular frameworks like C<git>: a main command with many sub-commands.

You may add your own sub-commands in the C<~/local*> directories.  They
will automatically be picked-up.

=head1 FUNCTIONS

=over 4

=cut

our @EXPORT = qw(
	commands_load_plugins
	commands_find_plugin
	commands_plugin_use
);

#XXX You can only use system modules here, because "taranis install"
#    starts without any own modules installed.  Add system packages
#    to install/01* for each of the mentioned.
# Currently nothing is needed by this core module

my %plugins;

# called via Taranis::Commands->plugin(...) to avoid cyclic dependeny
sub plugin($$) {
	my ($pkg, $name, $config) = @_;
	$plugins{$name} = $config;
}


=item commands_load_plugins

Load all modules in the Taranis::Command namespace.

=cut

sub commands_load_plugins() {
	scan_for_plugins 'Command', load => 1;
}


=item my $config = commands_find_plugin $name

Get the configuration for the named plugin.  That's just a complex HASH.

=cut

sub commands_find_plugin($) {
	my $name = shift;
	$plugins{$name};
}


=item commands_plugin_use;

Print a global usage of all plugins to the selected filehandle.

=cut

sub commands_plugin_use() {
	map sprintf("%-12s %s", $_, join('|',@{$plugins{$_}{sub_commands} || []})),
		sort keys %plugins;
}

=back

=cut

1;
