#!/usr/bin/env perl

use warnings;
use strict;

use Test::More;
use Taranis qw(shorten_html);

is shorten_html('1234', 10), '1234', 'shorter';
is shorten_html('1234567890', 10), '1234567890', 'exact size';
is shorten_html('12345678901', 10), '123456 ...', 'shop last';
is shorten_html('123456789012345', 10), '123456 ...', 'shop last multi';

is shorten_html('12345 67890123', 10), '12345 ...', 'remove last word';
is shorten_html('12 345 67890123', 10), '12 345 ...', 'only last word';

is shorten_html('12 34 5&amp;89', 10), '12 34 ...', 'word with entity';
is shorten_html('123456&amp;89', 10), '123456 ...', 'entity at the end';

done_testing();

