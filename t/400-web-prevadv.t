#!/usr/bin/env perl
# Check the calculation of the previous advisory id

use warnings;
use strict;

use Test::More;
use Data::Dumper;

use_ok 'Taranis::Publish';
use_ok 'Taranis::Database';

my $db = Taranis::Database->new->simple;
isa_ok $db, 'Taranis::DB';

my $pub = Taranis::Publish->new;
isa_ok $pub, 'Taranis::Publish';

my $guard = $db->beginWork;

my $first_id = $db->addRecord(publication_advisory => {
	govcertid => 'TEST-2019-0001',
	version   => '1.00',
});

ok defined $first_id, "created advisory TEST-2019-0001 id=$first_id";

#### Check simple case: the previous is in this year

my $prev = $pub->_previousAdvisoryId('TEST-2019-0002', undef, $db);
is $prev, 'TEST-2019-0001', 'Simple follow-up';

#### Check last of previous year
$db->addRecord(publication_advisory => { govcertid => 'TEST-2019-4321' });
$db->addRecord(publication_advisory => { govcertid => 'TEST-2019-XXXX' });

my $prev2 = $pub->_previousAdvisoryId('TEST-2020-0001', undef, $db);
is $prev2, 'TEST-2019-4321', 'Last of previous year';

### Check last year, tricky case: the ids became longer
$db->addRecord(publication_advisory => { govcertid => 'TEST-2019-10234' });

my $prev3 = $pub->_previousAdvisoryId('TEST-2020-0001', undef, $db);
is $prev3, 'TEST-2019-10234', 'Last of previous year';

### Check retreival of the advisory
$db->addRecord(publication_advisory =>
  { govcertid => 'TEST-2019-0001', version => '1.01' });

my $adv = $pub->getPriorPublication('TEST-2019-0002', undef, $db);
ok defined $adv, 'Found prior advisory';
is $adv->{govcertid}, 'TEST-2019-0001', 'correct certid';
is $adv->{version}, '1.01', 'latest version';

$db->rollback($guard);

done_testing;
