#!/usr/bin/env perl
# Check transactions

use warnings;
use strict;

use Test::More;

use Taranis::Database;

require_ok('Taranis::DB');

my $db = Taranis::Database->new->simple;

ok(defined $db, 'connect DB');
isa_ok($db, 'Taranis::DB');

### Straight formard

{
	my $guard1 = $db->beginWork;
	my $start_line = __LINE__ -1;

	ok defined $guard1, 'first transaction';
	isa_ok $guard1, 'Taranis::DB::Guard';

	my $get1   = $db->activeGuard;
	ok defined $get1;
	isa_ok $get1, 'Taranis::DB::Guard';
	is $guard1, $get1;
	undef $get1;

	is $guard1->location,  __FILE__ . ' line '.$start_line;;

	# do something
	$db->commit($guard1);

	ok ! defined $guard1;
	ok ! defined $db->activeGuard;
}

### Nested

{	my $guard2 = $db->beginWork;

	my $nested = $db->beginWork;
	is $nested, 'nested', 'created nested';

	$db->commit($nested);
	ok ! defined $nested;
	ok defined $guard2;

	$db->commit($guard2);
	ok !defined $guard2;
}

done_testing;
