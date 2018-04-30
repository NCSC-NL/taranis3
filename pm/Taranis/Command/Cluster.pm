# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Cluster;

use warnings;
use strict;

use Carp           qw(confess);

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::Lock ();
use Taranis::Clustering ();

my %handlers = (
	'news-items' => \&cluster_news_items,
);

Taranis::Commands->plugin(cluster => {
	handler       => \&cluster_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'reset|r!',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  news-items [-r]         (re)compute clustering on new items

OPTIONS:
  -r --reset              restart with all items
__HELP
} );

sub cluster_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub cluster_news_items($) {
	my $args   = shift;

	$::db      = Database->{simple};   # T4
	my $lock   = Taranis::Lock->lockProcess('clustering');

	my $reset  = $args->{reset};
    Taranis::Clustering->new->recluster(cleanup_old_scores => $reset);
}

1;
