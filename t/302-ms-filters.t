#!/usr/bin/env perl
# Test the creation of word/tag/certid filter database query fragments

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
	db => {},
);
isa_ok $ms, 'Taranis::MetaSearch';

my (@where, @binds);

### Word filter

my @word_args = (
	id_field => 'ana.digest',
	table    => 'analysis',
	columns  => [ 'comment', 'title' ],
);

my $word_pos = $ms->_wordFilterFind(\@binds, [ 'tic', 'tac' ], @word_args);
ok $word_pos, 'create word filter';

cmp_select $word_pos, <<'__POSITIVE', '...positive';
  ana.digest IN (
     SELECT digest
     FROM analysis
     WHERE comment ILIKE ? OR title ILIKE ? OR comment ILIKE ? OR title ILIKE ?
)
__POSITIVE

my $word_neg = $ms->_wordFilterBlock(\@binds, [ 'toe' ], @word_args);
cmp_select $word_neg, <<'__NEGATIVE', '...negative';
 ana.digest NOT IN (
   SELECT digest
   FROM analysis
   WHERE comment ILIKE ? OR title ILIKE ?
 )
__NEGATIVE

is_deeply \@binds, [ qw/%tic% %tic% %tac% %tac% %toe% %toe%/ ], '...binds';

### tag filter

(@where, @binds) = ();

my @tag_args = (
	id_field  => 'ana.digest',
	table     => 'analysis',
	tag_group => 'group',
);

my $tag_pos = $ms->_tagFilterFind(\@binds, [ 'tic', 'tac' ], @tag_args);
ok $tag_pos, 'create tag filter';

cmp_select $tag_pos, <<'__POSITIVE', '...positive';
 ana.digest IN (
   SELECT ti.item_id
   FROM tag
        JOIN tag_item AS ti  ON ti.tag_id = tag.id
  WHERE ti.item_table_name = 'group'
    AND tag.name ILIKE ? OR tag.name ILIKE ?
)
__POSITIVE

my $tag_neg = $ms->_tagFilterBlock(\@binds, [ 'toe' ], @tag_args);
cmp_select $tag_neg, <<'__NEGATIVE', '...negative';
 ana.digest NOT IN (
   SELECT ti.item_id
   FROM tag
        JOIN tag_item AS ti  ON ti.tag_id = tag.id
  WHERE ti.item_table_name = 'group'
    AND tag.name ILIKE ?
)
__NEGATIVE

is_deeply \@binds, [ qw/tic tac toe/ ], '...binds';


### certid filter via table (for assess items)

(@where, @binds) = ();

my @certid_args = (
	id_field  => 'ana.digest',
	table     => 'identifier',
);

my $id_pos = $ms->_certidFilterFind(\@binds, [ 'tic', 'tac' ], @certid_args);
ok $id_pos, 'create certid filter by table';

cmp_select $id_pos, <<'__POSITIVE', '...positive';
 ana.digest IN (
   SELECT digest
   FROM identifier
   WHERE UPPER(identifier) IN ('TIC','TAC')
 )
__POSITIVE

my $id_neg = $ms->_certidFilterBlock(\@binds, [ 'toe' ], @certid_args);
cmp_select $id_neg, <<'__NEGATIVE', '...negative';
 ana.digest NOT IN (
   SELECT digest
   FROM identifier
   WHERE UPPER(identifier) IN ('TOE')
 )
__NEGATIVE

cmp_ok scalar @binds, '==', 0, '...no binds';


### certid filter via fields (other searches)

(@where, @binds) = ();

my @certid2_args = (
	fields => [ qw/govcertid ids/ ],
);

my $id2_pos = $ms->_certidFilterFieldsFind(\@binds, ['tic', 'tac'],
	@certid2_args);
ok $id2_pos, 'create certid filter by field';

cmp_select $id2_pos, <<'__POSITIVE', '...positive';
 (govcertid ILIKE ? OR govcertid ILIKE ? OR
  govcertid ILIKE ? OR govcertid ILIKE ? OR
  ids ILIKE ? OR ids ILIKE ? OR
  ids ILIKE ? OR ids ILIKE ?)
__POSITIVE

my $id2_neg = $ms->_certidFilterFieldsBlock(\@binds, [ 'toe' ], @certid2_args);
cmp_select $id2_neg, <<'__NEGATIVE', '...negative';
  NOT (govcertid ILIKE ? OR govcertid ILIKE ? OR ids ILIKE ? OR ids ILIKE ?)
__NEGATIVE

cmp_ok scalar @binds, '==', 12, '... binds';
#warn Dumper \@binds;
is_deeply \@binds, [
  '%tic %',
  '%tic',
  '%tac %',
  '%tac',
  '%tic %',
  '%tic',
  '%tac %',
  '%tac',
  '%toe %',
  '%toe',
  '%toe %',
  '%toe'
];

done_testing;
