# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::Twitter;

use strict;
use Taranis qw(:all);
use Taranis::Collector;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use Taranis::HttpUtil qw(lwpRequest);
use Data::Dumper;
use HTML::Entities;
use JSON;
use LWP::Authen::OAuth;
use Time::Local;

sub new {
	my ( $class, $config, $debugSource ) = @_;

	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource ),
	};
	
	return( bless( $self, $class ) );
}

sub getSourceData {
	my ( $self, $url, $source, $debugSource ) = @_;

	$self->{http_status} = 'OK';
	$source->{encoding} = undef;
	$self->{errmsg} = undef;
	
	my $retrieve_url = ( $url ) ? $url : $source->{fullurl};

	$retrieve_url = decode_entities( $retrieve_url );

	say "SSL request $retrieve_url" if ( $debugSource );

	my $response = lwpRequest(
		get => $retrieve_url,
		lwp_constructor => sub {
			LWP::Authen::OAuth->new(
				oauth_consumer_key => $source->{oauth_consumer_key} || Config->{twitter_consumer_key},
				oauth_consumer_secret => $source->{oauth_consumer_secret} || Config->{twitter_consumer_secret},
				oauth_token => $source->{oauth_token} || Config->{twitter_access_token},
				oauth_token_secret => $source->{oauth_token_secret} || Config->{twitter_access_token_secret},
			);
		},
	);

	if ( $response->is_success ) {
		print $response->status_line . "\n" if ( $debugSource );
		
		$self->{http_status_code} = $response->status_line;
		
		my $content = $response->decoded_content;
		
		return from_json( $content );

	} else {
		print $response->status_line . "\n" if ( $debugSource );
		
		my $error = 'Could not retrieve url ' . $retrieve_url . ' ' . $response->status_line;
				
		say $error if ( $debugSource );
		
		my $errorcode = $response->code;
		my $digest = $source->{digest};
		my $content = Dumper $response;

		# only write errors for sources with digest
		# images don't have a digest, image errors are handled
		# in other subs

		if ( !$self->{no_db} ) {

			$self->{collector}->{err}->writeError(
				digest => $digest, 
				error => $error, 
				error_code => $errorcode, 
				content => $content,
				sourceName => $source->{sourcename}
			);
		}

		$self->{http_status_line} = $response->status_line;
		$self->{http_status_code} = $errorcode;
		return 0; 
	}
}

sub collect {
	my ( $self, $sourceData, $source, $debugSourceName ) = @_;
	
	my $twitterStatusPrefix = "https://twitter.com/";
	
	my ( @newTweets, $response );
	
 	my $tweets = ( ref( $sourceData ) =~ /^HASH$/ ) ? $sourceData->{statuses} : $sourceData;

	my %already_collected;
	foreach my $tweet ( reverse @$tweets ) {
		# When this is a retweet, we want the source tweet only and uniquely
		$tweet = $tweet->{retweeted_status} if $tweet->{retweeted_status};

		my $createdAt = $self->parseTwitterDate( $tweet->{created_at} );
		my $createdAtStr = "on " . $createdAt->{day} . "-" . $createdAt->{month} . "-" . $createdAt->{year} . " at " . $createdAt->{hour} . ":" . $createdAt->{minute}; 

		my $title = encode_entities( $tweet->{text} );
		my $status = 0;
		
		my $link = "$twitterStatusPrefix$tweet->{user}->{screen_name}/status/$tweet->{id}";
		my $twitterUserName = encode_entities( $tweet->{user}->{name} );
		my $twitterScreenName = encode_entities( $tweet->{user}->{screen_name} );
		my $description = "Posted by $twitterUserName a.k.a \@$twitterScreenName $createdAtStr";

		say '>title: ' . "$title\n" if $debugSourceName;
		say '>description: ' . "$description\n\n" if $debugSourceName;

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

		my $cat_id     = $source->{categoryid};
		my $old_itemDigest = textDigest "$title$description$link";
		my $itemDigest     = textDigest "$title$description$link;$cat_id";

		my $collector = $self->{collector};
		if(    ! $already_collected{$itemDigest}++
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

			push @newTweets, {
				itemDigest => $itemDigest,
				'link' => $link,
				description => $description,
				title => $title,
				status => $status,
				matching_keywords => \@matchedKeywords
			};
		}
	}

	return \@newTweets;
}

sub getAdditionalConfigKeys {
	return [ qw( oauth_consumer_key oauth_consumer_secret oauth_token oauth_token_secret) ];
}

sub testCollector {
	my ( $self, $source ) = @_;
	my $testResult;

	my $fullurl = $source->{protocol} . $source->{host};

	if ($source->{port} && !(($source->{port} == 80 && $source->{protocol} == 'http://') or ($source->{port} == 443 && $source->{protocol} == 'https://'))) {
		$fullurl .= ':' . $source->{port};
	}

	$fullurl .= $source->{url};

	if ($source->{oauth_consumer_key} || Config->{twitter_consumer_key}) {
		my $response = lwpRequest(
			get => decode_entities( $fullurl ),
			lwp_constructor => sub {
				LWP::Authen::OAuth->new(
					oauth_consumer_key => $source->{oauth_consumer_key} || Config->{twitter_consumer_key},
					oauth_consumer_secret => $source->{oauth_consumer_secret} || Config->{twitter_consumer_secret},
					oauth_token => $source->{oauth_token} || Config->{twitter_access_token},
					oauth_token_secret => $source->{oauth_token_secret} || Config->{twitter_access_token_secret},
				);
			},
		);

		if ( $response->is_success ) {
			$testResult = "Connection OK";		
		} else {
			$testResult = "Connection failed: " . $response->status_line;
		}
	} else {
		$testResult = "Connection failed: missing OAuth configuration settings.";
	}

	return $testResult;
}

