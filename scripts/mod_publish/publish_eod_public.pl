#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util trim_text);
use Taranis::Config;
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

my @EXPORT_OK = qw(	openDialogPublishEod_public publishEodPublic );

sub publish_eod_public_export {
	return @EXPORT_OK;
}

sub openDialogPublishEod_public {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email_public};
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
		$vars->{publicationType} = 'eod_public';
		
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

sub publishEodPublic {
	my ( %kvArgs) = @_;
	my ( $message, $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;
	my $oTaranisUsers = Taranis::Users->new( Config ); 

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eod}->{email_public};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {

		my $publicationId = $kvArgs{id};
		my $eodText = trim_text $kvArgs{eod_preview};
	
		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofday",
			"publication_endofday.publication_id" => $publicationId
		);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_begin} ) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_end} ) );
		
		my $typeId = $oTaranisPublication->getPublicationTypeId( $typeName )->{id};
	
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
	
			my $sign_pgp = (Config->{pgp_signing_endofday_public} || 'OFF') eq 'ON';
			
			my $subject = "End-of-Day - $timeframeBegin - $timeframeEnd";
			
			my ( @addresses, @individualIds, @results );
			my $sendingFailed = 0;
			my $user = $oTaranisUsers->getUser( sessionGet('userid') );
	
			my $response = $oTaranisPublish->sendPublication(
				subject => $subject,
				msg => decode_entities( $eodText ),
				attach_xml => 0,
				pub_type => 'eod_public',
				from_name => $user->{mailfrom_sender}
			);

	
			if ( $response ne "OK" ) {
				$vars->{results} = "Your message has not been sent: \n\n";

				if($sign_pgp) {
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
				$vars->{results} .= "Your message was sent to the End-of-Day public list.\n\n";
				setUserAction( action => 'publish end-of-day public', comment => "Published end-of-day public $timeframeBegin - $timeframeEnd");
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
