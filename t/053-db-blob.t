#!/usr/bin/env perl
# Check transactions

use warnings;
use strict;
use utf8;

use Test::More;
use Encode   qw(encode);
use Taranis::Database;

require_ok('Taranis::DB');

my $db = Taranis::Database->new->simple;
ok(defined $db, 'connect DB');

my $blob = encode utf8 => 'abcdëfgh€';
cmp_ok length($blob), '>', 8, 'raw longer than as utf8';


### addBlob

my ($oid1, $size1) = $db->addBlob($blob);
ok defined $oid1, "saved object $oid1";
cmp_ok $size1, '==', length($blob), "size $size1";


### getBlob

my $got = $db->getBlob($oid1, $size1);
ok defined $got, 'get blob';
cmp_ok length($got), '==', length($blob);
is $got, $blob;

### removeBlob

$db->removeBlob($oid1);
ok 1, 'removed blob';

done_testing;
