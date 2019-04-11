# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::POP3Mail;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Encode;
use filetest 'access';
use HTML::Entities;
use Mail::POP3Client;
use MIME::Parser;
use Taranis qw(:all);
use Taranis::Collector;
use Taranis::Database qw(withTransaction);


sub new {
	my ( $class, $config, $debugSource ) = @_;
	
	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource )
	};
	
	return( bless( $self, $class ) );
}

sub collect {
	my ( $self, $source, $debugSource ) = @_;

	my $sourceDigest = $source->{digest};
	my $sourcename = $source->{sourcename};
	my $username = $source->{username};
	my $password = $source->{password};
	my $host = $source->{host};
	my $categoryId = $source->{categoryid};
	my $port = $source->{port};
	my $protocol = $source->{protocol};
	my $deleteMail = $source->{delete_mail};
	
	my $ssl = ( $protocol =~ /^pop3s$/i ) ? 1 : 0;

	my $pop3 = Mail::POP3Client->new( 
		HOST => $host,
		USESSL => $ssl,
		USER => $username,
		PASS => $password
	);

	$pop3->Host( $host );
	$pop3->User( $username );
	$pop3->Password( $password );
	$pop3->Port( $port ) if ( $port );

	my $mimeParser = MIME::Parser->new();
	my $mimeParserOutPutDir = tmp_path($self->{collector}->{config}->{mimeparser_outputdir});
	-d $mimeParserOutPutDir or mkdir $mimeParserOutPutDir or die "$mimeParserOutPutDir: $!";

	$mimeParser->output_dir( $mimeParserOutPutDir );
	chmod 0777, $mimeParserOutPutDir;

	print nowstring(1) . " [INFO]  " . $sourcename . " connecting to POP3 server $host\n";
	
	if ( !$pop3->Connect() ) {
		$self->{errmsg} = "Could not connect to POP3 server $host: $@\n";
		return 0;
	}

	my $msgcount = $pop3->Count();
	print nowstring(1) . " [INFO]  " . $sourcename . " Retrieving $msgcount message(s)\n";

	MESSAGE:
	for ( my $msgSequenceNumber = 1; $msgSequenceNumber <= $msgcount; $msgSequenceNumber++ ) {
		my $message = $pop3->Retrieve( $msgSequenceNumber );
		
		my ( $subject, $messageId, $from );
		
		foreach ( $pop3->Head( $msgSequenceNumber ) ) {
			/^(Subject):\s+/i and $subject = decode('MIME-Header', $_);
			/^(message-id):\s+/i and $messageId = decode('MIME-Header', $_);
			/^(from):\s+/i and $from = decode('MIME-Header', $_);
		}

		my $collector = $self->{collector};
		my $mimeEntity = eval { $message ? $mimeParser->parse_data($message) : undef };
		if ( $@ ) {
			$self->{errmsg} = "Error from MIME parser: " . $@;

			$collector->writeError(
				source     => $source,
				error      => $self->{errmsg},
				error_code => '011',
				content    => $message,
			);

			say $self->{errmsg} if ( $debugSource );
			next MESSAGE;
		}

		my $old_digest = textDigest "$messageId$subject";
		my $digest     = textDigest "$messageId$subject;$categoryId";
		
		if($collector->itemExists($old_digest) || $collector->itemExists($digest)) {
			print "skipping existing message nr: $msgSequenceNumber\n"
				if $debugSource;
		} else {

			say "processing message nr: $msgSequenceNumber" if $debugSource;

			my $itemStatus = 0;
			my $title = HTML::Entities::encode($subject || "[MESSAGE HAS NO SUBJECT]");
			$from = HTML::Entities::encode($from || "[NO HEADER 'FROM' IN MESSAGE]");

			my $body;
			$body = HTML::Entities::encode( decodeMimeEntity( $mimeEntity, 1, 1 ) );
			$body = "FROM: " . $from . " \n" . $body;

			my $description = trim( $body );
			
			my @matchedKeywords;
			if ( $source->{use_keyword_matching} ) {
				if ( $source->{wordlists} ) {
					@matchedKeywords = $collector->getMatchingKeywordsForSource( $source, [ $title, $description ] );
					$itemStatus = 1 if ( !@matchedKeywords );
					print ">matched keywords: @matchedKeywords\n" if $debugSource;						
				} else {
					# if no wordlists are configured set all items to 'read' status
					$itemStatus = 1;
				}
			}
			
			if ( length( $description ) > 500 ) {
				$description = substr( $description, 0, 500 );
				$description =~ s/(.*)\s+.*?$/$1/;
			}

			if ( length( $title ) > 250 ) {
				$title = substr(  $title, 0, 250 );
				$title =~ s/(.*)\s+.*?$/$1/;
			}

			my $dbh = $collector->{dbh};
			withTransaction {
				my %insert = (
					digest => $digest,
					body => HTML::Entities::encode( $message )
				);

				my ( $stmnt, @bind ) = $collector->{sql}->insert( 'email_item', \%insert );

				$dbh->prepare( $stmnt );
				$dbh->executeWithBinds( @bind );

				my $last_insert_id = $dbh->getLastInsertedId( 'email_item' );
				my $link = 'id=' . $last_insert_id;

				my $matchingKeywords = ( @matchedKeywords )
					? to_json( @matchedKeywords )
					: undef;

				%insert = (
					digest => $digest,
					category => $categoryId,
					source => $sourcename,
					title => $title,
					description => $description,
					'link' => $link,
					is_mail => 1,
					status => $itemStatus,
					source_id => $source->{id},
					matching_keywords_json => $matchingKeywords
				);

				( $stmnt, @bind ) = $collector->{sql}->insert( 'item', \%insert );

				$dbh->prepare( $stmnt );
				$dbh->executeWithBinds( @bind );
			};

			if ( defined( $dbh->{db_error_msg} ) ) {
				$self->{errmsg} = $dbh->{db_error_msg} . "\n";
				return 0;
			}
		}

		$pop3->Delete( $msgSequenceNumber ) if ( $deleteMail );
		$mimeParser->filer->purge;
	}

	$pop3->Close();

	return 1;
}

