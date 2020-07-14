# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(val_int trim_text nowstring);
use Taranis::SessionUtil qw(setUserAction right rightOnParticularization);
use Taranis::Session qw(sessionGet);
use Taranis::Template;
use Taranis::Config;
use Taranis::Publication;
use Taranis::Publish;
use Taranis::Website::Client;
use Taranis::FunctionalWrapper qw(Config Publication Publish Template);
use strict;

use HTML::Entities qw(encode_entities);

my @EXPORT_OK = qw( openDialogPublishWebsite publishAdvisoryWebsite checkPreviousPublishedAdvisory );

sub publish_website_export {
	return @EXPORT_OK;
}

sub openDialogPublishWebsite {
	my %kvArgs = @_;
	my ($vars, $tpl);

	my $typeName = Config->publicationTemplateName(advisory => 'website');
	my $publicationId = val_int $kvArgs{id};

	if(rightOnParticularization($typeName) && $publicationId) {
		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_website",
			"publication_advisory_website.publication_id" => $publicationId,
		);

		my $certid    = $publication->{govcertid};
		my $version   = $publication->{version};
		my $is_update = $version > 1.00;

		Publication->setPublication(id => $publicationId, published_on => nowstring(9));

		my ($pub_type, $details_id);
		if($publication->{advisory_id}) {
			$pub_type   = $is_update ? "website_update" : "website" ;
			$details_id = $publication->{advisory_id};
		} else {
			$pub_type   = $is_update ? "forward_website_update" : "forward_website" ;
			$details_id = $publication->{advisory_forward_id};
		}

		my $advisoryText = Template->processPreviewTemplate( "advisory", $pub_type, $details_id, $publicationId, 71 );

		Publication->setPublication(id => $publicationId, contents => $advisoryText);

		$vars->{preview}    = $advisoryText;
		$vars->{publication_id} = $publication->{publication_id};
		$vars->{adv_web_id} = $publication->{id};
		$vars->{is_regular} = $publication->{advisory_id} ? 1 : 0;
		$vars->{advisory_heading} = "PUBLISH TO WEBSITE -- $certid [v$version]";

		$tpl = "publish_advisory_website.tt";
		my $dialogContent = Template->processTemplate($tpl, $vars, 1);

		return {
			dialog => $dialogContent,
			params => {
				publicationId => $publicationId,
			}
		};
	} else {
		$vars->{message} = 'No permission...';
		my $dialogContent = Template->processTemplate('dialog_no_right.tt', $vars, 1 );
		return { dialog => $dialogContent };
	}
}

sub publishAdvisoryWebsite {
	my %kvArgs = @_;
	my ($tpl, $vars);

	my $typeName = Config->publicationTemplateName(advisory => 'website');
	my $publicationId = val_int $kvArgs{id};

	if(rightOnParticularization($typeName) && right("execute") && $publicationId) {
		my $is_public     = $kvArgs{is_public}  eq '1';
		my $is_regular    = $kvArgs{is_regular} eq '1';

		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_website",
			"publication_advisory_website.publication_id" => $publicationId,
		);
		my $certid  = $publication->{govcertid};
		my $version = $publication->{version};

		my $advisory_text   = trim_text $kvArgs{advisory_preview};

		# Get mailed version for additional info
		my $advisoryTable   = $is_regular ? 'publication_advisory' : 'publication_advisory_forward';
		my $detailsIdColumn = $is_regular ? 'advisory_id' : 'advisory_forward_id';
		my $emaild = Publication->getPublicationDetails(
			table => $advisoryTable,
			"$advisoryTable.id" => $publication->{$detailsIdColumn},
		);

		# Construct publication to-be, based on the advisory which got mailed
		# around.  It only gets definitive form after success... 
		$publication->{contents}     = $advisory_text;

		# Create XML which may/may not be sent
		delete $emaild->{tlpamber} if $is_public;
		my $xml_text = Publication->processPreviewXml($emaild);
		$publication->{xml_contents} = $xml_text;

		my $website = Taranis::Website::Client->new;
		if(my $reference = $website->publishAdvisory($publication, $emaild)) {
			$vars->{results} = "The Advisory was successfully published on the website.\n\n";
			$vars->{results} .= "The advisory was published as non-public\n\n" if !$is_public;

			setUserAction( action => 'publish advisory',
				comment => "Published advisory $certid [v$version] web");

			Publication->setPublication(
				id           => $publicationId,
				status       => 3,
				published_by => sessionGet('userid'),
				published_on => nowstring(10),
				contents     => $advisory_text,
				xml_contents => $xml_text,
			);

			Publication->setPublicationDetails(
				table => "publication_advisory_website",
				where => { id => $publication->{id} },
				handle_uuid   => $reference,
				document_uuid => undef,
				is_public     => $is_public || 0,
			);

		} else {
			$vars->{results} = "The advisory was not published on the website because of following error:\n$website->{errmsg}\n\n";
		}

		$vars->{advisory_heading} = "PUBLISH -- $certid [v$version]";
		$tpl = 'publish_advisory_website_result.tt';

	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = Template->processTemplate($tpl, $vars, 1 );
	+{ dialog => $dialogContent };
}

sub checkPreviousPublishedAdvisory {
	my %kvArgs = @_;

	my $message     = '';
	my $isSuccess   = 0;
	my $isPublished = 0;

	if (my $publicationId = val_int $kvArgs{id}) {
		my $publication = Publication->getPublicationDetails(
			table => "publication_advisory_website",
			"publication_advisory_website.id" => $publicationId,
		);

		my $certid = $publication->{govcertid};

		my ($external_ref, $previous);
		if ( $publication->{version} > 1.00 ) {
			my $previousVersion = sprintf "%1.2f", $publication->{version} - 0.01;
			$previous = Publication->getPublicationDetails(
				table => "publication_advisory_website",
				"publication_advisory_website.govcertid" => $certid,
				"publication_advisory_website.version"   => $previousVersion,
			);

			$previous->{handle_uuid}
				or $message = "Warning: prior advisory version $previousVersion is prepared but not published (yet)";

		} elsif($previous = Publish->getPriorPublication($certid, 'publication_advisory_website')) {

			$previous->{handle_uuid}
				or $message = "Warning: prior advisory $previous->{govcertid} $previous->{version} is prepared but not published (yet)";

		}

		if( ! $previous ) {
			$message = "Could not find an older advisory.";

		} elsif($previous->{advisory_forward_id}) {
			$isPublished = 1;
			$isSuccess   = 1;

		} elsif(my $external_ref = $previous->{handle_uuid}) {
			my $website = Taranis::Website::Client->new;
			if(my $answer = $website->isPublished($external_ref)) {
				$isPublished = $answer->{is_published};
				$isSuccess   = $answer->{is_success};
				$message     = $answer->{message};
			} else {
				$message     = "Destination server could not be reached.";
			}
		}
	} else {
		$message = "Invalid input supplied";
	}

	return {
		params => {
			is_published => $isPublished || 0,
			is_success   => $isSuccess   || 0,
			message      => $message,
		}
	};
}

1;
