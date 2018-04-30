#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util trim_text);
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction rightOnParticularization);
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Template;
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use strict;

use Date::Format qw( time2str );
use Date::Parse;
use HTML::Entities qw(decode_entities);

my @EXPORT_OK = qw(	openDialogPublishEod publishEod );

sub publish_eod_export {
	return @EXPORT_OK;
}

sub openDialogPublishEod {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {
		my $publicationId = $kvArgs{id};

		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofday",
			"publication_endofday.publication_id" => $publicationId
		);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_begin}) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_end}) );

		$vars->{eod_heading} = "END OF DAY - $timeframeBegin - $timeframeEnd";
		$vars->{preview} = trim_text $publication->{contents};
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{eod_id} = $publication->{id};
		$vars->{publicationType} = 'eod';

		my $dialogContent = $oTaranisTemplate->processTemplate( 'publish_eod.tt', $vars, 1 );

		return {
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub publishEod {
	my ( %kvArgs) = @_;
	my ( $message, $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;
	my $oTaranisUsers = Taranis::Users->new(Config);

	my $templConfig = Taranis::Config->new(Config->{publication_templates});
	my $typeName     = $templConfig->{eod}{email};

	my $hasPublicationRights = rightOnParticularization($typeName);

	if ( $hasPublicationRights ) {

		my $publicationId = $kvArgs{id};
		my $eodText = trim_text $kvArgs{eod_preview};

		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofday",
			"publication_endofday.publication_id" => $publicationId
		);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_begin} ) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_end} ) );

		# We may send both to the confidential as the public list only
		# when there is no amber and there is no signing (templates may differ)
		my $sign_with_pgp = (Config->{pgp_signing_endofday} || 'OFF') eq 'ON';
		my $amber_text = $publication->{tlp_amber} || '';
		my $sendEodPublicSeparately = $sign_with_pgp || $amber_text =~ /\S/;

		# EodWhite can be disabled; other publications wait for T4
		my $sendEodWhite = (Config->{publish_eod_white} || 'OFF') eq 'ON';

		my $userId = sessionGet('userid');

		if (
			!$oTaranisPublication->setPublication(
					id => $publicationId,
					contents => $eodText,
					status => 3,
					published_by => $userId,
					published_on => nowstring(10)
				)
		) {
			$vars->{message} = $oTaranisPublication->{errmsg} if ( $oTaranisPublication->{errmsg} );
			$vars->{message} .= " End-of-day has not been sent.";
		}	else {

			my $subject = "End-of-Day - $timeframeBegin - $timeframeEnd";

			my ( @addresses, @individualIds, @results );
			my $sendingFailed = 0;
			my $user = $oTaranisUsers->getUser($userId);

			my $response = $oTaranisPublish->sendPublication(
				subject => $subject,
				msg => decode_entities( $eodText ),
				attach_xml => 0,
				pub_type => 'eod',
				from_name => $user->{mailfrom_sender}
			);

			if ( $response ne "OK" ) {
				$vars->{results} = "Your message has not been sent: \n\n";

				if($sign_with_pgp) {
					$eodText =~ s/^-----BEGIN.*Hash:(?:.*?)\n(.*)-----BEGIN PGP SIGNATURE-----.*$/$1/is;
					$eodText =~ s/^- //gm;
		      	}

				if ( !$oTaranisPublication->setPublication(
						id => $publicationId,
						contents => trim( $eodText ),
						status => 2,
						published_by => undef,
						published_on => undef
					)
				) {
					$vars->{message} = $oTaranisPublication->{errmsg} if ( $oTaranisPublication->{errmsg} );
					$vars->{message} .= " End-of-day has not been sent.";
				}

			} else {
				$vars->{results} .= "Your message was sent to the End-of-Day confidential list.\n\n";

				my $typeNameEodPublic = $templConfig->{eod}{email_public};
				my $typeIdEodPublic   = $oTaranisPublication->getPublicationTypeId($typeNameEodPublic)->{id};
				my ($publicationIdEodPublic, $eodIdPublic);

				my $typeNameEodWhite  = $templConfig->{eod}{email_white};
				my $typeIdEodWhite    = $oTaranisPublication->getPublicationTypeId($typeNameEodWhite)->{id};
				my ($publicationIdEodWhite,  $eodIdWhite);

				my $dbh = $oTaranisPublication->{dbh};
				withTransaction {
					$oTaranisPublication->addPublication(
						title       => "TLP:AMBER End-of-Day",
						created_by  => $userId,
						type        => $typeIdEodPublic,
						approved_on => nowstring(10),
						approved_by => $userId,
						status      => 2,
					);
					$publicationIdEodPublic = $dbh->getLastInsertedId("publication");

					$oTaranisPublication->addPublication(
						title       => "TLP:WHITE End-of-Day",
						created_by  => $userId,
						type        => $typeIdEodWhite,
						approved_on => nowstring(10),
						approved_by => $userId,
						status      => 2,
					);
					$publicationIdEodWhite = $dbh->getLastInsertedId("publication");

					my @fields = map +($_ => $publication->{$_}), qw/
						handler first_co_handler second_co_handler
						timeframe_begin timeframe_end general_info
						vulnerabilities_threats published_advisories
						linked_items incident_info community_news
						media_exposure/;

					$oTaranisPublication->linkToPublication(
						table => "publication_endofday",
						publication_id => $publicationIdEodPublic,
						@fields,
					);
					$eodIdPublic = $dbh->getLastInsertedId("publication_endofday");

					$oTaranisPublication->linkToPublication(
						table => "publication_endofday",
						publication_id => $publicationIdEodWhite,
						@fields,
					);
					$eodIdWhite = $dbh->getLastInsertedId("publication_endofday");
				};

				# EoD White is always sent seperately
				if($sendEodWhite) {
					my $eodWhiteTxt = $oTaranisTemplate->processPreviewTemplate(
						"eod", "email_white", $eodIdWhite,
						$publicationIdEodWhite, 0,
					);

					$oTaranisPublication->setPublication(
							id => $publicationIdEodWhite,
							contents => $eodWhiteTxt,
					);
					$vars->{results} .= "An End-of-Day publication for the white list has been created.\n\n";
				}

				my $eodPublicTxt = $oTaranisTemplate->processPreviewTemplate(
					"eod", "email_public", $eodIdPublic,
					$publicationIdEodPublic, 0
				);

				if($sendEodPublicSeparately) {
					$oTaranisPublication->setPublication(
							id => $publicationIdEodPublic,
							contents => $eodPublicTxt,
					);

					$vars->{results} .= "An End-of-Day publication for the public list has been created.\n\n";
					setUserAction( action => 'publish end-of-day', comment => "Published end-of-day confidential $timeframeBegin - $timeframeEnd");
				} else {
					$oTaranisPublish->sendPublication(
						subject    => $subject,
						msg        => trim( decode_entities($eodPublicTxt)),
						attach_xml => 0,
						pub_type   => 'eod_public',
						from_name  => $user->{mailfrom_sender},
					);

					$oTaranisPublication->setPublication(
						id => $publicationIdEodPublic,
						contents     => trim($eodPublicTxt),
						status       => 3,
						published_by => $userId,
						published_on => nowstring(10),
					);

					$vars->{results} .= "Your message was sent to the End-of-Day public lists.\n\n";
					setUserAction( action => 'publish end-of-day', comment => "Published end-of-day public $timeframeBegin - $timeframeEnd");
				}
			}

			$vars->{eod_heading} = "END-OF-DAY - $timeframeBegin - $timeframeEnd";
		}

		my $dialogContent = $oTaranisTemplate->processTemplate( 'publish_eod_result.tt', $vars, 1 );

		return {
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $oTaranisTemplate->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}
1;