1;

=head1 NAME

Taranis::Collector::POP4Mail - Mail Collector for POP3

=head1 SYNOPSIS

  use Taranis::Collector::POP3Mail;

  my $obj = Taranis::Collector::POP3Mail->new( $oTaranisConfig, $debugSource );

  $obj->collect( $source, $debugSourceName );

=head1 DESCRIPTION

Collector for POP3 mail sources.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSourceName )

Constructor of the C<Taranis::Collector::POP3Mail> module. An object instance of Taranis::Config should be passed as first argument.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::POP3Mail->new( $objTaranisConfig, 'NCSC' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $source, $debugSourceName );

Will collect from POP3 mailbox. Parameter $source is mandatory.
$source is a HASH reference with all the necessary source settings.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    $obj->collect( { digest => 'MJH342kAS', sourcename => 'NCSC', username => 'myusername', ... }, 'NCSC' );

If successful returns TRUE. If unsuccessful it will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<No valid writable Mime Parser output directory specified in config.>

Caused by collect() when there C<mimeparser_outputdir> setting in Taranis configuration is not set or not writable.
You should check C<mimeparser_outputdir> setting in Taranis or collector configuration file. 

=item *

I<Could not connect to POP3 server XXX: '...'>

Caused by collect() when connecting to the set server is not possible.
You should check C<host> and C<port> settings of source. 

=item *

I<Error from MIME parser: '...'>

Caused by collect() when parsing the MIME parts of the email. Exact error text is from the perl module C<< MIME::Parser->parse_data() >>
You should check the email that is causing the error and probably delete it.

=back

=cut
