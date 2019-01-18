#!/usr/bin/env perl
# Check decoding of the user's search query

use warnings;
use strict;

use Test::More;

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Quotekeys = 0;

use_ok 'Taranis::MetaSearch';

my $ms = Taranis::MetaSearch->new(
	is_identifier => qr/^CVE-\d+-\d+/,
	db => { },
);
my @example_ids = qw/CVE-1-2 CVE-42-999 CVE-372-1/;

isa_ok $ms, 'Taranis::MetaSearch';

sub try_question($$$) {
	my ($label, $search, $expected) = @_;

#warn "SEARCH=$search\n";
	my $question = $ms->_evaluateQuestion($search);

#warn Dumper $question;
	is_deeply $question, $expected, $label;
}

try_question 'no question', undef, undef;
try_question 'empty question', '', undef;
try_question 'only blanks', "  \n \n\t  ", undef;

try_question 'one word', 'tic', {
	bonus_words   => [ 'tic' ],
	has_words     => 1,
	has_bonus     => 1,
	search_string => 'tic'
};

try_question 'two words', '  tic  tac  ', {
	bonus_words   => [ 'tic', 'tac' ],
	has_words     => 2,
	has_bonus     => 2,
	search_string => 'tic tac'
};

try_question 'required words', '+tic  tac  +toe', {
	bonus_words    => [ 'tac' ],
	required_words => [ 'tic', 'toe' ],
	has_words      => 3,
	has_bonus      => 1,
	has_required   => 2,
	search_string => '+tic tac +toe'
};

try_question 'excluded words', '-tic  tac  -toe', {
	bonus_words    => [ 'tac' ],
	excluded_words => [ 'tic', 'toe' ],
	has_words      => 3,
	has_bonus      => 1,
	has_excluded   => 2,
	search_string => '-tic tac -toe'
};

try_question 'mixture words', 'tic  +tac  -toe', {
	bonus_words    => [ 'tic' ],
	required_words => [ 'tac' ],
	excluded_words => [ 'toe' ],
	has_words      => 3,
	has_bonus      => 1,
	has_required   => 1,
	has_excluded   => 1,
	search_string => 'tic +tac -toe'
};

try_question 'quoted words', '  "tic tac"  +"tac tic"  -"tic toe"  ', {
	bonus_words    => [ 'tic tac' ],
	required_words => [ 'tac tic' ],
	excluded_words => [ 'tic toe' ],
	has_words      => 3,
	has_bonus      => 1,
	has_required   => 1,
	has_excluded   => 1,
	search_string  => '"tic tac" +"tac tic" -"tic toe"',
};

try_question 'mixture tags', ' tag:tic  +tag:tac  -tag:toe ', {
	bonus_tags    => [ 'tic' ],
	required_tags => [ 'tac' ],
	excluded_tags => [ 'toe' ],
	has_tags      => 3,
	has_bonus     => 1,
	has_required  => 1,
	has_excluded  => 1,
	search_string => 'tag:tic +tag:tac -tag:toe',
};

try_question 'discover certids', "@example_ids", {
	bonus_certids => \@example_ids,
	has_certids   => 3,
	has_bonus     => 3,
	search_string => "@example_ids",
};

try_question 'mixture certids', " $example_ids[0] +$example_ids[1]  -$example_ids[2]", {
	bonus_certids    => [ $example_ids[0] ],
	required_certids => [ $example_ids[1] ],
	excluded_certids => [ $example_ids[2] ],
	has_certids      => 3,
	has_bonus        => 1,
	has_required     => 1,
	has_excluded     => 1,
	search_string    => "$example_ids[0] +$example_ids[1] -$example_ids[2]",
};

### Skip problems

try_question 'incomplete sign', '  -  tic   +   tac', {
	bonus_words      => [ 'tic', 'tac' ],
	has_bonus        => 2,
	has_words        => 2,
	search_string    => '- tic + tac',
};

try_question 'incomplete tags', '-tag: +tag:', undef;

done_testing;
