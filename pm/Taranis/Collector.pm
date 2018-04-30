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
use SQL::Abstract::More;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use Encode;
use HTML::Entities;
use JSON;
use Data::Dumper;
use POSIX qw(strftime);

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

	$self->{http_status} = 'OK';
	$source->{encoding} = undef;
	$self->{errmsg} = undef;

	my $retrieve_url = ( $url ) ? $url : $source->{fullurl};

	my $response;

	$retrieve_url = decode_entities( $retrieve_url );
	$retrieve_url =~ s/\\//g; # strip backslash from url

	say "request $retrieve_url" if ( $debugSource );
	$response = lwpRequest(get => $retrieve_url);

	undef $self->{http_status_line};
	undef $self->{http_status_code};

	if ( $response->is_success ) {
		print $response->status_line . "\n" if ( $debugSource );

		$self->{http_status_code} = $response->status_line;

		my $content = $response->decoded_content;

		if ( $source->{parser} =~ /^twitter$/i ) {
			return from_json( $content );
		}

		my $encoding = 'UTF-8'; # assume this is the default

		if ( $content ) {
			if ( defined $source->{parser} ne 'xml' && !$source->{is_image} ) {
				$content =~ s/\n//gi;
			}

			if ( $content =~ /encoding="([^"]+)"/ ) {
				$encoding = $1;
				say $encoding if ( $debugSource );
			} elsif ( $response->headers->{'content-type'} )  {
				my $content_type = $response->headers->{'content-type'};
				my @contents;
				if ( ref $content_type eq 'ARRAY' ) {
					@contents = eval { @$content_type };
				} else {
					$contents[0] = $content_type;
				}

				my @eg = eval { grep { /charset=/ } @contents };

				if ( !$@ ) {
					if ( $eg[0] && $eg[0] =~ /charset=(.*)/ ) {
						$encoding = $1;
					}
				}
			}
		}

		print "Encoding: $encoding\n" if ( $debugSource );
		$source->{encoding} = $encoding;

		return $content;
	} else {
		print $response->status_line . "\n" if ( $debugSource );

		my $error = 'Could not retrieve url ' . $retrieve_url . ' ' . $response->status_line;

		say $error if ( $debugSource );

		my $errorcode = $response->code;
		my $digest = $source->{digest};
		my $content = Dumper $response;

		my $is_image = ( exists( $source->{is_image} ) && $source->{is_image} ) ? 1 : 0;
		# only write errors for sources with digest
		# images don't have a digest, image errors are handled
		# in other subs

		if ( !$self->{no_db} && !$is_image ) {

			$self->{err}->writeError(
				digest => $digest,
				error => $error,
				error_code => $errorcode,
				content => $content,
				sourceName => $source->{sourcename}
			);
		}

		$self->{http_status_line} = $response->status_line;
		$self->{http_status_code} = $errorcode;
		return '0';
	}
}

