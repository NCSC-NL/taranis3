#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util flat trim_text);
use Taranis::SessionUtil qw(setUserAction rightOnParticularization);
use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Publication);
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use strict;

use HTML::Entities qw(decode_entities);

my @EXPORT_OK = qw(	openDialogPublishEow publishEow );

sub publish_eow_export {
	return @EXPORT_OK;
}

sub openDialogPublishEow {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $pu = Publication;
	my $pb = Taranis::Publish->new;

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eow}->{email};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {
		my $publicationId = $kvArgs{id};

		my $publication = $pu->getPublicationDetails(
			table => "publication_endofweek",
			"publication_endofweek.publication_id" => $publicationId
		);

		my @groups = @{ $pb->getConstituentGroupsForPublication( $publication->{type} ) };

		$vars->{groups} = \@groups;
		$vars->{eow_heading} = "PUBLISH -- END OF WEEK"; 
		$vars->{preview} = trim_text $publication->{contents};
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{eow_id} = $publication->{id};

		my $dialogContent = $tt->processTemplate( 'publish_eow.tt', $vars, 1 );

		return { 
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
			} 
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $tt->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}	
}

sub publishEow {
	my ( %kvArgs) = @_;
	my ( $message, $vars );

	my $tt = Taranis::Template->new;
	my $pu = Publication;
	my $pb = Taranis::Publish->new;
	my $us = Taranis::Users->new( Config );

	my $typeName = Taranis::Config->new( Config->{publication_templates} )->{eow}->{email};
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {

		my $publicationId = $kvArgs{id};
		my $eowText = trim_text $kvArgs{eow_preview};
		my @groups = flat $kvArgs{groups};

		my $publication = $pu->getPublicationDetails(
			table => "publication_endofweek",
			"publication_endofweek.publication_id" => $publicationId
		); 
	
		my $typeId = $pu->getPublicationTypeId( $typeName )->{id};
	
		if(@groups==0) {
			$vars->{message} = "End-of-week not sent: no groups were selected";
		} elsif (
			!$pu->setPublication( 
					id => $publicationId, 
					contents => $eowText, 
					status => 3, 
					published_by => sessionGet('userid'),
					published_on => nowstring(10) 
				)	
		) {
			$vars->{message} = $pu->{errmsg} if $pu->{errmsg}; 
			$vars->{message} .= " End-of-week has not been sent.";
		} else {
	
			# get those who want to receive eow emails
			my @wantEmail = @{ $pb->getIndividualsForSending( $typeId, \@groups ) };
			my $pgpSigningSetting = Config->{pgp_signing_endofweek};
			
			my $subject = "End-of-Week " . nowstring(5);
			my ( @addresses, @individualIds, @results );
			my $sendingFailed = 0;
			my $user = $us->getUser( sessionGet('userid') );
	
			for ( my $i = 0; $i < @wantEmail; $i++ ) {
				push @addresses, $wantEmail[$i]->{emailaddress};
				push @individualIds, $wantEmail[$i]->{id};

				# send eow to 10 persons at a time
				if ( ( $i % 10 == 9 ) || ( ( scalar( @wantEmail ) - $i ) <  2 )  ) {
					my $response = $pb->sendPublication(
						addresses => \@addresses,
						subject => $subject,
						msg => decode_entities( $eowText ),
						attach_xml => 0,
						pub_type => 'eow',
						from_address => $user->{mailfrom_email},
						from_name => $user->{mailfrom_sender}
					);
	
					if ( $response ne "OK" ) {
						$sendingFailed = 1;
					}
	
					my %result = ( response => $response ); 
	
					for ( my $i = 0; $i < @addresses; $i++ ) {
						push @{ $result{addresses} }, $addresses[$i];
						push @{ $result{ids} }, $individualIds[$i];
					}
						
					push @results, \%result;
	
					undef @addresses;
					undef @individualIds;
				}
			}
	
			if ( $sendingFailed eq 0 ) {
				$vars->{results} = "Your message was successfully sent to the following addresses: \n\n";
				setUserAction( action => 'publish end-of-week', comment => "Published end-of-week " . nowstring(5) );
				
				foreach my $result ( @results ) {
					foreach my $id ( @{ $result->{ids} } ) {
						$pb->setSendingResult( 
							channel => 1,
							constituent_id => $id,
							publication_id => $publicationId,
							result => $result->{response}
						);
					}
					
					foreach my $address ( @{ $result->{addresses} } ) {
						$vars->{results} .= "- " . $address . " " . $result->{response} . "\n";
					}
				}
			} else {
				$vars->{results} = "Your message has not been sent: \n\n";
	
				foreach my $result ( @results ) {
					foreach my $address ( @{ $result->{addresses} } ) {
						$vars->{results} .= "- " . $address . " " . $result->{response} . "\n";
					}
				}
		
				if ( $pgpSigningSetting =~ /^ON$/i ) {
					$eowText =~ s/^-----BEGIN.*Hash:(?:.*?)\n(.*)-----BEGIN PGP SIGNATURE-----.*$/$1/is;
					$eowText =~ s/^- //gm;
		      	}
	
				if ( !$pu->setPublication( 
						id => $publicationId, 
						contents => trim( $eowText ),
						status => 2, 
						published_by => undef,
						published_on => undef 
					)
				) {
					$vars->{message} = $pu->{errmsg} if ( $pu->{errmsg} ); 
					$vars->{message} .= " End-of-week has not been sent.";
				}	
			}
					
			$vars->{eow_heading} = "END-OF-WEEK";
				
		}
		
		my $dialogContent = $tt->processTemplate( 'publish_eow_result.tt', $vars, 1 );
			
		return { 
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
			} 
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = $tt->processTemplate( 'dialog_no_right.tt', $vars, 1 );	
		return { dialog => $dialogContent };	
	}	
}

1;
