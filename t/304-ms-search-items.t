#!/usr/bin/env perl
# Check the creation of the complex query to scan items

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

# construct a question (check is, to be sure the premissis are correct)
my $question = $ms->_evaluateQuestion("  CVE-1-1 word  tag:label ");
is_deeply $question, {
	bonus_certids => [ 'CVE-1-1' ],
	bonus_words   => [ 'CVE-1-1', 'word' ],
	bonus_tags    => [ 'label' ],
	has_certids   => 1,
	has_words     => 2,
	has_tags      => 1,
	has_bonus     => 3,
	search_string => 'CVE-1-1 word tag:label'
}, 'create question';

my %search = (
	question   => $question,
	start_time => '20171211 100908',
	item       => {
		status => 3,         # just a random numeric field
		source => 'markov',  # just a random text field
	}
);

# db call caught
my $answers = $ms->_searchItems(\%search);
#warn Dumper $catch_query::query;
cmp_select $catch_query::query, <<'__QUERY', 'constructed query';
 SELECT it.digest, it.title, it.description,
        TO_CHAR(it.created, 'DD-MM-YYYY HH24:MI:SS:MS') AS date,
        em.body AS body
   FROM item  AS it
        LEFT JOIN email_item AS em ON em.digest  = it.digest
  WHERE it.source ILIKE ?
    AND it.status = 3
    AND it.created >= '20171211 100908'
    AND it.digest = ANY(ARRAY((
        SELECT digest FROM item
         WHERE title ILIKE ? OR description ILIKE ?
            OR title ILIKE ? OR description ILIKE ? )
      UNION
      ( SELECT digest FROM email_item WHERE body ILIKE ? OR body ILIKE ? )
      UNION
      ( SELECT ti.item_id
        FROM tag JOIN tag_item AS ti ON ti.tag_id = tag.id
        WHERE ti.item_table_name = 'item' AND tag.name ILIKE ? )
      UNION
      ( SELECT digest FROM identifier WHERE UPPER(identifier) IN ('CVE-1-1')
     )))
__QUERY

#warn Dumper $catch_query::binds;
is_deeply $catch_query::binds, [
  'markov',
  '%CVE-1-1%',
  '%CVE-1-1%',
  '%word%',
  '%word%',
  '%CVE-1-1%',
  '%word%',
  'label'
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

#XXX Run explain to compile the query.

#warn "$_\n"
#	for $db->query("EXPLAIN $catch_query::query", @$catch_query::binds)->flat;

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
