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

my @EXPORT_OK = qw(	openDialogPublishEos publishEos );

sub publish_eos_export {
	return @EXPORT_OK;
}

sub openDialogPublishEos {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eos}->{email};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {
		my $publicationId = $kvArgs{id};

		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofshift",
			"publication_endofshift.publication_id" => $publicationId
		);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_begin}) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_end}) );
		  
		$vars->{eos_heading} = "END OF SHIFT - $timeframeBegin - $timeframeEnd"; 
		$vars->{preview} = trim_text $publication->{contents};
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{eos_id} = $publication->{id};
		$vars->{publicationType} = 'eos';
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'publish_eos.tt', $vars, 1 );

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

sub publishEos {
	my ( %kvArgs) = @_;
	my ( $message, $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;
	my $oTaranisUsers = Taranis::Users->new( Config );

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eos}->{email};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {

		my $publicationId = $kvArgs{id};
		my $eosText = trim_text $kvArgs{eos_preview};
	
		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofshift",
			"publication_endofshift.publication_id" => $publicationId
		);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_begin} ) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_end} ) );
		
		my $userId = sessionGet('userid');
		
		if ( 
			!$oTaranisPublication->setPublication( 
					id => $publicationId, 
					contents => $eosText, 
					status => 3, 
					published_by => $userId,
					published_on => nowstring(10) 
				)	
		) {
			$vars->{message} = $oTaranisPublication->{errmsg} if ( $oTaranisPublication->{errmsg} ); 
			$vars->{message} .= " End-of-shift has not been sent.";
		}	else {
	
			my $pgpSigningSetting = Config->{pgp_signing_endofshift};
			
			my $subject = "End-of-Shift - $timeframeBegin - $timeframeEnd";
			
			my $sendingFailed = 0;
			my $user = $oTaranisUsers->getUser( sessionGet('userid') );
	
			my $response = $oTaranisPublish->sendPublication(
				subject => $subject,
				msg => decode_entities( $eosText ),
				attach_xml => 0,
				pub_type => 'eos',
				from_name => $user->{mailfrom_sender}
			);

			if ( $response ne "OK" ) {
				$vars->{results} = "Your message has not been sent: \n\n";

				if ( $pgpSigningSetting =~ /^ON$/i ) {
					$eosText =~ s/^-----BEGIN.*Hash:(?:.*?)\n(.*)-----BEGIN PGP SIGNATURE-----.*$/$1/is;
					$eosText =~ s/^- //gm;
		      	}
	
				if ( !$oTaranisPublication->setPublication( 
						id => $publicationId, 
						contents => trim( $eosText ),
						status => 2, 
						published_by => undef,
						published_on => undef 
					)
				) {
					$vars->{message} = $oTaranisPublication->{errmsg} if ( $oTaranisPublication->{errmsg} ); 
					$vars->{message} .= " End-of-shift has not been sent.";
				}	

			} else {
				$vars->{results} .= "Your message was successfully sent to the End-of-Shift list. \n\n";
				setUserAction( action => 'publish end-of-shift', comment => "Published end-of-shift" . nowstring(5) );
			}

			$vars->{eos_heading} = "END-OF-SHIFT - $timeframeBegin - $timeframeEnd";
		}
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'publish_eos_result.tt', $vars, 1 );
			
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
