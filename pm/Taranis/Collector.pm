# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector;

use strict;
use Taranis qw(:all);
use Taranis::Config::XMLGeneric;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::HttpUtil qw(lwpRequest);
use Taranis::Error;
use Taranis::Screenshot;
use Taranis::Wordlist;

use HTML::Entities qw(decode_entities encode_entities);
use Data::Dumper;
use POSIX qw(strftime);

use constant {
	MAX_LINK_LENGTH  => 500,
	MAX_DESCR_LENGTH => 500,
	MAX_TITLE_LENGTH => 250,
};

sub new {
	my ( $class, $config, $debugSource ) = @_;

	my $self = {
		errmsg => undef,
		config => $config,
		dbh => Database,
		sql => Sql,
		err => Taranis::Error->new( $config ),
	};

	return( bless( $self, $class ) );
}

sub getStrips {
	my ( $self, $configFile ) = @_;
	my $stripscfg = Taranis::Config::XMLGeneric->new( $self->{config}->{stripsconfig}, "hostname", "strips" );
	return decode_entities_deep( $stripscfg->loadCollection() );
}

# Returns whether it's time to check this source.
sub sourceMtbcPassed {
	my ( $self, $source, $debugSource ) = @_;

	my $mtbcSec    = ($source->{mtbc} // 0) * 60;
	my $mtbcRandom = ($source->{mtbc_random_delay_max} // 0) * 60;

	my %where = ( source => $source->{digest} );

	my ( $stmnt, @bind ) = $self->{sql}->select( "checkstatus", "timestamp", \%where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my $timestamp = 0;
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$timestamp = $record->{timestamp};
	}

	# Add a semi-random delay between 0 and (`mtbc_random_delay_max` * 60) seconds.
	my $randomDelay = $mtbcRandom ? rand($mtbcRandom) : 0;
	my $nextRun     = $timestamp + $mtbcSec + $randomDelay;
	my $readyToRun  = $nextRun <= time();

	if ( $debugSource ) {
		printf(
			"source ready for next run at: %d (previous run) + %d (mtbc) + %d (random delay) = %d, aka %s\n",
			$timestamp, $mtbcSec, $randomDelay, $nextRun, strftime( "%Y-%m-%d %H:%M:%S", localtime($nextRun)));
		say $readyToRun ? "source is ready to run." : "source is not ready to run yet.";
	}

	return $readyToRun;
}

sub getSourceData {
	my ( $self, $url, $source, $debugSource ) = @_;

	$source->{encoding} = undef;
	$self->{errmsg}     = undef;

	my $retrieve_url = $url // $source->{fullurl};
	$retrieve_url = decode_entities( $retrieve_url );
	$retrieve_url =~ s/\\//g; # strip backslash from url

	say "request $retrieve_url" if ( $debugSource );
	my $response = lwpRequest(get => $retrieve_url);

	my $is_image = $source->{is_image} ? 1 : 0;

	my $code = $self->{http_status_code} = $response->code;
	my $sl   = $self->{http_status_line} = $response->status_line;
	print "$sl\n" if $debugSource;

	if($response->is_success) {
		my $content = $response->decoded_content;

		return from_json($content)
			if lc($source->{parser}) eq 'twitter';

		my $encoding = 'UTF-8';
		unless($is_image) {
			if ( $content =~ /encoding="([^"]+)"/ ) {
				$encoding = $1;
			} else {
				$encoding = $response->headers->content_type_charset;
			}
			say "Encoding: $encoding" if $debugSource;
		}
		$source->{encoding} = $encoding;
		return $content;
	}

	my $error = "Could not retrieve url $retrieve_url $sl";
	say $error if $debugSource;

	if ( !$self->{no_db} && !$is_image ) {
		# Only write errors for sources with digest.
		# images don't have a digest, image errors are handled
		# in other subs

		$self->writeError(
			source     => $source,
			error      => $error,
			error_code => $code,
			content    => (Dumper $response),
		);
	}

	undef;
}

sub itemExists($) {
	my ($self, $digest) = @_;
	   $self->{dbh}->checkIfExists({digest => $digest}, "item")
	|| $self->{dbh}->checkIfExists({digest => $digest}, "item_archive");
}

