# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::IMAPMail;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Data::Dumper;
use filetest 'access';
use HTML::Entities;
use Mail::IMAPClient;
use MIME::Parser;
use Encode;
use Encode::IMAPUTF7;
use XML::LibXML;
use XML::LibXML::Simple qw(XMLin);
use JSON;

use Taranis qw(:all);
use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Config;
use Taranis::Collector;
use Taranis::Damagedescription;
use Taranis::Database qw(withTransaction);
use Taranis::Publication;
use Taranis::Publication::Advisory;
use Taranis::SoftwareHardware;
use Taranis::Template;

sub new {
	my ( $class, $config, $debugSource ) = @_;

	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource )
	};

	return( bless( $self, $class ) );
}

sub collect {
	my ( $self, $source, $debugSource ) = @_;

	my $sourcename = $source->{sourcename};
	my $username = $source->{username};
	my $password = $source->{password};
	my $host = $source->{host};
	my $categoryId = $source->{categoryid};
	my $port = $source->{port};
	my $mailbox = $source->{mailbox};
	my $archiveMailbox = $source->{archive_mailbox};
	my $protocol = $source->{protocol};
	my $sourceDigest = $source->{digest};
	my $containsAdvisory = $source->{contains_advisory};
	my $useStartTLS = $source->{use_starttls};

	# for readability
	my $collector       = $self->{collector};
	my $collectorDbh    = $collector->{dbh};
	my $collectorError  = $collector->{err};
	my $collectorConfig = $collector->{config};

	my $advisoryXSD = find_config $collectorConfig->{advisory_xsd};

	my $as = Taranis::Assess->new( $collectorConfig );

	$mailbox = encode('IMAP-UTF-7', decode_entities $mailbox) if $mailbox;
	$archiveMailbox = encode('IMAP-UTF-7', decode_entities $archiveMailbox) if $archiveMailbox;

	my $imap = Mail::IMAPClient->new();

	$imap->Server( $host );
	$imap->User( $username );
	$imap->Password( $password );
	$imap->Timeout( '60' );
	$imap->Ignoresizeerrors( 1 );

	$imap->Port( $port ) if ( $port );
	$imap->Ssl( 1 ) if ( $protocol =~ /^imaps$/i );
	$imap->Starttls(1) if ( $useStartTLS );
#  $imap->Debug( 1 ) if ( $debug );

	my $mimeParser = MIME::Parser->new();
	my $mimeParserOutPutDir = tmp_path($collectorConfig->{mimeparser_outputdir});
	mkdir $mimeParserOutPutDir;

		$mimeParser->output_dir( $mimeParserOutPutDir );
		chmod 0777, $mimeParserOutPutDir;

		print nowstring(1) . " [INFO]  " . $sourcename . " Connecting to IMAP server $host\n";

		if ( !$imap->connect() ) {
			$self->{errmsg} = "Could not connect to IMAP server $host: $@\n";
			return 0;
		}

		if ( !$imap->select( $mailbox ) ) {
			$self->{errmsg} = "Could not select folder $mailbox: \"$@\"\n";
			return 0;
		}

		if ( !$imap->exists( $archiveMailbox ) ) {
			$self->{errmsg} = "Could not connect to archive folder $archiveMailbox: \"$@\"\n";
			print "ARCHIVE MAILBOX NAME: " . $archiveMailbox;
			return 0;
		}

		say "Selected Folder " . $imap->Folder() if ( $debugSource );

		my $msgcount = $imap->message_count();
		print nowstring(1) . " [INFO]  ". $sourcename . " Retrieving $msgcount message(s)\n";

		my @messagesSequenceNumbers = $imap->messages();

		# go through each message in the $mailbox
		MESSAGE:
		foreach my $msgSequenceNumber ( @messagesSequenceNumbers ) {

			my $messageId = $imap->get_header($msgSequenceNumber, "Message-Id");
			my $from = decode('MIME-Header', $imap->get_header($msgSequenceNumber, "From"));
			my $subject = decode('MIME-Header', $imap->subject($msgSequenceNumber));

			my $itemStatus = 0;
			my $messageHasValidXMLAdvisory = 0;
			my $xmlAdvisory = {};

			my $old_digest = textDigest "$messageId$subject";
			my $digest     = textDigest "$messageId$subject;$categoryId";

			if (   ! $collector->itemExists($old_digest)
				&& ! $collector->itemExists($digest)
			   ) {

				say "3.processing message nr: " . $msgSequenceNumber if ( $debugSource );

				my $title = HTML::Entities::encode($subject || "[MESSAGE HAS NO SUBJECT]");
				$from = HTML::Entities::encode($from || "[MISSING FROM IN MESSAGE]");

		    	my $message = $imap->message_string( $msgSequenceNumber );
				my $mimeEntity = eval { $message ? $mimeParser->parse_data( $message ) : undef };

				if ( $@ ) {
					$self->{errmsg} = "Error from MIME parser: " . $@;

					$collectorError->writeError(
						digest => $sourceDigest,
						error => $self->{errmsg},
						error_code => '011',
						content => $message,
						sourceName => $sourcename
					);

					say $self->{errmsg} if ( $debugSource );
					next MESSAGE;
				}

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

				# trim description of item to 500 characters or less, end with whole word
				if ( length( $description ) > 500 ) {
					$description = substr( $description, 0, 500 );
					$description =~ s/(.*)\s+.*?$/$1/;
				}

				# trim title of item to 250 characters or less, end with whole word
				if ( length( $title ) > 250 ) {
					$title = substr(  $title, 0, 250 );
					$title =~ s/(.*)\s+.*?$/$1/;
				}

				# check if the source can contain Taranis XML advisories
				if ( $containsAdvisory ) {

					if(my $attachments = $as->getAttachmentInfo( $mimeEntity, undef)) {
						my $validator;
						foreach my $attachmentName ( keys %$attachments ) {
							lc($attachments->{$attachmentName}->{filetype}) eq 'xml'
								or next;

							my $attachment = $as->getAttachment($mimeEntity, $attachmentName)
								or next;
;

							my $attachmentEntity = $mimeParser->parse_data($attachment);
							my $attachmentDecoded = decodeMimeEntity( $attachmentEntity, 1, 0 );
							$attachmentDecoded =~ s/\r//g;

							my $doc = eval { XML::LibXML->load_xml(string => $attachmentDecoded) };
							if($@) {
								$self->{errmsg} = $@;
								say $self->{errmsg} if $debugSource;

								$collectorError->writeError(
									digest => $sourceDigest,
									error => "XML parser error for XML Advisory: $self->{errmsg}",
									error_code => '015',
									content => $attachmentDecoded,
									sourceName => $sourcename
								);
								next;
							}

							$validator ||= XML::LibXML::Schema->new(location => $advisoryXSD);
							eval { $validator->validate($doc) };
							if($@) {
								$self->{errmsg} = $@;
								say $self->{errmsg} if $debugSource;

								$collectorError->writeError(
									digest => $sourceDigest,
									error => "XML Advisory validation failed: $self->{errmsg}",
									error_code => '015',
									content => $attachmentDecoded,
									sourceName => $sourcename
								);
								next;
							}

							$messageHasValidXMLAdvisory = 1;
							$itemStatus = 3; # item status 'waitingroom'

							# convert XML to perl datastructure
							$xmlAdvisory = XMLin( $attachmentDecoded, SuppressEmpty => '', KeyAttr => [] );
						}
					}
				}

				## because each message will be saved into two tables,
				## saving to database is put in a transaction
				withTransaction {
					my %insert = (
						digest => $digest,
						body => HTML::Entities::encode( $message )
					);

					# save raw email contents in table email_item
					my ( $stmnt, @bind ) = $collector->{sql}->insert( 'email_item', \%insert );

					$collectorDbh->prepare( $stmnt );
					$collectorDbh->executeWithBinds( @bind );

					my $last_insert_id = $collectorDbh->getLastInsertedId( 'email_item' );
					my $link = 'id=' . $last_insert_id;

					my $matchingKeywords = ( @matchedKeywords )
						? encode_json( \@matchedKeywords )
						: undef;

					%insert = (
						digest      => $digest,
						category    => $categoryId,
						source      => $sourcename,
						title       => $title,
						description => $description,
						'link'      => $link,
						is_mail     => 1,
						status      => $itemStatus,
						source_id	=> $source->{id},
						matching_keywords_json => $matchingKeywords
					);

					# save assess item
					( $stmnt, @bind ) = $collector->{sql}->insert( 'item', \%insert );

					$collectorDbh->prepare( $stmnt );
					$collectorDbh->executeWithBinds( @bind );
				};

				# if there's a valid Taranis XML advisory, create an analysis and link it to the assess item
				if ( $messageHasValidXMLAdvisory ) {
					say "email contains valid Taranis XML Advsiory" if ( $debugSource );
					$self->importAdvisory( $xmlAdvisory, $digest, $source, $debugSource );
				}

				if ( !$imap->move( $archiveMailbox, $msgSequenceNumber ) ) {
					$self->{errmsg} = "Message has been saved, but could not be moved to archive mailbox $archiveMailbox: " . $@;
					return 0;
				}

				$mimeParser->filer->purge;
			} else {

				if ( !$imap->move( $archiveMailbox, $msgSequenceNumber ) ) {
					$self->{errmsg} = "Message has not been saved (because a duplicate already exists in Taranis), and could not be moved to archive mailbox $archiveMailbox: " . $@;
					return 0;
				}

				print "skipping existing message number " . $msgSequenceNumber . ". Message has been moved to archive folder.\n" if ( $debugSource );
			}

			# Although inefficient, we expunge per change: a timeout may
			# stop this tasks and we do not want the knowledge about
			# processed messages to get lost.
			$imap->expunge;
		}

	$imap->disconnect() if ( $imap->IsConnected() );

	return 1;
}

