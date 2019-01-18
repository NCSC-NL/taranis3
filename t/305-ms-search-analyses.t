#!/usr/bin/env perl
# Check the creation of complex queries in assess items.

use warnings;
use strict;

use Test::More;

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Quotekeys = 0;

use_ok 'Taranis::MetaSearch';

my $db_query;

sub cmp_select($$$) {
	my ($has, $want, $label) = @_;

	s/\s+/ /gs,s/^ //,s/ $// for $has, $want;
	is $has, $want, $label;
}

my $ms = Taranis::MetaSearch->new(
	is_identifier => qr/^CVE-\d+-\d+/,
	db => (bless {}, 'catch_query'),
);
isa_ok $ms, 'Taranis::MetaSearch';

# construct a question (identical to the string in 'item')
my $question = $ms->_evaluateQuestion("  CVE-1-1 word  tag:label ");

my %search = (
	question   => $question,
	start_time => '20171211 100908',
	analysis   => {
		rating   => 3,         # just a random numeric field
		owned_by => 'markov',  # just a random text field
	}
);

# db call caught
my $answers = $ms->_searchAnalyses(\%search);
#warn Dumper $catch_query::query;
cmp_select $catch_query::query, <<'__QUERY', 'constructed query';
 SELECT ana.id, ana.title, ana.comments AS description, ana.idstring,
        TO_CHAR(ana.orgdatetime, 'DD-MM-YYYY HH24:MI:SS:MS') AS date
   FROM analysis AS ana
  WHERE ana.orgdateTime >= '20171211 100908'
    AND (ana.id IN (
 SELECT id
   FROM analysis
  WHERE title ILIKE ? OR comments ILIKE ?
        ) OR ana.id IN (
 SELECT ti.item_id
   FROM tag
        JOIN tag_item AS ti  ON ti.tag_id = tag.id
  WHERE ti.item_table_name = 'analysis'
    AND tag.name ILIKE ?
        ) OR
        (ana.idstring ILIKE ? OR ana.idstring ILIKE ?))
__QUERY

#warn Dumper $catch_query::binds;
is_deeply $catch_query::binds, [
	'%word%',
	'%word%',
	'label',
	'%CVE-1-1 %',
	'%CVE-1-1',
], 'constructed binds';

my $db = eval '
	require Taranis::Database;
    Taranis::Database->new->simple;
';

if($@ || !$db) {
	ok 1, 'no connection to the database';
	#warn $@;

	done_testing;
	exit 0;
}

# Run explain to compile the query on the real schema.

#warn "$_\n" for
$db->query("EXPLAIN $catch_query::query", @$catch_query::binds)->flat;

done_testing;

####
package catch_query;
our ($query, $binds);
sub query($@) {
	my $self = shift;
	$query   = shift;
	$binds   = \@_;
	undef;      # blocks scoring in the main code
}