#XXX this was Taranis::htmlToText()
# The code is cleaning-up in a messy way, but cannot be changed (yet)
# to avoid the risk that already processed items will reappear because
# their check-sum accidentally changed.
sub _sloppy_strip_html($) {

	#XXX decode too early
    my $field = decode_entities $_[0];

	for($field) {
		s/\p{IsSpace}+/ /gs;
		s/\'//gi;
    	s/\n/ /gi;
    	s/&lt;/</gi;        #XXX shouldn't be possible
    	s/&gt;/>/gi;
    	s/<(.*?)>//gi;
    	s/<!--(.*)-->//gi;  #XXX already removed
    	s/^ //;
    	s/ $//;
	}
	$field;
}

sub _strong_strip_html($) {
	my $field = shift;
	for($field) {
		s/\<\!--.*?--\>/ /gs;  # strip comments
		s/\<[^>]+\>/ /gs;      # strip markup
		s/\p{IsSpace}+/ /gs;   # seq of blanks and cr/lf to single blank
		s/^ //; s/ $//;        # strip leading/trailing blanks
	}
	decode_entities $field;
}

# Convert collected data into an item which may get inserted into the db
sub prepareItemFromHTML(%) {
	my ($self, %raw) = @_;

	my $debug  = $raw{debug};
	my $source = $raw{source};
	my $cat_id = $source->{categoryid};

	my $link   = $raw{link};

	my $title_stripped = _sloppy_strip_html $raw{title};
	my $descr_stripped = _sloppy_strip_html $raw{description};

	length $title_stripped && length $link
		or return undef;

	# before 3.4.0, the category was not in the digest
	my $old_digest = textDigest "$title_stripped$descr_stripped$link";
	my $digest     = textDigest "$title_stripped$descr_stripped$link;$cat_id";

	if(my $d = $self->itemExists($old_digest) || $self->itemExists($digest)) {
		print "item $digest already exists\n" if $debug;
		return { is_new => 0 };
	}
	print "item $digest is new, $raw{title}\n" if $debug;

	my $title  = encode_entities( _strong_strip_html $raw{title} );
	my $descr  = encode_entities( _strong_strip_html $raw{description} );

	my $keywords;
	my $status = 0;

	if($source->{use_keyword_matching}) {
		$keywords = $self->_matchingKeywords($source, $title, $descr, $link);
		print ">matched keywords: @$keywords\n" if $debug;
		$status = @$keywords ? 0 : 1;
	}

	if(length $link > MAX_LINK_LENGTH) {
		$self->writeError(
			source     => $source,
			content    => undef,
			error_code => '012',
			error      => "Link exceeds max link length. LINK: $link",
		);
		$link = substr $link, 0, MAX_LINK_LENGTH;
	}

	+{
		itemDigest  => $digest,
		is_new      => 1,
		status      => $status,
		title       => shorten_html($title, MAX_TITLE_LENGTH),
		description => shorten_html($descr, MAX_DESCR_LENGTH),
		link        => $link,
		matching_keywords => $keywords,
	};
}

sub processScreenshot {
	my ( $self, $item, $source, $debugSource ) = @_;

	my %screenshotArgs = ( screenshot_module => $self->{config}->{screenshot_module} );
	$screenshotArgs{proxy_host} = $self->{config}->{proxy_host} if ( $self->{config}->{proxy_host} );
	$screenshotArgs{user_agent} = $self->{config}->{useragent} if ( $self->{config}->{useragent} );

	my $screenshot = Taranis::Screenshot->new( %screenshotArgs );

	if ( my $screenshot = $screenshot->takeScreenshot( siteAddress => $item->{'link'} ) ) {
		say "screenshot of $item->{'link'} OK" if ( $debugSource );

		if ( my $blobDetails = $self->{dbh}->addFileAsBlob( binary => $screenshot ) ) {

			return $blobDetails;

		} else {
			$self->writeError(
				source => $source,
				error => 'Failed to take a screenshot of website (1): ' . $screenshot->{errmsg},
				error_code => '019',
			);
			say "screenshot of $item->{'link'} FAILED (1)" if ( $debugSource );
		}
	} else {
		$self->writeError(
			source     => $source,
			error      => 'Failed to take a screenshot of website (2): ' . $screenshot->{errmsg},
			error_code => '019',
		);
		say "screenshot of $item->{'link'} FAILED (2)" if ( $debugSource );
	}

	return 0;
}

