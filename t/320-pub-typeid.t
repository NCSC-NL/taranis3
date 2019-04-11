#!/usr/bin/env perl
# Check the publication type id discovery.  This is implements quite
# ugly, so we need some checks.

use warnings;
use strict;

use Test::More;

use_ok 'Taranis::Publication';
use_ok 'Taranis::Config';

my $config = Taranis::Config->new;
ok defined $config, 'config';

my $publ   = Taranis::Publication->new;
ok defined $publ, 'publication';

# Test first

my $name1 = $config->publicationTemplateName(advisory => 'email');
is $name1, 'Advisory (email)', 'config name';

my $type_id1 = $publ->getPublicationTypeId($name1);
ok defined $type_id1, "type id = $type_id1";

is $type_id1, $publ->getPublicationTypeId(advisory => 'email');

# Test other

my $name2 = $config->publicationTemplateName(eow => 'email');
is $name2, 'End-of-Week (email)', 'config name';

my $type_id2 = $publ->getPublicationTypeId($name2);
ok defined $type_id2, "type id = $type_id2";

is $type_id2, $publ->getPublicationTypeId(eow => 'email');
cmp_ok $type_id1, '!=', $type_id2;

done_testing();
