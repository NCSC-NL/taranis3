# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::XMLFeed;

use strict;
use Taranis qw(:all);
use Taranis::Collector;
use XML::FeedPP;
use HTML::Entities qw(encode_entities);
use Encode;


sub new {
	my ( $class, $config, $debugSource ) = @_;
	
	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource ),
	};
	
	return( bless( $self, $class ) );
}

sub collect {
	my ( $self, $sourceData, $source, $debugSourceName ) = @_;
	my @feedLinks;
	undef $self->{errmsg};

	my %collectedDigests;
	my $feed;
	my $foundItems = 0;
	
	my $debug = ( $source->{sourcename} eq $debugSourceName ) ? 1 : 0;
	my $encoding = $source->{encoding} || 'UTF-8';

	if ( $sourceData !~ /^<\?xml/i ) {
		$sourceData = '<?xml version="1.0" encoding="'.$encoding.'"?>' . $sourceData;
	}

	eval { $feed = XML::FeedPP->new( $sourceData, ignore_error => 1 ) };
	
	if ( $@ ) {
		my $strippedError = $@;
		$strippedError =~ s/(.*?)at \/.*/$1/i;
		
		$self->{errmsg} = "XML parsing error: " . $strippedError;
		say $self->{errmsg} if ( $debug );
		$sourceData = '';
		return;
	}

	my @feedItems = $feed->get_item();
	
	if ( scalar( @feedItems ) == 0 ) {
		$self->{errmsg} = "No items found in XML feed";
		return;
	}

	my $collector = $self->{collector};
	foreach my $item ( @feedItems ) {

		my $title = $item->title();
		my $link = $item->link();
		my $description = $item->description();
		my $status = 0;

		if ( ref( $description ) eq 'HASH' ) {
			$description = ( ref( $description->{'a'} ) ne 'ARRAY' && exists( $description->{'a'}->{'#text'} ) && defined( $description->{'a'}->{'#text'} ) ) 
				? $description->{'a'}->{'#text'} 
				: "" ;
			$description = ( $description eq "" && ref( $item->{summary} ) ne 'HASH' ) ? $item->{summary} : "";
		}

		$title = $collector->prepareTextForSaving( $title ) if ( $title );
		$description = $collector->prepareTextForSaving( $description ) if ( $description );
	
		$title = ( $title ) ? htmlToText( $title ) : "";
		$link  = htmlToText( $link );

		$description = htmlToText( $description );

		my $cat_id   = $source->{categoryid};
		my $old_itemDigest = textDigest "$title$description$link";
		my $itemDigest     = textDigest "$title$description$link;$cat_id";

		if ( $link ne "" && $title ne "" ) {
			$title = encode_entities( $title );
			$description = encode_entities( $description );

			print '>title: ' . "$title\n"  if $debug;
			print '>description: ' . "$description\n\n"  if $debug;

			my $completeTitle = $title;
			my $completeDescription = $description;
			my $completeLink = $link;
			
			if ( length( $description ) > 500 ) {
				$description = substr( $description, 0, 500 );
				$description =~ s/(.*)\s+.*?$/$1/;
			}
			
			if ( length( $title ) > 250 ) {
				$title = substr( $title, 0, 250 );
				$title =~ s/(.*)\s+.*?$/$1/;
			}

			if ( !$self->{no_db} ) {
 				if ( length $link > 500 ) {
					$collector->{err}->writeError(
						digest => $source->{digest},
						content => undef,
						error_code => '012',
						error => 'Link exceeds max link length. LINK: ' . $link,
						sourceName => $source->{sourcename}
					);
					$link = substr(  $link, 0, 500 );
				}
			}

			my %where = ( digest => $itemDigest );
			if (   $collectedDigests{$itemDigest}
				|| $collector->itemExists($old_itemDigest)
				|| $collector->itemExists($itemDigest)
			   ) {
				$foundItems = 1;
				print "$itemDigest Exists in table item\n" if $debug;
			} else {

				$collectedDigests{$itemDigest} = 1;
				my @matchedKeywords;
				
				if ( $source->{use_keyword_matching} ) {
					if ( $source->{wordlists} ) {
						@matchedKeywords = $collector->getMatchingKeywordsForSource( $source, [ $completeTitle, $completeDescription, $completeLink ] );
						$status = 1 if ( !@matchedKeywords );
						print ">matched keywords: @matchedKeywords\n" if $debug;
					} else {
						# if no wordlists are configured (and source has set use_keyword_matching to true) set all items to 'read' status
						$status = 1;
					}
				}
				
				$foundItems = 1;
				push @feedLinks, { 
					itemDigest => $itemDigest, 
					'link' => $link, 
					description => $description, 
					title => $title, 
					status => $status,
					matching_keywords => \@matchedKeywords
				};
				
			}
		} 
	}
	
	if ( $foundItems ) {
		return \@feedLinks;	
	} else {
		$self->{errmsg} = "XML feed only contains bad items.";
		return;		
	}
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

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<No items found in XML feed> and I<XML feed only contains bad items.>

Caused by collect() when there are no items found after parsing the HTML source.
You should check if set parser for th current source is configured correctly. 

=item *

I<XML parsing error: '...'>

Caused by collect() when Perl module C<XML::FeedPP> encounters an parsing error.
You should check the XML source.

=back

=cut