sub importAdvisory {
	my ( $self, $xmlAdvisory, $itemDigest, $source, $debugSource ) = @_;

	# for readability
	my $collectorError = $self->{collector}->{err};

	my $an = Taranis::Analysis->new( $self->{collector}->{config} );
	my ( $importError, $newAnalysisId, $title, $newTitle, $basedOnAdvisoryVersion );
	my $analysisRating = $an->getAnalysisRatingFromAdvisory(
		damage => lc $xmlAdvisory->{meta_info}->{damage},
		probability => lc $xmlAdvisory->{meta_info}->{probability}
	);

	my $idString = '';
	foreach my $typeId ( %{ $xmlAdvisory->{meta_info}->{vulnerability_identifiers} } ) {
		if ( ref ( $xmlAdvisory->{meta_info}->{vulnerability_identifiers}->{$typeId}->{id} ) =~ /^ARRAY$/ ) {
			foreach my $id ( @{ $xmlAdvisory->{meta_info}->{vulnerability_identifiers}->{$typeId}->{id} } ) {
				$idString .= "$id ";
			}
		} else {
			$idString .= "$xmlAdvisory->{meta_info}->{vulnerability_identifiers}->{$typeId}->{id} ";
		}
	}

	withTransaction {
		# save new analysis
		if ( $newAnalysisId = $an->addObject(
			table => "analysis",
			title => encode_entities( $xmlAdvisory->{meta_info}->{title} ),
			comments => encode_entities( $xmlAdvisory->{content}->{abstract} ),
			idstring => $idString,
			rating => $analysisRating,
			status => 'pending'
		)) {

			# link analysis to assess item
			if ( !$an->linkToItem( $itemDigest, $newAnalysisId ) ) {
				$importError = $an->{errmsg};
				say $importError if ( $debugSource );
			}
		} else {
			$importError = $an->{errmsg};
			say $importError if ( $debugSource );
		}
	};

	if ( $source->{create_advisory} && !$importError ) {
		my $pu = Taranis::Publication->new( $self->{collector}->{config} );
		my $pa = Taranis::Publication::Advisory->new( config => $self->{collector}->{config} );
		my $sh = Taranis::SoftwareHardware->new( $self->{collector}->{config} );
		my $dd = Taranis::Damagedescription->new( $self->{collector}->{config} );
		my $tt = Taranis::Template->new( config => $self->{collector}->{config} );
		my $advisoryHandler = $source->{advisory_handler};
		my ( $advisoryId, $publicationId );
		$basedOnAdvisoryVersion = '1.00';

		my @xmlVersionHistory = ( ref ( $xmlAdvisory->{meta_info}->{version_history}->{version_instance} ) =~ /^ARRAY$/  )
			? @{ $xmlAdvisory->{meta_info}->{version_history}->{version_instance} }
			: $xmlAdvisory->{meta_info}->{version_history}->{version_instance};

		foreach my $versionInstance ( @xmlVersionHistory ) {
			$basedOnAdvisoryVersion = $versionInstance->{version} if ( $versionInstance->{version} > $basedOnAdvisoryVersion );
		}

		my $pubtempl = $self->{collector}->{config}->{publication_templates};
		my $typeName = Taranis::Config->new($pubtempl)->{advisory}->{email};
		my $typeId = $pu->getPublicationTypeId( $typeName )->{id};

		my $title = $pa->getTitleFromXMLAdvisory( $xmlAdvisory );
		my $advisoyIDDetails = $pa->getAdvisoryIDDetailsFromXMLAdvisory( $xmlAdvisory );
		my $advisoryLinks = $pa->getLinksFromXMLAdvisory( $xmlAdvisory );
		my $softwareHardwareDetails = $pa->getSoftwareHardwareFromXMLAdvisory( $xmlAdvisory );
		my $damageDescriptionDetails = $pa->getDamageDescriptionsFromXMLAdvisory( $xmlAdvisory );
		$idString =~ s/ +/, /g;
		$idString =~ s/, $//;

		# add new damage descriptions
		foreach my $xmlDamageDescription ( @{ $damageDescriptionDetails->{newDamageDescriptions} } ) {
			if ( $dd->addDamageDescription( description => $xmlDamageDescription ) ) {
				push @{ $damageDescriptionDetails->{damageDescriptionIds} }, $dd->{dbh}->getLastInsertedId('damage_description');

				$collectorError->writeError(
					digest => $source->{digest},
					error => encode( 'UTF-8', "Damage description '$xmlDamageDescription' has been added"),
					error_code => '016',
					sourceName => $source->{sourcename}
				);
			} else {
				$importError = $dd->{errmsg};
			}
		}

		# start adding advisory, etc, to database
		withTransaction {
			if (
				!$pu->addPublication(
					title => substr( $title, 0, 50 ),
					created_by => $advisoryHandler,
					type => $typeId,
					status => '0'
				)
				|| !( $publicationId = $pu->{dbh}->getLastInsertedId('publication') )
				|| !$pu->linkToPublication(
							table => 'analysis_publication',
							analysis_id => $newAnalysisId,
							publication_id => $publicationId
					)
				|| !$pu->linkToPublication(
						table => 'publication_advisory',
						publication_id => $publicationId,
						version => $advisoyIDDetails->{newAdvisoryVersion},
						govcertid => $advisoyIDDetails->{newAdvisoryDetailsId},
						title => $title,
						probability => $pa->{scale}->{$xmlAdvisory->{meta_info}->{probability} },
						damage => $pa->{scale}->{ $xmlAdvisory->{meta_info}->{damage} },
						ids => $idString,
						platforms_text => encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_platforms_text} ),
						versions_text => encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_products_versions_text} ),
						products_text => encode_entities( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{affected_products_text} ),
						hyperlinks => $advisoryLinks,
						description => encode_entities( $xmlAdvisory->{content}->{description} ),
						consequences => encode_entities( $xmlAdvisory->{content}->{consequences} ),
						update => encode_entities( $xmlAdvisory->{content}->{update_information} ),
						solution => encode_entities( $xmlAdvisory->{content}->{solution} ),
						summary => encode_entities( $xmlAdvisory->{content}->{abstract} ),
						ques_dmg_infoleak => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_infoleak},
						ques_dmg_privesc => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_privesc},
						ques_dmg_remrights => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_remrights},
						ques_dmg_codeexec => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_codeexec},
						ques_dmg_dos => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_dos},
						ques_dmg_deviation => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_dmg_deviation},
						ques_pro_solution => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_solution},
						ques_pro_expect => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_expect},
						ques_pro_exploited => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_exploited},
						ques_pro_userint => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_userint},
						ques_pro_complexity => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_complexity},
						ques_pro_credent => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_credent},
						ques_pro_access => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_access},
						ques_pro_details => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_details},
						ques_pro_exploit => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_exploit},
						ques_pro_standard => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_standard},
						ques_pro_deviation => $xmlAdvisory->{rating}->{publisher_analysis}->{ques_pro_deviation},
						based_on => $xmlAdvisory->{meta_info}->{reference_number} . " $basedOnAdvisoryVersion"
					)
			) {
				$importError = $pu->{errmsg};
			} else {
				$advisoryId = $pu->{dbh}->getLastInsertedId('publication_advisory');

				# link products to advisory
				foreach my $softwareHardware ( @{ $softwareHardwareDetails->{products} } ) {
					if (
						!$pu->linkToPublication(
							table => 'product_in_publication',
							softhard_id => $softwareHardware->{id},
							publication_id => $publicationId
						)
					) {
						$importError = $pu->{errmsg};
					}
				}

				# link platforms to advisory
				foreach my $softwareHardware ( @{ $softwareHardwareDetails->{platforms} } ) {
					if (
						!$pu->linkToPublication(
							table => 'platform_in_publication',
							softhard_id => $softwareHardware->{id},
							publication_id => $publicationId
						)
					) {
						$importError = $pu->{errmsg};
					}
				}

				# link damage descriptions to advisory
				foreach my $damageDescriptionId ( @{ $damageDescriptionDetails->{damageDescriptionIds} } ) {
					if (
						!$pu->linkToPublication(
							table => 'advisory_damage',
							damage_id => $damageDescriptionId,
							advisory_id => $advisoryId
						)
					) {
						$importError = $pu->{errmsg};
					}
				}
			}

			# update replacedby_id of previous version advisory with new publication id
			if ( $advisoyIDDetails->{publicationPreviousVersionId} && !$pu->setPublication( id => $advisoyIDDetails->{publicationPreviousVersionId}, replacedby_id => $publicationId ) ) {
				$importError = $pu->{errmsg};
			}

			# log software/hardware which could not be linked to advisory
			foreach my $shProblem ( @{ $softwareHardwareDetails->{importProblems} } ) {
				$collectorError->writeError(
					digest => $source->{digest},
					error => $shProblem,
					error_code => '017',
					sourceName => $source->{sourcename},
					reference_id => $publicationId
				);
			}
		};

		if ( !$importError ) {
			my $advisoryType = ( $advisoyIDDetails->{newAdvisoryVersion} > 1 ) ? 'update' : 'email';
			my $previewText = $tt->processPreviewTemplate( 'advisory', $advisoryType, $advisoryId, $publicationId, 71 );
			my $xmlText = $pu->processPreviewXml( $advisoryId );

			# set contents of new publication
			if ( !$pu->setPublication( id => $publicationId, contents => $previewText, xml_contents => $xmlText ) ) {
				$importError = $pu->{errmsg};
			}

			$previewText = encode_entities( $previewText );
			my $publisher = encode_entities( $xmlAdvisory->{meta_info}->{issuer} );
			my $referenceNumberNamingPart = ( $xmlAdvisory->{meta_info}->{reference_number} =~ /^(.*?)-\d{4}-\d+$/ )[0];
			my $referencesToPublisher = "";

			foreach my $lineWithReference ( $previewText =~ /\n(.*?$referenceNumberNamingPart.*?\n)/gmi, $previewText =~ /\n(.*?$publisher.*?\n)/gmi ) {
				$lineWithReference =~ s/^\s*(.*?)\s*$/$1/;

				if ( $referencesToPublisher !~ $lineWithReference ) {
					$referencesToPublisher .= $lineWithReference . "\n";
					$previewText =~ s/(\Q$lineWithReference\E)/<span class="mark-text">$1<\/span>/;
				}
			}

			$previewText =~ s/($referenceNumberNamingPart|$publisher)/<span class="bold">$1<\/span>/gi;

			if ( $referencesToPublisher ) {
				$collectorError->writeError(
					digest => $source->{digest},
					error => "References to publisher found in advisory during advisory import",
					error_code => '018',
					content => $previewText,
					sourceName => $source->{sourcename},
					reference_id => $publicationId
				);
			}
		}

		$newTitle = "$advisoyIDDetails->{newAdvisoryDetailsId} [v$advisoyIDDetails->{newAdvisoryVersion}] $xmlAdvisory->{meta_info}->{title}";
	}

	if ( $importError ) {
		$collectorError->writeError(
			digest => $source->{digest},
			error => "Advisory import error: $importError",
			error_code => '015',
			content => Dumper $xmlAdvisory,
			sourceName => $source->{sourcename}
		);
		return 0;
	} else {

		my $notificationText = ( $source->{create_advisory} )
			? encode( 'UTF-8', "Imported advisory '$xmlAdvisory->{meta_info}->{reference_number} [v$basedOnAdvisoryVersion]' as pending advisory '$newTitle'")
			: encode( 'UTF-8', "Imported advisory '$xmlAdvisory->{meta_info}->{title}' as pending analysis AN-" . substr( $newAnalysisId, 0,4) . '-' .substr( $newAnalysisId, 3,4) );

		$collectorError->writeError(
			digest => $source->{digest},
			error => $notificationText,
			error_code => '016',
			sourceName => $source->{sourcename}
		);
		return 1;
	}
}

