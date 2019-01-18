#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:util flat trim_text);
use Taranis::SessionUtil qw(setUserAction rightOnParticularization);
use Taranis::Template;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(CGI Config Constituent_Group Database Publication Publish Template);
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Constituent_Group;
use Taranis::CallingList qw(getCallingList createCallingList);
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use Encode;
use strict;

use CGI::Simple;
use Data::Dumper;
use HTML::Entities qw(decode_entities);

my @EXPORT_OK = qw(
	openDialogPublishForward getConstituentListForward closeForwardPublication
	publishForward printCallingListForward saveCallingListForward
);

sub publish_forward_export {
	return @EXPORT_OK;
}

sub openDialogPublishForward {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $advisoryId );

	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	my $hasPublicationRights = rightOnParticularization($typeName);

	my $lockOk = 0;

	if ( $hasPublicationRights ) {
		my $publicationId = $kvArgs{id};

		my $checkProducts = 0;
		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_forward",
			"publication_advisory_forward.publication_id" => $publicationId
		);

		# lock the advisory
		my $advisoryId = ( $publication->{govcertid} =~ /.*X+$/i ) ? Publish->getNextAdvisoryId() : $publication->{govcertid};
		my $publicationType = ( $publication->{version} > 1.00 ) ? "forward_update" : "forward";

		my $userId = sessionGet('userid');

		# check if advisory is locked
		if ( Publish->{dbh}->checkIfExists( { status => 4, type => $publication->{type} }, "publication" ) ) {
			$vars->{message} = "Advisory is locked";
			$lockOk = 0;

		} else {

			withTransaction {
				Publication->setPublication( id => $publicationId, status => 4, published_on => nowstring(9), opened_by => $userId );
				Publication->setPublicationDetails( table => 'publication_advisory_forward', where => { publication_id => $publicationId }, 'govcertid' => $advisoryId );
				my $publicationText = Template->processPreviewTemplate( 'advisory', $publicationType, $publication->{id}, $publicationId, 71 );
				Publication->setPublication( id => $publicationId, contents => $publicationText );
				$lockOk = 1;
			};

			Publication->getLinkedToPublication(
				join_table_1 => { product_in_publication => "softhard_id" },
				join_table_2 => { software_hardware => "id" },
				"pu.id" => $publicationId
			);

			while ( Publication->nextObject() ) {
				$checkProducts = 1;
				push @{ $vars->{ products } }, Publication->getObject();
			}

			Publication->getLinkedToPublication(
				join_table_1 => { platform_in_publication => "softhard_id" },
				join_table_2 => { software_hardware => "id" },
				"pu.id" => $publicationId
			);

			while ( Publication->nextObject() ) {
				push @{ $vars->{ platforms } }, Publication->getObject();
			}

			$vars->{check_products} = $checkProducts;
			$vars->{publication_id} = $publication->{publication_id};
			$vars->{advisory_id} = $publication->{id};

			$vars->{advisory_heading} = "PUBLISH -- " . $advisoryId . " [v" . $publication->{version} . "]";
		}

		my $dialogContent = Template->processTemplate( 'publish_sh_selection.tt', $vars, 1 );

		return {
			dialog => $dialogContent,
			params => {
				lockOk => $lockOk,
				publicationId => $publicationId,
				advisoryId => $advisoryId
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub getConstituentListForward {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $publicationId );

	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	my $hasPublicationRights = rightOnParticularization( $typeName );

	if ( $hasPublicationRights ) {
		$publicationId = $kvArgs{id};
		my $selectionType = $kvArgs{selectionType};

		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_forward",
			"publication_advisory_forward.publication_id" => $publicationId
		);

		my @groups = @{ Publish->getConstituentGroupsForPublication( $publication->{type} ) };

		my @selectedGroups;

		if (uc $selectionType eq 'OR') {
			my @shList = flat $kvArgs{sh};
			@selectedGroups = @{ Publish->getConstituentGroupsByWares(@shList) };
		} else {

			my $json_andSelection = $kvArgs{shList};
			$json_andSelection =~ s/&quot;/"/g;

			my $selections = from_json( $json_andSelection );

			@selectedGroups = @{ Publish->getConstituentGroupsByWareCombinations( $selections ) };
		}

		GROUP_LOOP:
		foreach my $group ( @groups ) {
			foreach my $id ( @selectedGroups ) {
				if ( $group->{id} eq $id ) {
					$group->{selected} = 1;
					next GROUP_LOOP;
				} else {
					$group->{selected} = 0;
				}
			}
		}

		$vars->{groups} = \@groups;
		$vars->{advisory_heading} = "PUBLISH -- " . $publication->{govcertid} . " [v" . $publication->{version} . "]";
		$vars->{preview} = trim_text $publication->{contents};
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{attachments} = Publication->getPublicationAttachments( publication_id => $publication->{publication_id} );

		my $isHighHigh = ( $publication->{damage} =~ /^1$/ && $publication->{probability} =~ /^1$/ ) ? 1 : 0;

		my $dialogContent = Template->processTemplate( 'publish_advisory.tt', $vars, 1 );
		return {
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
				isHighHigh => $isHighHigh
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub closeForwardPublication {
	my ( %kvArgs) = @_;
	my ( $message, $govcertId, $publicationType );

	my $releaseOk = 0;
	my $publicationId = $kvArgs{id};

	my $userId = sessionGet('userid');

	my $isAdmin = getUserRights(
		entitlement => "admin_generic",
		username => $userId
	)->{admin_generic}->{write_right};

	my $advisory = Publication->getPublicationDetails(
		table => "publication_advisory_forward",
		"publication_advisory_forward.publication_id" => $publicationId
	);

	if ( ( defined $kvArgs{releaseLock} && $isAdmin ) || ( $advisory->{opened_by} =~ $userId ) ) {
		my ( $status, $approvedBy );
		if ( exists( $kvArgs{setToPending} ) ) {
			$status = 0;
			$approvedBy = undef;
		} else {
			$status = 2;
			$approvedBy = $advisory->{approved_by};
		}

		if ( $advisory->{version} > 1.00 ) {
			$govcertId = $advisory->{govcertid};
			$publicationType = 'forward_update';
		} else {
			my $advisoryPrefix = Config->{advisory_prefix};
			my $advisoryIdLength = Config->{advisory_id_length};

			my $x = "";
			for ( my $i = 1; $i <= $advisoryIdLength; $i++ ) { $x .= "X"; }
			$govcertId = $advisoryPrefix . "-" . nowstring(6) . "-" . $x;
			$publicationType = 'forward';
		}

		withTransaction {
			if ( $publicationId =~ /^\d+$/
				&& Publication->setPublication( id => $publicationId, status => $status, published_on => undef, published_by => undef, opened_by => undef, approved_by => $approvedBy )
				&& Publication->setPublicationDetails( table => "publication_advisory_forward", where => { id => $advisory->{id} }, govcertid => $govcertId )
			) {
				my $advisoryText = Template->processPreviewTemplate( "advisory", $publicationType, $advisory->{id}, $publicationId, 71 );

				if ( Publication->setPublication( id => $publicationId, contents => $advisoryText ) ) {
					$releaseOk = 1;

					if ( $status =~ /^0$/ ) {
						setUserAction( action => 'change advisory status', comment => "Changed advisory '" . $advisory->{govcertid} . " " . $advisory->{version_str} . " " . $advisory->{pub_title} . "' from 'Approved' to 'Pending'");
					}

				} else {
					$message = "lock_release_failed";
				}
			} else {
				$message = "lock_release_failed";
			}
		};
	} else {
		$message = 'Only admin users can unlock advisories!';
	}

	return {
		params => {
			message => $message,
			releaseOk => $releaseOk,
			publicationId => $publicationId,
			pub_type => 'forward'
		}
	};
}

sub publishForward {
	my ( %kvArgs) = @_;
	my ( $message, $vars );

	my $typeName = Config->publicationTemplateName(advisory => 'forward');
	my $hasPublicationRights = rightOnParticularization($typeName);

	if ( $hasPublicationRights ) {

		my $publicationId = $kvArgs{id};
		my $advisoryText  = trim_text $kvArgs{advisory_preview};
		my @groups        = flat $kvArgs{groups};

		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_forward",
			"publication_advisory_forward.publication_id" => $publicationId
		);

		my $typeIdAdvisoryEmail = Publication->getPublicationTypeId($typeName);

		my $isHighHigh = 0;
		if (@groups==0) {
			$vars->{message} = "Advisory has not been sent.";
		} else {
			Publication->setPublication(
				id => $publicationId,
				contents => $advisoryText,
				status => 3,
				published_by => sessionGet('userid'),
				published_on => nowstring(10),
				opened_by => undef
			);

			# get those who want to receive advisory emails
			my @wantEmail = @{ Publish->getIndividualsForSending( $typeIdAdvisoryEmail, \@groups ) };

			my %level = ( 1 => "H", 2 => "M", 3 => "L" );

			my $subject = $publication->{govcertid}
				. " [v" . $publication->{version} . "]"
				. " [" . $level{ $publication->{probability} }
				. "/" . $level{ $publication->{damage} } . "]"
				. " " . decode_entities( $publication->{title} );

			my @addresses;
			my @individualIds;
			my @results;
			my $sendingFailed = 0;

			# send advisory without
			for ( my $i = 0; $i < @wantEmail; $i++ ) {
				push @addresses, $wantEmail[$i]->{emailaddress};
				push @individualIds, $wantEmail[$i]->{id};
			}

			my $attachments = Publication->getPublicationAttachments( publication_id => $publication->{publication_id} );
			foreach my $attachment ( @$attachments ) {
				my $file;
				my $mode = Publication->{dbh}->{dbh}->{pg_INV_READ};

				withTransaction {
					my $lobj_fd = Publication->{dbh}->{dbh}->func( $attachment->{object_id}, $mode, 'lo_open');

					Publication->{dbh}->{dbh}->func( $lobj_fd, $file, $attachment->{file_size}, 'lo_read' );
				};

				$attachment->{binary} = $file;
			}

			if ( scalar( @addresses ) > 0 ) {
				my $response = Publish->sendPublication(
					addresses => \@addresses,
					subject => $subject,
					msg => decode_entities( $advisoryText ),
					attach_xml => 0,
					pub_type => 'advisory',
					attachments => $attachments
				);

				if ( $response ne "OK" ) {
					$sendingFailed = 1;
				}

				my %result = (
					response => $response,
					inc_xml => 0
				);

				for ( my $i = 0; $i < @addresses; $i++ ) {
					push @{ $result{addresses} }, $addresses[$i];
					push @{ $result{ids} }, $individualIds[$i];
				}

				push @results, \%result;

				undef @addresses;
				undef @individualIds;
			}

			if ( $sendingFailed eq 0 ) {
				$vars->{results} = "Your message was successfully sent to the following addresses: \n\n";

				my $updatedAnalysisCount = Publish->setAnalysisToDoneStatus( $publicationId, $publication->{govcertid} );

				$vars->{analysisUpdated} = $updatedAnalysisCount;

				# in case of a High/High advisory create a callinglist
				if ( $publication->{damage} == 1 && $publication->{probability} == 1 ) {
					createCallingList($publicationId, \@groups);
				}

				foreach my $result ( @results ) {
					foreach my $id ( @{ $result->{ids} } ) {
						Publish->setSendingResult(
							channel => 1,
							constituent_id => $id,
							publication_id => $publicationId,
							result => $result->{response}
						);

						if ( $result->{inc_xml} ) {
							Publish->setSendingResult(
								channel => 5,
								constituent_id => $id,
								publication_id => $publicationId,
								result => $result->{response}
							);
						}
					}

					foreach my $address ( @{ $result->{addresses} } ) {
						$vars->{results} .= "- " . $address . " " . $result->{response} . "\n";
					}
				}

			} else {
				closeForwardPublication( id => $publicationId );

				$vars->{results} = "Your message has not been sent: \n\n";

				foreach my $result ( @results ) {
					foreach my $address ( @{ $result->{addresses} } ) {
						$vars->{results} .= "- " . $address . " " . $result->{response} . "\n";
					}
				}
			}

			$vars->{advisory_heading} = "PUBLISH -- " . $publication->{govcertid} . " [v" . $publication->{version} . "]";

			setUserAction( action => 'publish advisory', comment => "Published advisory " . $publication->{govcertid} . " [v" . $publication->{version} . "]");

			$isHighHigh = 1 if ( $publication->{damage} eq 1 && $publication->{probability} eq 1 );
		}

		my $dialogContent = Template->processTemplate( 'publish_advisory_result.tt', $vars, 1 );

		return {
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
				isHighHigh => $isHighHigh
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate( 'dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub printCallingListForward {
	my (%kvArgs) = @_;

	setUserAction(
		action => 'print callinglist',
		comment => "Printed callinglist for advisory " . _publicationIdAndVersion($kvArgs{id})
	);

	return {
		params => {
			callingList => Template->processTemplate(
				"publish_advisory_call_list.tt",
				{ calling_list => getCallingList($kvArgs{id}, $kvArgs{t}) },
				1
			)
		}
	};
}

sub saveCallingListForward {
	my (%kvArgs) = @_;

	setUserAction(
		action => 'save callinglist',
		comment => "Saved callinglist for advisory " . _publicationIdAndVersion($kvArgs{id})
	);

	print CGI->header(
		-content_disposition => 'attachment; filename="callinglist.txt"',
		-type => 'text/plain',
	);

	print Template->processTemplate(
		"publish_call_list_savefile.tt",
		{ calling_list => getCallingList($kvArgs{id}, $kvArgs{t}) },
		1
	);
}

sub _publicationIdAndVersion {
	my $publication = Publication->getPublicationDetails(
		table => "publication_advisory_forward",
		"publication_advisory_forward.publication_id" => shift,
	);
	return "$publication->{govcertid} $publication->{version_str}";
}

1;