sub writeSourceCheck {
	my ( $self, %arg ) = @_;

	my $source 	= $arg{source};
	my $comment = $arg{comment};

	my $table   = 'checkstatus';
	my %where   = ( source => $source );
	my %updates = ( timestamp => nowstring(4), comments => $comment );

	if ( $self->{dbh}->checkIfExists( \%where, $table ) ) {
		my ( $stmnt, @bind ) = $self->{sql}->update( $table, \%updates, \%where );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}

	} else {
		$updates{source} = $source;
		my ( $stmnt, @bind ) = $self->{sql}->insert( $table, \%updates );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	}
	return 1;
}

sub parseIdentifierPatterns($$) {
	my ($self, $sourceData, $configFile) = @_;

	my $idconfig   = $self->{config}->{identifiersconfig};
	my $identifier = Taranis::Config::XMLGeneric->new( $idconfig, "idname", "ids", undef, $configFile );
	my $identifiers = decode_entities_deep( $identifier->loadCollection() );

	my @found;
	foreach my $line ( @$identifiers ) {
		while ( $sourceData =~ m/($line->{pattern})/gi ) {
			my $certid = $1;
			if(my $s = $line->{substitute}) {
				if($s =~ m!(.*?)/(.*)!i) {
					$certid =~ s/$1/$2/gi;
				}
			}

			push @found, $certid;
		}
	}

	@found;
}

sub setCollectorStarted {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->insert('statistics_collector', { collector_id => $args{collectorId}, status => $args{status} });

	$self->{dbh}->prepare( $stmnt );
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return $self->{dbh}->getLastInsertedId( 'statistics_collector' );
	} else {
		$self->{errmsg} .= $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setCollectorFinished {
	my ( $self, %args ) = @_;
	return $self->setCollectorStatus( collectorRunId => $args{collectorRunId}, finished => \'NOW()', status => '--END-- @ ' . nowstring(7) );
}

sub setCollectorStatus {
	my ( $self, %update ) = @_;
	undef $self->{errmsg};

	my $collectorRunId = delete( $update{collectorRunId} ) if ( $update{collectorRunId} );
	my $statusUpdate;
	if ( exists( $update{status} ) ) {
		$statusUpdate = $update{status};
		$update{status} = \'status || ?';
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( 'statistics_collector', \%update, { id => $collectorRunId } );

	my @binds = $collectorRunId;
	unshift @binds, $statusUpdate if ( $statusUpdate );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @binds );
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} .= $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} .= "Action failed, corresponding id not found in database.";
		return 0;
	}
}

sub writeCVEs($@) {
	my ($self, $digest, @identifiers) = @_;
	undef $self->{errmsg};
	@identifiers or return 1;

	my $db = $self->{dbh}->simple;

	#XXX Conflicts rarely emerge when parallel feeds are processed,
	# with a race condition on the uniqueness of the digest.

	foreach my $identifier (@identifiers) {
		$db->query( <<__CVE, $digest, $identifier );
INSERT INTO identifier (digest, identifier) VALUES (?, ?)
    ON CONFLICT DO NOTHING
__CVE
	}

	1;
}

sub stripsData {
	my ( $self, $html, $configFile ) = @_;
	my ( $hostname, $strip0, $strip1, $strip2, $strip3, $strip4 );

	my $strips = $self->getStrips( $configFile );

	if ( $strips ) {
		foreach my $strip ( @$strips ) {
			$hostname = $strip->{hostname};
			if ( $strip->{strip0} ) {
				$strip0 = $strip->{strip0};
				$html =~ s/$strip0//gi;
			}
			if ( $strip->{strip1} ) {
				$strip1 = $strip->{strip1};
				$html =~ s/$strip1//gi;
			}
			if ( $strip->{strip2} ) {
				$strip2 = $strip->{strip2};
				$html =~ s/$strip2//gi;
			}
			if ( $strip->{strip3} ) {
				$strip3 = $strip->{strip3};
				$html =~ s/$strip3//gi;
			}
			if ( $strip->{strip4} ) {
				$strip4 = $strip->{strip4};
				$html =~ s/$strip4//gi;
			}
		}
	}

	return $html;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord();
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord();
}