1;

=head1 NAME

Taranis::Collector::IMAPMail - Mail Collector for IMAP

=head1 SYNOPSIS

  use Taranis::Collector::IMAPMail;

  my $obj = Taranis::Collector::IMAPMail->new( $oTaranisConfig, $debugSource );

  $obj->collect( $source, $debugSourceName );

  $obj->importAdvisory( $xmlAdvisory, $itemDigest, $source, $debugSource );

=head1 DESCRIPTION

Collector for IMAP mail sources.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSourceName )

Constructor of the C<Taranis::Collector::IMAPMail> module. An object instance of Taranis::Config should be passed as first argument.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::IMAPMail->new( $objTaranisConfig, 'NCSC' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $source, $debugSourceName )

Method for retrieval of IMAP and IMAPS sources. It uses the source settings in C<$source> for credentials, server info and mailbox names.

The optional C<$debugSourceName> can be set to print debug information to screen.

    $obj->collect( { digest => 'MJH342kAS', sourcename => 'NCSC', mailbox => 'inbox', ... }, 'NCSC' );

The method will first try to make a connection then select the mailbox and looks if the archive mailbox exists. It uses C<Mail::IMAPClient> for this.
It will return FALSE if one of these checks fails.

Next step is checking each message if it's already in Taranis.
If it doesn't exist, it will retrieve the complete message and parse it using C<< MIME::Parser->parse_data() >>.
If this fails an error wil be written using C<< Taranis::Error->writeError() >> with C<error_code> 011.
When parsing of message is successful the body text will first be decoded using C<< Taranis->decodeMimeEntity() >> and secondly encoded using C<< HTML::Entities::encode >>.