sub itemExists($) {
	my ($self, $digest) = @_;
	   $self->{dbh}->checkIfExists({digest => $digest}, "item")
	|| $self->{dbh}->checkIfExists({digest => $digest}, "item_archive");
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
			$self->{err}->writeError(
				digest => $source->{digest},
					error => 'Failed to take a screenshot of website (1): ' . $screenshot->{errmsg},
					error_code => '019',
					sourcename => $source->{sourcename}
				);
				say "screenshot of $item->{'link'} FAILED (1)" if ( $debugSource );
		}
	} else {
		$self->{err}->writeError(
			digest => $source->{digest},
			error => 'Failed to take a screenshot of website (2): ' . $screenshot->{errmsg},
			error_code => '019',
			sourcename => $source->{sourcename}
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

sub parseIdentifierPatterns {
	my ( $self, $sourceData, $configFile ) = @_;

	my $idconfig   = $self->{config}->{identifiersconfig};
	my $identifier = Taranis::Config::XMLGeneric->new( $idconfig, "idname", "ids", undef, $configFile );
	my $identifiers = decode_entities_deep( $identifier->loadCollection() );

	my @foundIdentifiers;
	foreach my $line ( @$identifiers ) {
		while ( $sourceData =~ m/($line->{pattern})/gi ) {
			my $tempId = $1;
			if ( $line->{substitute} ) {

				$line->{substitute} =~ m/(.*?)\/(.*)/gi;
				my $search  = ( $1 ) ? $1 : "";
				my $replace = ( $2 ) ? $2 : "";
				$tempId =~ s/$search/$replace/gi;
			}

			push @foundIdentifiers, ( { identifier => $tempId, digest => $self->{item_digest} } );
		}
	}

	return @foundIdentifiers;
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

sub writeCVE {
	my ( $self, %where ) = @_;

	undef $self->{errmsg};
	undef $self->{cve_error};

	my $cve_error;
	if ( !$where{identifier} || trim( $where{identifier} ) eq '' ) {
		$cve_error .=  'EMPTY identifier FOUND for digest: ' . $where{digest} . "\n";
	}

	if ( $where{digest} eq '' ) {
		$cve_error .= 'ALERT! No digest FOUND for identifier ' . $where{identifier}. "\n";
	}

	if ( $cve_error ) {
		$self->{cve_error} = $cve_error;
		return 0;
	}

	if ( !$self->{dbh}->checkIfExists( \%where, 'identifier' ) ) {
		my ( $stmnt, @bind ) = $self->{sql}->insert( 'identifier', \%where );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	}
	return 1;
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

sub prepareTextForSaving {
	my ($self, $text) = @_;

	$text = HTML::Entities::decode( $text );

	# "NO-BREAK SPACE" aka &nbsp; is not included in \s (unless unicode rules are in effect, which are not supported
	# until Perl 5.14.)
	$text =~ s/\N{U+A0}/ /g;

	$text =~ s/\s+/ /g;

	return $text;
}

sub _getWordlistMatches {
	my ( $self, $text, $pattern ) = @_;

	my %match;
	$match{ lc($_) } = 1 for ( $text =~ /$pattern/ig );
	my @matches = keys( %match );

	return \@matches;
}

sub _getWordlistMatchesWithAND {
	my ( $self, $text, $wordsPattern1, $wordsPattern2 ) = @_;

	my ( @distinctMatches, @matches );
	foreach ( $wordsPattern1, $wordsPattern2 ) {
		my $pattern = $_;
		my %match;
		$match{ lc($_) } = 1 for ( $text =~ /$pattern/ig );

		my @matchList = keys %match;
		push @matches, \@matchList;

	}

	if ( @{ $matches[0] } && @{ $matches[1] } ) {

		my %match1 = map { $_ => 1 } @{ $matches[0] };
		my %match2 = map { $_ => 1 } @{ $matches[1] };

		foreach ( @{ $matches[1] } ) {
			if ( exists( $match1{$_} ) ) {
				delete $match1{$_};
				delete $match2{$_};
			}
		}
		if ( keys( %match1 ) && keys( %match2) ) {
			push @distinctMatches, keys( %match1 ), keys( %match2);
		}
	}
	return \@distinctMatches;
}

sub getMatchingKeywordsForSource {
	my ( $self, $source, $keywordMatchingInputList ) = @_;
	my @matchedKeywords;

	foreach my $wordlist ( @{ $source->{wordlists} } ) {
		for ( @$keywordMatchingInputList ) {
			if ( $wordlist->{and_wordlist} ) {
				push @matchedKeywords, @{ $self->_getWordlistMatchesWithAND( $_, $wordlist->{wordlist}, $wordlist->{and_wordlist} ) };
			} else {
				push @matchedKeywords, @{ $self->_getWordlistMatches( $_, $wordlist->{wordlist} ) };
			}
		}
	}
	# remove duplicate keywords
	@matchedKeywords = keys %{{ map { $_ => 1 } @matchedKeywords }};

	return @matchedKeywords;
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

  $obj->prepareTextForSaving( $text );

  $obj->processScreenshot( $item, $source, $debugSource );

  $obj->setCollectorStarted( collectorId => $id, status => $collectorOutput );

  $obj->setCollectorStatus( collectorRunId => $collectorRunID, status => $collectorOutput );

  $obj->setCollectorFinished( collectorRunId => $id );

  $obj->stripsData( $html );

  $obj->writeCVE( identifier => $identifier, digest => $digest );

  $obj->writeSourceCheck( source => $digest, comment => $comment );

  $obj->nextObject();

  $obj->getObject();

  $obj->_getWordlistMatches( $text, $pattern );

  $obj->_getWordlistMatchesWithAND( $text, $wordsPattern1, $wordsPattern2 );

=head1 DESCRIPTION

The collecting and processing of sources, performing collection checks and almost everything else that the collector does can be found in this module.

It's possible to debug a source by setting the C<$objTaranisConfig> flag to TRUE. It's advisable to run the collector from commandline in this case, because all debug information is printed to screen.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSource )

Constructor of the C<Taranis::Collector> module. The $objTaranisConfig is mandatory.

    my $obj = Taranis::Collector->new( $objTaranisConfig, 0 );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<Taranis::Config> object which can be accessed by:

    $obj->{config};

Creates a new C<Taranis::Error> object which can be accessed by:

    $obj->{err};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

The SSL settings from the main XML configuration are set in $ENV.

Returns the blessed object.

=head2 getMatchingKeywordsForSource( \%source, \@keywordMatchingInputList )

Scans text for keywords. Both paramteres are mandatory.
The C<source> parameter is an HASH reference with all source settings and associated wordlists.
The C<keywordMatchingInputList> is an ARRAY reference where each item in the list is text which can be scanned.

    $obj->getMatchingKeywordsForSource( { wordlists => [ { wordlist => '(keyword1|keyword2|etc...)', and_wordlist => '(keyword3|keyword4|etc...)' } ] } );

Returns an ARRAY with unique matching keywords.

=head2 getSourceData( $url, $source, $debugSource )

Retrieves source data. It uses C<LWP::UserAgent> to retrieve data.
In case of C<https> protocol it will first create a request using C<HTTP::Request>, to feed LWP.

It takes an URL as optional argument. If $url is defined it will retrieve the URL. If it's not defined it will use C<< $source->{fullurl} >> as URL.

    $obj->getSourceData( 'https://www.ncsc.nl/rss' );

OR

    $obj->getSourceData( undef, 'http://www.govcert.nl/rss.xml', { fullurl => 'https://www.ncsc.nl/rss', ... }, 'NCSC' );

It will return the content using C<< HTTP::Response->decoded_content() >> if LWP GET request is successful.
Also C<< $obj->{http_status_code} >> will be set to C<< HTTP::Response->status_line() >>.

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

    $obj->parseIdentifierPatterns( $sourceData );

All found identifiers are put in an ARRAY of HASHES, with keys C<identifier> ( CVE, RSHA, etc ) and C<digest> ( the item digest ).

An ARRAY of HASHES is returned.

=head2 prepareTextForSaving( $text )

Filters a string and to makes sure the returned string is UTF-8 encoded.
It also changes whitespaces that are longer than one space character into one space character. Same goes for newline characters.
The string argument is mandatory.

    $obj->prepareTextForSaving( $text );

It returns an UTF-8 string.

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

=head2 writeCVE( identifier => $identifier, digest => $digest )

Writes identifiers like CVE, combined with the Assess item digest to database.
Both identifier and digest are mandatory arguments and should be supplied as C<< key => value >> pairs.

    $obj->writeCVE( identifier => 'CVE-2010-0001', digest => 'YCpWzDJgrxy+aWdXzaf2lw' );

Returns TRUE if successful. Returns FALSE if a database error occurs and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

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

=head2 _getWordlistMatches() & _getWordlistMatchesWithAND()

Helper methods to filter out keywords from texts.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Action failed, corresponding id not found in database.>

Caused by setCollectorFinished().
You should check if parameter C<collectorRunId> has been specified.

=item *

I<Database error, please check log for info> or I<Database error. (Error cannot be logged because logging is turned off or is not configured correctly)>

Is caused by a database syntax or input error.

=back

=head1 DEPENDENCIES

CPAN modules required are B<LWP::UserAgent>, B<SQL::Abstract::More>, B<URI::Escape>, B<URI::Split>, B<Digest::MD5>, B<Encode>, B<HTML::Entities>, B<Data::Dumper> and B<JSON>.

Taranis modules required are B<Taranis>, B<Taranis::Database>, B<Taranis::Config::XMLGeneric>, B<Taranis::Error>, B<Taranis::Screenshot> and B<Taranis::Wordlist>.

=back

=cut
