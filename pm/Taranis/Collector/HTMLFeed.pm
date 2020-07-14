# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::HTMLFeed;

use strict;
use Taranis qw(:all);
use Taranis::Collector;
use Taranis::Parsers;
use Data::Dumper;
use HTML::Entities qw(encode_entities decode_entities);
use URI;

sub new($$) {
	my ($class, $config, $debugSource) = @_;
	my $collector = Taranis::Collector->new($config, $debugSource);
	bless {collector => $collector}, $class;
}

sub collect {
	my ($self, $sourceData, $source, $debugSourceName) = @_;
	undef $self->{errmsg};
	my $debug      = !!$debugSourceName;
	my $collector  = $self->{collector};

	my $sourceName = $source->{sourceName};
	my $base       = $source->{fullurl};
	my $parserName = $source->{parser};

	print "processHtmlFeed debug: $debugSourceName - $sourceName\n" if $debug;

	my $parsers    = Taranis::Parsers->new($collector->{config});
	my $parser     = $parsers->getParser($parserName);
	unless($parser) {
		$self->{errmsg} = "HTML feed unknown parser $parserName.";
		return;
	}

	my $itemstart  = decode_entities $parser->{item_start};
	my $itemstop   = decode_entities $parser->{item_stop};
	my $titlestart = decode_entities $parser->{title_start};
	my $titlestop  = decode_entities $parser->{title_stop};
	my $descstart  = decode_entities $parser->{desc_start};
	my $descstop   = decode_entities $parser->{desc_stop};
	my $linkstart  = decode_entities $parser->{link_start};
	my $linkstop   = decode_entities $parser->{link_stop};
	my $linkprefix = decode_entities $parser->{link_prefix};

	if($debug) {
		print Dumper $parser, <<__DECODED;
parsing $parserName
--------
item:  $itemstart ... $itemstop
title: $titlestart ... $titlestop
descr: $descstart ... $descstop
link:  $linkstart ... $linkstop
linkprefix: $linkprefix (encoded as $parser->{link_prefix})
__DECODED
	}

	my @feed = $sourceData =~ m/\Q$itemstart\E(.*?)\Q$itemstop\E/gs;
	print @feed . " elements in feed\n" if $debug;
	if(@feed == 0) {
		$self->{errmsg} = "No items found in HTML feed";
		return;
	}

	my @items;

	ELEM:
	foreach my $elem (@feed) {
		my $absuri;
		if (length $linkstart > 0) {
			my $rellink = $elem =~ m/\Q$linkstart\E(.*?)\Q$linkstop\E/ ? trim($1) : "";

			# Let's be careful, that relative links with a parser which
			# does specify an link prefix will not change: do not feed
			# them to URI.  Otherwise, items inserted before 3.4.1 may
			# emerge again.

			if(!length $rellink) {
			} elsif(length $linkprefix) {
				my $abslink = $rellink =~ m/^http/i ? $rellink : "$linkprefix$rellink";
				$absuri     = URI->new($abslink);
			} else {
				$absuri     = URI->new_abs($rellink, $base);
			}
			print ">link relative: $rellink\nabsolute: $absuri\n" if $debug;
		}

		my $link      = $absuri && $absuri->has_recognized_scheme ? $absuri->canonical : '';
		my $raw_title = length $titlestart && $elem =~ /\Q$titlestart\E(.+?)\Q$titlestop\E/ ? $1 : '';
		my $raw_descr = length $descstart  && $elem =~ /\Q$descstart\E(.+?)\Q$descstop\E/   ? $1 : '';

		my $item      = $collector->prepareItemFromHTML(
			source      => $source,
			title       => $raw_title,
			description => $raw_descr,
			link        => $link,
			debug       => $debug,
		) or next ELEM;

		push @items, $item;
	}

	unless(@items) {
		$self->{errmsg} = "Could not find any items in this feed.";
		return;
	}

	[ grep delete($_->{is_new}), @items ];
}

1;

=head1 NAME

Taranis::Collector::HTMLFeed - HTML Collector

=head1 SYNOPSIS

  use Taranis::Collector::HTMLFeed;

  my $obj = Taranis::Collector::HTMLFeed->new( $oTaranisConfig, $debugSource );

  $obj->collect( $sourceData, $source, $debugSourceName );

=head1 DESCRIPTION

Collector for HTML sources. HTML sources are mostly parsed by a special HTML parser.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSourceName )

Constructor of the C<Taranis::Collector::HTMLFeed> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::HTMLFeed->new( $objTaranisConfig, 'NCSC' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $sourceData, $source, $debugSourceName )

Will collect items from retrieved data using a parser. Parameters $sourceData and $source are mandatory.
$sourceData is the HTML source. $source is a HASH reference with all the necessary source settings like C<sourcname>, C<parser> and C<digest>.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    $obj->collect( '<html><head>...', { parser => 'someparser', digest => 'MJH342kAS', sourcename => 'NCSC' }, 'NCSC' );

If successful Returns an ARRAY of HASH references with the following keys: itemDigest, link, description, title, status, matching_keywords (=ARRAY).
If unsuccessful it will return undef and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=cut
