#!/usr/bin/env perl
# Check the creation of complex queries to scan advisories

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
	start_time => '20180109 092311',
	advisories => {
		probability => 3,   # just a random numeric field
	},
);

# db call caught
my $answers = $ms->_searchAdvisories(\%search, type => 'advisory');
#warn Dumper $catch_query::query;

cmp_select $catch_query::query, <<'__QUERY', 'constructed query';
 SELECT details.govcertid, details.ids,
        details.id  AS details_id,
        pu.id       AS pub_id,
        pu.contents AS extra_text,
        TO_CHAR(pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS date,
        TO_CHAR(pu.created_on, 'DD-MM-YYYY') AS created,
        details.summary  AS description,
        details.title    AS title,
        details.version  AS version
   FROM publication_advisory AS details
		JOIN publication AS pu  ON details.publication_id = pu.id
  WHERE NOT deleted AND pu.created_on >= '20180109 092311'
    AND (details.id IN (
           SELECT id
           FROM publication_advisory
           WHERE summary ILIKE ? OR govcertid ILIKE ? OR ids ILIKE ?
         ) OR
         details.id IN (
           SELECT id
           FROM publication
           WHERE contents ILIKE ?
         ) OR
         details.id::varchar IN (
           SELECT ti.item_id
           FROM tag
                JOIN tag_item AS ti  ON ti.tag_id = tag.id
           WHERE ti.item_table_name = 'publication_advisory'
             AND tag.name ILIKE ?
         ) OR
         (details.govcertid ILIKE ? OR details.govcertid ILIKE ?
           OR details.ids ILIKE ? OR details.ids ILIKE ?))
__QUERY

#warn Dumper $catch_query::binds;
is_deeply $catch_query::binds, [
  '%word%',
  '%word%',
  '%word%',
  '%word%',
  'label',
  '%CVE-1-1 %',
  '%CVE-1-1',
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