A summary of the message is saved to table C<item> and the complete message is saved to C<email_item>.

Finally the message will be moved from mailbox to the archive mailbox.

If any of the above fails the method will return FALSE and set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 importAdvisory( $xmlAdvisory, $itemDigest, $source, $debugSource )

Imports a Taranis XML advisory. $xmlAdvisory is an XML::Simple object and $source is an HASH reference containing source settings.

    $obj->importAdvisory( XML::Simple, 'ekj2o3i49', { advisory_handler => 'some_username', create_advisory => 1, sourcename => 'NCSC', ... }, 'NCSC' );

If successful returns TRUE. If unsuccessful returns FALSE.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<No valid writable Mime Parser output directory specified in config.>

Caused by collect() when there C<mimeparser_outputdir> setting in Taranis configuration is not set or not writable.
You should check C<mimeparser_outputdir> setting in Taranis or collector configuration file.

=item *

I<Could not connect to IMAP server XXX: '...'>

Caused by collect() when connecting to the set server is not possible.
You should check C<host> and C<port> settings of source.

=item *

I<Could not select folder XXX: '...'>

Caused by collect() when try to open the specified IMAP mail folder.
You should check C<mailbox> settings of source.

=item *

I<Could not connect to archive folder XXX: '...'>

Caused by collect() when checking if the specified IMAP mail folder exists.
You should check C<archive mailbox> settings of source.

=item *

I<Error from MIME parser: '...'>

Caused by collect() when parsing the MIME parts of the email. Exact error text is from the perl module C<< MIME::Parser->parse_data() >>
You should check the email that is causing the error and probably delete it.

=item *

I<Could not create an XML parser for XML Advisory, please check advisory_xsd setting in Taranis configuration.>

Caused by collect() when trying to parse an XML advisory.
You should check C<advisory_xsd> setting in Taranis or collector configuration file..

=item *

I<Message has been saved, but could not be moved to archive mailbox XXX: '...'>

Caused by collect() when trying move a processed email to the archive mailbox.
You should check C<archive mailbox> settings of source as well as the mailbox settings on the mailserver.

=item *

I<Message has not been saved, (because a duplicate already exists in Taranis) and could not be moved to archive mailbox XXX: '...'>

Caused by collect() when trying move a processed email to the archive mailbox.
You should check C<archive mailbox> settings of source as well as the mailbox settings on the mailserver.

=back

=cut
