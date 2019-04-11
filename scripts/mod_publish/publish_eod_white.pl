#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util flat trim_text);
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

my @EXPORT_OK = qw(openDialogPublishEod_white publishEodWhite);

sub publish_eod_white_export {
	return @EXPORT_OK;
}

#XXX
# The name of this method is inconsistent, because the javascript doing this
# call is bluntly constructing this call's named from a base and a capitalized
# publication type
sub openDialogPublishEod_white {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;

	my $typeName = Config->publicationTemplateName(eod => 'email_white');
	my $hasPublicationRights = rightOnParticularization($typeName);

	if ( $hasPublicationRights ) {
		my $publicationId = $kvArgs{id};

		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofday",
			"publication_endofday.publication_id" => $publicationId
		);

		my $pubTypeId = $publication->{type};
		my $groups    = $oTaranisPublish->getConstituentGroupsForPublication($pubTypeId);

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_begin}) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time($publication->{timeframe_end}) );
		  
		$vars->{eod_heading} = "END OF DAY - $timeframeBegin - $timeframeEnd"; 
		$vars->{preview} = trim_text $publication->{contents};
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{eod_id} = $publication->{id};
		$vars->{groups} = $groups;
		$vars->{publicationType} = 'eod_white';
		
		my $dialogContent = $oTaranisTemplate->processTemplate( 'publish_eod_white.tt', $vars, 1 );

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

sub publishEodWhite {
	my %kvArgs = @_;
	my ($message, $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisPublication = Publication;
	my $oTaranisPublish = Taranis::Publish->new;
	my $oTaranisUsers = Taranis::Users->new( Config ); 

	my $typeName = Config->publicationTemplateName(eod => 'email_white');

	my $hasPublicationRights = rightOnParticularization($typeName);
	if($hasPublicationRights) {

		my $publicationId = $kvArgs{id};
		my $eodText = decode_entities trim_text($kvArgs{eod_preview});
		my @groups  = flat $kvArgs{groups};
	
		my $publication = $oTaranisPublication->getPublicationDetails(
			table => "publication_endofday",
			"publication_endofday.publication_id" => $publicationId
		);

		my $pubTypeId = $publication->{type};

		my $timeframeBegin = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_begin} ) );
		my $timeframeEnd = time2str("%A %d-%m-%Y %H:%M", str2time( $publication->{timeframe_end} ) );
		
		my $userId = sessionGet('userid');

		if(@groups==0) {
			$vars->{message} = "End-of-Day White not sent: no groups were selected.";
		} elsif(
			!$oTaranisPublication->setPublication( 
					id => $publicationId, 
					contents => $eodText, 
					status => 3, 
					published_by => $userId,
					published_on => nowstring(10) 
				)	
		) {
			$vars->{message}  = "$oTaranisPublication->{errmsg}\n"
				if $oTaranisPublication->{errmsg}; 
			$vars->{message} .= "End-of-Day White has not been sent.";
		}	else {
			my $subject = "End-of-Day White - $timeframeBegin - $timeframeEnd";
			my $user    = $oTaranisUsers->getUser($userId);

            my $want_email = $oTaranisPublish->getIndividualsForSending($pubTypeId, \@groups);
			my @addresses  = map $_->{emailaddress}, @$want_email;
			my $nr_addrs   = @addresses;

			while(@addresses) {    # sent 10 at a time
				$oTaranisPublish->sendPublication(
					addresses  => [ splice @addresses, 0, 9 ],
					subject    => $subject,
					msg        => $eodText,
					attach_xml => 0,
					pub_type   => 'eod_white',
					from_name  => $user->{mailfrom_sender},
				);
			}
	
			$vars->{results} .= "The EoD was sent to $nr_addrs addresses.\n\n";
			setUserAction( action => 'publish end-of-day white', comment => "Published end-of-day white $timeframeBegin - $timeframeEnd");

			$vars->{eod_heading} = "END-OF-DAY WHITE - $timeframeBegin - $timeframeEnd";
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
