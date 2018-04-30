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


sub new {
	my ( $class, $config, $debugSource ) = @_;
	
	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource ),
	};
	
	return( bless( $self, $class ) );
}

sub collect {
	my ( $self, $sourceData, $source, $debugSourceName ) = @_;
	undef $self->{errmsg};

	print "processHtmlFeed debug: " . $debugSourceName . " - " . $source->{sourcename} .  "\n" if ( $debugSourceName );

	my $collector = $self->{collector};
	my $parser = Taranis::Parsers->new( $collector->{config} );
	my @feedLinks;
	
	my $foundItems = 0;
	
	if ( my $element = $parser->getParser( $source->{parser} ) ) {
		print Dumper $element if ( $debugSourceName );

		say 'parsing ' . $source->{parser} if ( $debugSourceName );
		my $itemstart  = decode_entities( $element->{item_start} );
		my $itemstop   = decode_entities( $element->{item_stop} );
		my $titlestart = decode_entities( $element->{title_start} );
		my $titlestop  = decode_entities( $element->{title_stop} );
		my $descstart  = decode_entities( $element->{desc_start} );
		my $descstop   = decode_entities( $element->{desc_stop} );
		my $linkstart  = decode_entities( $element->{link_start} );
		my $linkstop   = decode_entities( $element->{link_stop} );
		my $linkprefix = decode_entities( $element->{link_prefix} );
		my $search1    = decode_entities( $element->{strip0_start} );
		my $replace1   = decode_entities( $element->{strip0_stop} );
		my $search2    = decode_entities( $element->{strip1_start} );
		my $replace2   = decode_entities( $element->{strip1_stop} );
		my $search3    = decode_entities( $element->{strip2_start} );
		my $replace3   = decode_entities( $element->{strip2_stop} );

		if ( $debugSourceName ) {
			print "\n--------\nLINKPREFIX: $linkprefix - $element->{link_prefix}\n";
			print "itemstart: $itemstart \n";
			print "itemstop: $itemstop\n";
			print "titlestart: $titlestart\n";
			print "titlestop $titlestop\n";
			print "descstart: $descstart\n";
			print "descstop: $descstop\n";
			print "linkstart: $linkstart\n";
			print "linkstop: $linkstop\n";
			print "linkprefix: $linkprefix\n"; 
		}

		my $maxlinklength  = 500;
		my $maxdesclength  = 500;
		my $maxtitlelength = 250;

		my $oddcheck = 0;

		my @split1 = split( /\Q$itemstart\E(.*?)\Q$itemstop\E/, $sourceData );		
		print scalar @split1 . " elements in split content\n" if $debugSourceName;

		if ( scalar( @split1 ) == 0 ) {
			$self->{errmsg} = "No items found in HTML feed";
			return;
		}

		my $link;

		foreach my $split1 ( @split1 ) {
			if ( $self->isOdd( $oddcheck++ ) ) {

				if ( length( $linkstart ) > 0 ) {
					my @linkarr = split( /\Q$linkstart\E(.*?)\Q$linkstop\E/, $split1 );					
					
					my $templink = ( $linkarr[1] ) ? trim( htmlToText( $linkarr[1] ) ) : "";

					print "TEMPLINK: $templink\n" if ( $debugSourceName );
					$link = ( lc( substr( $templink, 0, 4 ) ) eq "http" ) ? $templink : $linkprefix . $templink;
					
					print "LINK: $link\n" if ( $debugSourceName ); 
				}

				my ( @titleArr, @descriptionArr );
				my ( $title, $description );
				my $status = 0;
				
				if ( length( $titlestart ) > 0 ) {
					@titleArr = split( /\Q$titlestart\E(.*?)\Q$titlestop\E/, $split1 );
					$title = $titleArr[1];
				}

				if ( length( $descstart ) > 0 ) {
					@descriptionArr = split( /\Q$descstart\E(.*?)\Q$descstop\E/, $split1 );
					$description = $descriptionArr[1];
				}

				$description = $collector->prepareTextForSaving( $description ) if ( $description );
				$title = $collector->prepareTextForSaving( $title ) if ( $title );

				$description = htmlToText( $description );
				$title = ( $title ) ? htmlToText( $title ) : "";
				
				# Filter invalid URIs
				my $link_uri = URI->new($link);
				
				if($link_uri->has_recognized_scheme) {
					$link = $link_uri->canonical;
				} else {
					$link = '#';
				}

				my $cat_id = $source->{categoryid};
				my $old_itemDigest = textDigest "$title$description$link";
				my $itemDigest = textDigest "$title$description$link;$cat_id";

				if ( $link ne "" && $title ne "" ) {
					
					$title = encode_entities( $title );
					$description = encode_entities( $description );

					my $completeTitle = $title;
					my $completeDescription = $description;
					my $completeLink = $link;

					if ( length( $description ) > $maxdesclength ) {
						$description = substr( $description, 0, $maxdesclength );
						$description =~ s/(.*)\s+.*?$/$1/;
					}
					
					if ( length( $title ) > $maxtitlelength ) {
						$title = substr( $title, 0, $maxtitlelength );
						$title =~ s/(.*)\s+.*?$/$1/;
					}		

					if ( !$self->{no_db} ) {
		 				if ( length $link > $maxlinklength ) {
							$collector->{err}->writeError(
								digest => $source->{digest},
								content => undef,
								error_code => '012',
								error => 'Link exceeds max link length. LINK: ' . $link,
								sourceName => $source->{sourcename}
							);
							$link = substr( $link, 0, $maxlinklength );
						}
					}

					if (   ! $self->{no_db} 
						&& ! $collector->itemExists($old_itemDigest)
						&& ! $collector->itemExists($itemDigest)
					) {

						my @matchedKeywords;
						
						if ( $source->{use_keyword_matching} ) {
							if ( $source->{wordlists} ) {
								@matchedKeywords = $collector->getMatchingKeywordsForSource( $source, [ $completeTitle, $completeDescription, $completeLink ] );
								$status = 1 if ( !@matchedKeywords );
								print ">matched keywords: @matchedKeywords\n" if $debugSourceName;
							} else {
								# if no wordlists are configured set all items to 'read' status
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
						
					} else {
						$foundItems = 1;
						print "$itemDigest Exists in table item\n" if $debugSourceName;
					}
				} 
			}
		}
	}

	if ( $foundItems ) {
		return \@feedLinks;	
	} else {
		$self->{errmsg} = "HTML feed only contains bad items.";
		return;		
	}
}

sub isOdd {
	my ( $self, $oddCheck ) = @_;
	return ( ( $oddCheck % 2 ) != 0 );
}

1;

=head1 NAME

Taranis::Collector::HTMLFeed - HTML Collector

=head1 SYNOPSIS

  use Taranis::Collector::HTMLFeed;

  my $obj = Taranis::Collector::HTMLFeed->new( $oTaranisConfig, $debugSource );

  $obj->collect( $sourceData, $source, $debugSourceName );

  $obj->isOdd( $number );

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

If successful Returns an ARRAY of HASH references with the following keys: itemDigest, link, description, title, status, matching_keywords (=ARRAY reference).
If unsuccessful it will return undef and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 isOdd( $number )

Checks whether the supplied number is odd or even.

    $obj->isOdd( 7 );

Returns TRUE if supplied number is odd. Returns FALSE if supplied number even.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<No items found in HTML feed> and I<HTML feed only contains bad items.>

Caused by collect() when there are no items found after parsing the HTML source.
You should check if set parser for th current source is configured correctly. 

=back

=head1 DEPENDENCIES

CPAN module required is B<Data::Dumper>.

Taranis modules required are B<Taranis>, B<Taranis::Collector> and B<Taranis::Parsers>.

=cut