sub _matchingKeywords($@) {
	my ($self, $source, @text) = @_;

	my $wordlists = $source->{wordlists}
		or return ();

	my %matches;
	foreach my $wl (@$wordlists) {
		my $has_wl = $wl->{match};
		my $and_wl = $wl->{and_match};

		foreach my $text (@text) {
			my %found;
			$found{lc $_}++ for $text =~ /$has_wl/g;

			if($and_wl) {
				my %also;
				$also{lc $_} for $text =~ /$and_wl/g;
				$also{$_} or delete $found{$_} for keys %found;
			}
			$matches{$_}++ for keys %found;
		}
	}

	[ keys %matches ];
}

#XXX Still in use for IMAP and POP sources, awaiting for the full
#XXX collector rewrite which brings full unification of feeds.
sub getMatchingKeywordsForSource($$) {
	my ($self, $source, $texts) = @_;
	my $k = $self->_matchingKeywords($source, @$texts) || [];
	@$k;
}

sub writeError(@) {
	my $self = shift;
	$self->{err}->writeError(@_);
}

1;


=head1 NAME

Taranis::Collector - module for collecting and processing of IMAP, POP3, HTML and XML sources.

=head1 SYNOPSIS

  use Taranis::Collector;

  my $obj = Taranis::Collector->new( $objTaranisConfig, $debugSource );

  $obj->getMatchingKeywordsForSource( \%source, \@keywordMatchingInputList );

  $obj->getSourceData( $url, $source, $debugSource );

  $obj->sourceMtbcPassed( $source, $debugSource );

  $obj->getStrips();

  $obj->parseIdentifierPatterns( $sourceData, $configFile );

  $obj->processScreenshot( $item, $source, $debugSource );

  $obj->setCollectorStarted( collectorId => $id, status => $collectorOutput );

  $obj->setCollectorStatus( collectorRunId => $collectorRunID, status => $collectorOutput );

  $obj->setCollectorFinished( collectorRunId => $id );

  $obj->stripsData( $html );

  $obj->writeCVE( identifier => $identifier, digest => $digest );

  $obj->writeSourceCheck( source => $digest, comment => $comment );

  $obj->writeError(...);

  $obj->nextObject();

  $obj->getObject();

=head1 DESCRIPTION

The collecting and processing of sources, performing collection checks and almost everything else that the collector does can be found in this module.

It's possible to debug a source by setting the C<$objTaranisConfig> flag to TRUE. It's advisable to run the collector from commandline in this case, because all debug information is printed to screen.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSource )

Constructor of the C<Taranis::Collector> module. The $objTaranisConfig
is mandatory.  Returns the blessed object.

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

The SSL settings from the main XML configuration are set in $ENV.

=head2 getSourceData( $url, $source, $debugSource )

Retrieves source data. It uses C<LWP::UserAgent> to retrieve data.
In case of C<https> protocol it will first create a request using C<HTTP::Request>, to feed LWP.

It takes an URL as optional argument. If $url is defined it will retrieve the URL. If it's not defined it will use C<< $source->{fullurl} >> as URL.

    $obj->getSourceData( 'https://www.ncsc.nl/rss' );

OR

    $obj->getSourceData( undef, 'http://www.govcert.nl/rss.xml', { fullurl => 'https://www.ncsc.nl/rss', ... }, 'NCSC' );

It will return the content using C<< HTTP::Response->decoded_content() >> if LWP GET request is successful.
Also C<< $obj->{http_status_line} >> will be set to C<< HTTP::Response->status_line() >>.