sub parseTwitterDate {
	# twitter date format: Thu Jun 13 15:22:00 +0000 2013
	my ( $self, $twitterDateStr ) = @_;
	my %date;

	my %months = (
		jan => 1, feb => 2, mar => 3, apr => 4,
		may => 5, jun => 6, jul => 7, aug => 8,
		sep => 9, 'oct' => 10, nov => 11, dec => 12
	);
	my $monthsString = join '|', keys %months;
	
	my %regex = ( 
		year => qr/^(\d{4})$/,
		month => qr/^($monthsString)$/i,
		day => qr/^(\d{1,2})$/,
		'time' => qr/^(\d\d):(\d\d):(\d\d)$/,
		timeZone => qr/^([+-]\d{4})$/
	);

	foreach ( split ' ', $twitterDateStr ) {
		( $date{year} ) = ( $_ =~ $regex{year} ) if ( $_ =~ $regex{year} );
		$date{month} = $months{ lc( ( $_ =~ $regex{month} )[0] ) } if $_ =~ $regex{month};
		( $date{day} ) = ( $_ =~ $regex{day} ) if ( $_ =~ $regex{day} );
		( $date{hour}, $date{minute}, $date{second} ) = ( $_ =~ $regex{'time'} ) if ( $_ =~ $regex{'time'} );
		( $date{timeZone} ) = ( $_ =~ $regex{timeZone} ) if ( $_ =~ $regex{timeZone} );
	}
	
	# local timezone correction
	my @t = localtime(time);
	my $gmt_offset_in_seconds = timegm(@t) - timelocal(@t);
	my $offsetHours = $gmt_offset_in_seconds / 3600;
	$date{hour} += $offsetHours;

	return \%date;
}

1;

=head1 NAME

Taranis::Collector::Twitter - Twitter Feed Collector

=head1 SYNOPSIS

  use Taranis::Collector::Twitter;

  my $obj = Taranis::Collector::Twitter->new( $objTaranisConfig, $debugSource );

  $obj->collect( $sourceData, $source, $debugSourceName );

  $obj->getSourceData( $url, \%source, $debugSource );

  $obj->testCollector( \%source );

  $obj->getAdditionalConfigKeys();

  Taranis::Collector::Twitter->getAdditionalConfigKeys();

  $obj->parseTwitterDate( $twitterDateStr );

=head1 DESCRIPTION

Collector for Twitter sources. The Twitter Collector makes use of Twitter API V1.1 and OAuth.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSource )

Constructor of the C<Taranis::Collector::Twitter> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::Twitter->new( $objTaranisConfig, 'Twitter-NCSC' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $sourceData, $source, $debugSourceName );

Will collect tweets from retrieved data. Parameters $sourceData and $source are mandatory.
$sourceData is the a datastructure created from the JSON return from Twitter. $source is a HASH reference with all the necessary source settings.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    $obj->collect( $arrayRef, { sourcename => 'NCSC', use_keyword_matching => 1 }, 'Twitter-NCSC' );

Returns an ARRAY of HASH references with the following keys: itemDigest, link, description, title, status, matching_keywords (=ARRAY reference).

=head2 getSourceData( $url, \%source, $debugSource );

Retrieves source data. It uses C<LWP::UserAgent> to retrieve data. 

Argument $url is optional. If $url is defined it will retrieve the URL. If it's not defined it will use C<< $source->{fullurl} >> as URL.

    $obj->getSourceData( 'https://api.twitter.com/1.1/search/tweets.json?q=taranis -rt&result_type=recent&count=20' );

OR

    $obj->getSourceData( undef, { fullurl => 'https://api.twitter.com/1.1/search/tweets.json?q=taranis -rt&result_type=recent&count=20', ... } );

It will return the parsed JSON as HASH reference if LWP GET request is successful. 
Also C<< $obj->{http_status_code} >> will be set to C<< HTTP::Response->status_line() >>.

If the request fails, it will return FALSE and it will write error information using C<< Taranis::Error->writeError() >>.
Also C<< $obj->{http_status_code} >> will be set to C<< HTTP::Response->code() >> and C<< $obj->{http_status_line} >> will be set to C<< HTTP::Response->status_line() >>.

=head2 testCollector( \%source )

Used to test the connection and retrieval of items.

    $obj->testCollector( { url => '/1.1/search/tweets.json?q=taranis -rt&result_type=recent&count=20', protocol => 'http', port => 80, ... } );

Returns a string message as result.

=head2 getAdditionalConfigKeys()

returns [ 'oauth_consumer_key', 'oauth_consumer_secret', 'oauth_token', 'oauth_token_secret' ];

=head2 parseTwitterDate( $twitterDateStr )

Parses a Twitter date. Expects a STRING like 'Thu Jun 13 15:22:00 +0000 2013'.

    $obj->parseTwitterDate( 'parseTwitterDate' );

Returns a HASH reference with keys C<year>, C<month>, C<day>, C<hour> and C<timeZone>.

=cut
