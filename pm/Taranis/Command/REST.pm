# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::REST;

use warnings;
use strict;

use Carp   qw(confess);
use XML::XPath;
use XML::XPath::XMLParser;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);

my %handlers = (
	'cleanup-tokens' => \&rest_cleanup_tokens
);

Taranis::Commands->plugin(rest => {
	handler       => \&rest_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  cleanup-tokens       remove expired access tokens
__HELP
} );

sub rest_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

# was backend_tools/access_tokens_cleanup.pl
sub rest_cleanup_tokens($) {
	my $args   = shift;
	my $db = Database->{simple};

	$db->query( <<'__CLEANUP_TOKENS' );
DELETE FROM access_token
 WHERE expiry_time IS NOT NULL
   AND last_access < NOW() - (expiry_time::text ||' minutes')::INTERVAL
__CLEANUP_TOKENS

	$db->disconnect;
}
