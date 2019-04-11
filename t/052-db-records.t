#!/usr/bin/env perl
# Check transactions

use warnings;
use strict;

use Test::More;
use Taranis::Database ();

require_ok('Taranis::DB');

my $db = Taranis::Database->new->simple;
ok(defined $db, 'connect DB');

my $table = 'test_records';

### Cleanup if last run was not clean
$db->query("DROP TABLE IF EXISTS $table");
$db->query("DROP SEQUENCE IF EXISTS ${table}_id_seq");

### Create table
$db->query(<<__CREATE_SEQ);
CREATE SEQUENCE ${table}_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1
__CREATE_SEQ

$db->query(<<__CREATE_TABLE);
CREATE TABLE $table (
  id INTEGER DEFAULT nextval('${table}_id_seq'::regclass) NOT NULL,
  field1 TEXT,
  field2 TEXT )
__CREATE_TABLE


### addRecord

my $ia = $db->addRecord($table, { field1 => 'f1a', field2 => 'f2a' });
cmp_ok $ia, '==', 1, 'add first record';

my $ib = $db->addRecord($table, { field1 => 'f1b' });
cmp_ok $ib, '==', 2, 'add second record';

my $ic = $db->addRecord($table, { field2 => 'f2c' });
cmp_ok $ic, '==', 3, 'add third record';


### getRecord

my $g1 = $db->getRecord($table, 2);
is_deeply $g1, { id => 2, field1 => 'f1b', field2 => undef }, 'get record 2';

my $g2 = $db->getRecord($table, 3);
is_deeply $g2, { id => 3, field1 => undef, field2 => 'f2c' }, 'get record 3';

my $g3 = $db->getRecord($table, 'f2c', 'field2');
cmp_ok $g3->{id}, '==', 3, 'other field selector';


### setRecord

$db->setRecord($table => 2, { field2 => 'f2b' });
my $s1 = $db->getRecord($table, 2);
is_deeply $s1, { id => 2, field1 => 'f1b', field2 => 'f2b' }, 'set record 2';

$db->setRecord($table => 2, { field1 => 'tic', field2 => 'tac' });
my $s2 = $db->getRecord($table, 2);
is_deeply $s2, { id => 2, field1 => 'tic', field2 => 'tac' }, 'set record 2';

$db->setRecord($table => 'f1a', { field2 => 'toe' }, 'field1');
my $s3 = $db->getRecord($table, 'toe', 'field2');
cmp_ok $s3->{id}, '==', 1, 'other field';


### setOrAddRecord

my $t1 = $db->setOrAddRecord($table => { field1 => 'f3a', field2 => 'f3b' }, 'field1');
is $t1, 4, 'set or add: do add';

my $t2 = $db->setOrAddRecord($table => { field1 => 'f3a', field2 => 'f3c' }, 'field1');
is $t1, $t2, 'set or add: do set';

my $t3 = $db->getRecord($table, $t1);
is_deeply $t3, { id => 4, field1 => 'f3a', field2 => 'f3c' }, 'is updated';


### deleteRecord

ok  defined $db->getRecord($table, 1), 'delete by id';
$db->deleteRecord($table, 1);
ok !defined $db->getRecord($table, 1);

ok  defined $db->getRecord($table, 2), 'delete by field';
$db->deleteRecord($table, 'tac', 'field2');
ok !defined $db->getRecord($table, 2);


### isTrue

ok  $db->isTrue("SELECT 1 FROM $table WHERE id = 3"), 'is true';
ok !$db->isTrue("SELECT 1 FROM $table WHERE id = 1000"), 'is false';

### Cleanup

$db->query("DROP TABLE IF EXISTS $table");
$db->query("DROP SEQUENCE IF EXISTS ${table}_id_seq");

done_testing;
