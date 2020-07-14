# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Util;
use base 'Exporter';

use warnings;
use strict;

use Carp       qw(confess);
use JSON       ();
use IO::Handle ();     # needed by older perls

our @EXPORT = qw(
	read_json write_json
);

# The read_json and write_json may be needed elsewhere, but cannot be
# located in ::Bare, which lacks installed modules.
my $json = JSON->new->utf8(0)->canonical(1)->pretty(1);

sub read_json($) {
	my $fn = shift;
	open my $fh, '<:encoding(utf8)', $fn
		or die "ERROR: cannot read from $fn for JSON: $!\n";

	my $data = eval { $json->decode(join '', $fh->getlines) };
	die "ERROR while parsing JSON from $fn:\n  $@" if $@;

	$data;
}

sub write_json($$) {
	my ($fn, $data) = @_;
	open my $fh, '>:encoding(utf8)', $fn
		or die "ERROR: cannot write JSON to $fn: $!\n";

	$fh->print($json->encode($data));
	$fh->close
		or die "ERROR while writing JSON to $fn: $!\n";
}

1;
