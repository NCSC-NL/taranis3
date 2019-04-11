#!/usr/bin/env perl
# Check creation of fragments of the database query

use warnings;
use strict;

use Test::More;

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Quotekeys = 0;

use_ok 'Taranis::MetaSearch';

my $db_query;
my $ms = Taranis::MetaSearch->new(
	is_identifier => qr/^CVE-\d+-\d+/,
	db => { },
);
isa_ok $ms, 'Taranis::MetaSearch';

### _isIdentifier

ok $ms->_isIdentifier('CVE-123-111'), 'is certid 1';
ok $ms->_isIdentifier('CVE-1-1'), 'is certid 2';
ok ! $ms->_isIdentifier('CVE-1345'), 'no second part';
ok ! $ms->_isIdentifier(' CVE-42-42'), 'leading blank';

### _addSearchDate

my (@where, @binds);
$ms->_addSearchDate(\@where, \@binds, { }, it => 'created');
cmp_ok scalar @where, '==', 0, 'no dates added';
cmp_ok scalar @binds, '==', 0;

(@where, @binds) = ();
$ms->_addSearchDate(\@where, \@binds, { start_time => 42 }, it => 'created');
cmp_ok scalar @where, '==', 1, 'only start date';
is $where[0], "it.created >= '42'";
cmp_ok scalar @binds, '==', 0;

(@where, @binds) = ();
$ms->_addSearchDate(\@where, \@binds, { end_time => 43 }, it => 'created');
cmp_ok scalar @where, '==', 1, 'only end date';
is $where[0], "it.created <= '43'";
cmp_ok scalar @binds, '==', 0;

(@where, @binds) = ();
$ms->_addSearchDate(\@where, \@binds, { start_time => 44, end_time => 45 }, it => 'created');
cmp_ok scalar @where, '==', 1, 'start and end date';
is $where[0], "it.created BETWEEN '44' AND '45'";
cmp_ok scalar @binds, '==', 0;

### _addSearchFilters

(@where, @binds) = ();
$ms->_addSearchFilters(\@where, \@binds, it => {
	searchArchive => 1,   # to be ignored
	numeric => 46,
	alphabetic => '12a',
});
cmp_ok scalar @where, '==', 2, 'generic search filters';
@where = sort @where;
is $where[0], 'it.alphabetic ILIKE ?', '... where';
is $where[1], 'it.numeric = 46';

cmp_ok scalar @binds, '==', 1, '... binds';
is $binds[0], '12a';

done_testing;
