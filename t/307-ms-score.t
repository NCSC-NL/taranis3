#!/usr/bin/env perl
# Check the scoring algoritms

use warnings;
use strict;

use Test::More;

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Quotekeys = 0;

use_ok 'Taranis::MetaSearch';

my $log;
my $ms = Taranis::MetaSearch->new(
	is_identifier => qr/^CVE-\d+-\d+/,
	db        => {},
	log_score => sub { $log = $_[0] },
);
isa_ok $ms, 'Taranis::MetaSearch';

# construct a question (identical to the string in 'item')
my $question = $ms->_evaluateQuestion("  CVE-1-1 word  tag:label another ");

my %search = (
	question   => $question,
);

$ms->_score(\%search,
    type        => 'fake item',
	title       => 'contains word',
	description => 'another contains word',
	extra_text  => 'contains word',
	tags        => [ 'label', 'tag1' ],
	cert_ids    => [ 'CVE-1-2', 'CVE-1-1' ],
	date        => '10-01-2017 16:44:42.123',
);

is $log, <<__SCORE;
fake item score: 110.2017011016444212 - contains word =
+ 1 * 15 --> bonus_words in title
+ 2 * 5  --> bonus_words in descr
+ 1 * 50 --> bonus_words in extra
+ 10 bonus tag 'label'
+ 1 * 25 bonus certids
+ 0.2017011016444212 timestamp
__SCORE

done_testing();
