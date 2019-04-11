#!/usr/bin/env perl

use warnings;
use strict;

use Taranis::Database;
use Test::More;

use lib 'pm';

require_ok('Taranis::DB');

my $old = Taranis::Database->new;

my $db = $old->simple;

ok(defined $db, 'connect DB');
isa_ok($db, 'Taranis::DB');

my $db_version = $db->query(<<'__VERSION')->list;
SELECT value FROM taranis WHERE key = 'schema_version'
__VERSION

cmp_ok($db_version, '>', 3400, "DB version $db_version");

done_testing;