If the request fails, it will return FALSE and it will write error information using C<< Taranis::Error->writeError() >>.
Also C<< $obj->{http_status_code} >> will be set to C<< HTTP::Response->code() >> and C<< $obj->{http_status_line} >> will be set to C<< HTTP::Response->status_line() >>.

In case the parser of the source is C<twitter>, the decoded content, which is a JSON string, will be decoded using C<<JSON->from_json()> and returned as such.

=head2 sourceMtbcPassed( $source, $debugSource )

Checks if it's time to collect and process the current source C<$source>.

The decision is based on:

=over

=item 1

The time when the source was last checked (from table C<checkstatus>).

=item 2

The source's C<mtbc> value: the Minimum Time Between Checks (in minutes) for this source.

=item 3

The source's C<mtbc_random_delay_max> value. If C<mtbc_random_delay_max> is non-zero, each check gets an additional delay of at most C<mtbc_random_delay_max> minutes. This can be used to make the HTTP/IMAP/... requests less predictable.

=back

Setting C<$debugSource> to true will print debug information to screen.

    $obj->sourceMtbcPassed( { sourcename => 'NCSC', mtbc => 30, digest => '0abADOA8vnaZ1dPWdvSdfA' }, 1 );

Will return TRUE or FALSE.

=head2 getStrips()

Retrieves and returns the strips configuration.

=head2 parseIdentifierPatterns( $sourceData, $configFile )

Searches the source data for all identifiers which are configured in taranis.conf.identifiers.xml.

    my $sourceData = $obj->getSourceData();

    my @certids = $obj->parseIdentifierPatterns( $sourceData );

All found identifiers are returns as a LIST.

An ARRAY of HASHES is returned.

=head2 processScreenshot( $item, $source, $debugSource )

Will make a screenshot of a webite and store the image as large object in database. Setting parameter C<$debugSource> will print debug output to stdout.

    $obj->processScreenshot( { link => 'https://www.ncsc.nl' }, { digest => '0abADOA8vnaZ1dPWdvSdfA', sourcename => 'NCSC' } );

If successful returns the large object details like C<oid> and C<fileSize>.
If unsuccessful returns FALSE.

=head2 setCollectorStarted( collectorId => $id, status => $collectorOutput )

Will add entry to table C<statistics_collector> with C<collector_id> to C<$id> and effectivly set the started timestamp.
The collector output can be added with the status parameter.

    $obj->setCollectorStarted( collectorId => 4, status => "Begin @ " . nowstring(7) . " with pid $$\n" );

If successful returns the ID of the newly added record.
If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setCollectorStatus( collectorRunId => $collectorRunID, status => $collectorOutput )

Updates the collector statistics of the collector with collector-run-ID $collectorRunID with the given collector output.  
The collector output is concatenated to status column.

    $obj->setCollectorStatus( collectorRunId => 3424, status => '### RUNNING BACKEND SCRIPTS ###' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setCollectorFinished( collectorRunId => $id )

Will set the finished timestamp of collectorrun with ID C<$id>. This ID should be obtained by the C<setCollectorStarted()> routine.

    $obj->setCollectorFinished( collectorRuntId => 54 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 stripsData( $html )

Strips off unwanted content using configured regular expressions.
The configured regular expressions can be found in taranis.conf.strips.xml and are accessed by C<< $obj->{strips} >>.

    $obj->stripsData( $html );

Returns the stripped text.

=head2 writeCVEs( $digest, @identifiers )

Writes identifiers like CVE, combined with the Assess item digest to database.

    $obj->writeCVE('YCpWzDJgrxy+aWdXzaf2lw', 'CVE-2010-0001');

=head2 writeSourceCheck( source => $digest,	comment => $comment )

Will write a timestamp of a source to the database.
It takes the source digest and a comment as parameter, where source digest is mandatory.
The argument should be supplied as C<< key => value >> pairs.

    $obj->writeSourceCheck( source => 'YCpWzDJgrxy+aWdXzaf2lw', comment => 'my comments' );

If successful returns TRUE. If unsuccessful return FALSE and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 isodd( $int )

Method checks if specified integer is even or odd.

    $obj->( 56 );

Returns TRUE if $int is odd, FALSE if it's even.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method like loadCollection().

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=back

=cut
