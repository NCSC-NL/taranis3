#!/usr/bin/env perl
# Check _to_CDATA

use warnings;
use strict;
use utf8;

use Test::More;

use_ok 'Taranis::Publication';

*_to_CDATA = \&Taranis::Publication::_to_CDATA;
sub CDATA($) { '<![CDATA[' . $_[0] . ']]>' }

ok ! defined _to_CDATA(undef), 'undef';
is _to_CDATA(42), '42', 'int';
is_deeply _to_CDATA([43, 44, undef, 45]), [43, 44, undef, 45], 'array';
is_deeply _to_CDATA({a => 1, b => 2}), { a => 1, b => 2}, 'hash';

is _to_CDATA("tic"), CDATA('tic'), 'string';
is _to_CDATA("t&agrave;&ccedil;"), CDATA("tàç"), 'encoded';

done_testing();
