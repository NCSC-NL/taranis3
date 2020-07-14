#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

## Taranis.t: tests for Taranis.pm.

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);
use utf8;

use Test::Most;

use Taranis qw(encode_entities_deep decode_entities_deep roundToSignificantDigits);
use Taranis::TestUtil qw(cmp_deeply_or_diff withDistConfig);


withDistConfig {
	# Test &encode_entities_deep.
	{
		cmp_deeply_or_diff
			scalar encode_entities_deep("fo<"),
			"fo&lt;",
			"encode_entities_deep - basic";

		cmp_deeply_or_diff
			scalar encode_entities_deep(" \r\n\t "),
			" \r\n\t ",
			"encode_entities_deep - whitespace";

		cmp_deeply_or_diff
			[ encode_entities_deep("fo<", "ba&r") ],
			[ "fo&lt;", "ba&amp;r" ],
			"encode_entities_deep - list";

		cmp_deeply_or_diff
			[ encode_entities_deep() ],
			[ ],
			"encode_entities_deep - no arguments, list context";

		cmp_deeply_or_diff
			scalar encode_entities_deep(),
			undef,
			"encode_entities_deep - no arguments, scalar context";

		cmp_deeply_or_diff
			[ encode_entities_deep(["baz", {"qu<ux" => ["no<rf"]}]) ],
			[ ["baz", {"qu&lt;ux" => ["no&lt;rf"]}] ],
			"encode_entities_deep - recursion";

		cmp_deeply_or_diff
			[ encode_entities_deep("fo<", "ba&r", ["baz", {"qu<ux" => ["no<rf"]}]) ],
			[ "fo&lt;", "ba&amp;r", ["baz", {"qu&lt;ux" => ["no&lt;rf"]}] ],
			"encode_entities_deep - list + recursion";

		cmp_deeply_or_diff
			scalar encode_entities_deep("kijk슠een huis"),
			'kijk&#xC2A0;een huis',
			"encode_entities_deep - obvious unicode";

		cmp_deeply_or_diff
			scalar encode_entities_deep("répertoire"),
			'r&eacute;pertoire',
			"encode_entities_deep - unicode that could be latin1";
	}


	# Test &decode_entities_deep.
	{
		cmp_deeply_or_diff
			scalar decode_entities_deep("fo&lt;"),
			"fo<",
			"decode_entities_deep - basic";

		cmp_deeply_or_diff
			scalar decode_entities_deep(" \r\n\t "),
			" \r\n\t ",
			"decode_entities_deep - whitespace";

		cmp_deeply_or_diff
			[ decode_entities_deep("fo&lt;", "ba&amp;r") ],
			[ "fo<", "ba&r" ],
			"decode_entities_deep - list";

		cmp_deeply_or_diff
			[ decode_entities_deep() ],
			[ ],
			"decode_entities_deep - no arguments, list context";

		cmp_deeply_or_diff
			scalar decode_entities_deep(),
			undef,
			"decode_entities_deep - no arguments, scalar context";

		cmp_deeply_or_diff
			scalar decode_entities_deep(["baz", {"qu&lt;ux" => ["no&lt;rf"]}]),
			["baz", {"qu<ux" => ["no<rf"]}],
			"decode_entities_deep - recursion";

		cmp_deeply_or_diff
			[ decode_entities_deep("fo&lt;", "ba&amp;r", ["baz", {"qu&lt;ux" => ["no&lt;rf"]}]) ],
			[ "fo<", "ba&r", ["baz", {"qu<ux" => ["no<rf"]}] ],
			"decode_entities_deep - list + recursion";

		cmp_deeply_or_diff
			scalar decode_entities_deep('kijk&#xC2A0;een huis'),
			"kijk슠een huis",
			"decode_entities_deep - obvious unicode";

		cmp_deeply_or_diff
			scalar decode_entities_deep('r&eacute;pertoire'),
			"répertoire",
			"decode_entities_deep - unicode that could be latin1";
	}
};


# Test roundToSignificantDigits.
subtest roundToSignificantDigits => sub {
	my $tests = [
		[12345,   2, 12000],
		[12345,   6, 12345],
		[12345,   0, 0],
		[123.45,  0, 0],
		[123.45,  1, 100],
		[123.45,  4, 123.4],
		[0,       4, 0],
		[-123.45, 4, -123.4],
	];

	for my $test (@$tests) {
		my ($number, $digits, $expected) = @$test;
		is
			roundToSignificantDigits($number, $digits),
			$expected,
			"roundToSignificantDigits($number, $digits) should be $expected";
	}
};


done_testing;
