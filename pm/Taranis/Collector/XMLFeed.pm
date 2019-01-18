# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::XMLFeed;

use strict;
use warnings;

use Taranis::Collector;
use XML::FeedPP;

sub new {
	my ($class, $config, $debugSource) = @_;
	my $collector = Taranis::Collector->new($config, $debugSource);
	bless {collector => $collector}, $class;
}

sub collect {
	my ($self, $sourceData, $source, $debugSourceName) = @_;
	undef $self->{errmsg};
	my $collector = $self->{collector};
	
	my $debug    = !!$debugSourceName;
	my $encoding = $source->{encoding} || 'UTF-8';

	$sourceData = qq{<?xml version="1.0" encoding="$encoding"?>$sourceData}
		if $sourceData !~ /^<\?xml/i;

	my $feed = eval { XML::FeedPP->new($sourceData, ignore_error => 1) };
	if(my $err = $@) {
		$err =~ s!\bat /.*!!;
		$self->{errmsg} = "XML parsing error: $err";
		print "$self->{errmsg}\n" if $debug;
		return;
	}

	my @feed_items = $feed->get_item;
	if(@feed_items == 0) {
		$self->{errmsg} = "No items found in XML feed";
		return;
	}

	my @items;
	foreach my $feed (@feed_items) {
		my $descr = $feed->description || '';
		if(ref $descr eq 'HASH' ) {
			my $a    = $descr->{a};
			$descr   = ref $a eq 'HASH' && defined $a->{'#text'} ? $a->{'#text'} : "" ;
			$descr ||= $feed->{summary}
				if ref $feed->{summary} ne 'HASH';
		}

		my $item = $collector->prepareItemFromHTML(
			source      => $source,
			title       => $feed->title,
			link        => $feed->link,
			description => $descr,
			debug       => $debug,
		) or next;

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

Taranis::Collector::XMLFeed - RSS Feed Collector

=head1 SYNOPSIS

  use Taranis::Collector::XMLFeed;

  my $obj = Taranis::Collector::XMLFeed->new( $oTaranisConfig, $debugSource );

  $obj->collect( $sourceData, $source, $debugSourceName );

=head1 DESCRIPTION

Collector for RSS sources. RSS sources are parsed using the Perl module C<XML::FeedPP>.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSourceName )

Constructor of the C<Taranis::Collector::XMLFeed> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::XMLFeed->new( $objTaranisConfig, 'NCSC' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $sourceData, $source, $debugSourceName );

Will collect items from retrieved data using Perl module C<XML::FeedPP>. Parameters $sourceData and $source are mandatory.
$sourceData is the XML source. $source is a HASH reference with all the necessary source settings like C<sourcname> and C<digest>.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    $obj->collect( '<?xml version="1.0" ...', { digest => 'MJH342kAS', sourcename => 'NCSC' }, 'NCSC' );

If successful Returns an ARRAY of HASH references with the following keys: itemDigest, link, description, title, status, matching_keywords (=ARRAY reference).
If unsuccessful it will return undef and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=cut
