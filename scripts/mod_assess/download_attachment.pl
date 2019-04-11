#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Assess;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(CGI Config Database);
use Taranis qw(:all);
use strict;
use CGI::Simple;
use MIME::Parser;
use HTML::Entities;
use Carp;

my @EXPORT_OK = qw( downloadAttachment loadImage );

sub download_attachment_export {
	return @EXPORT_OK;
}

sub downloadAttachment {
	my ( %kvArgs ) = @_;

	my $parser = MIME::Parser->new();
	
	my $outputDir = tmp_path 'assess-attachments';
	mkdir $outputDir;
	$parser->output_dir( $outputDir );

	my $as = Taranis::Assess->new( Config );
	
	my $mailItemId = $kvArgs{id};
	my $attachmentName = $kvArgs{attachmentName};

	my $message = $as->getMailItem( $mailItemId );

	my $decodedMessage = HTML::Entities::decode( $message->{body} );

	my $messageEntity = $parser->parse_data( $decodedMessage ) || croak "unparsable MIME message";
	my $attachment = $as->getAttachment( $messageEntity, $attachmentName ) || croak "no valid attachment found";
	my $attachmentEntity = $parser->parse_data( $attachment ) || croak "unparsable MIME attachment";

	my $attachmentDecoded = decodeMimeEntity( $attachmentEntity, 1, 0 );

	my $head = $attachmentEntity->head();
	
	my $contentType	= $head->get( 'content-type' );
	my $contentDisposition = $head->get( 'content-disposition' );
	my $contentTransferEncoding = $head->get( 'content-transfer-encoding' );

	$contentType =~ s/\n//g;
	$contentDisposition =~ s/\n//g if ( $contentDisposition );
	$contentTransferEncoding =~ s/\n//g if ( $contentTransferEncoding );
	
	if ( $contentType =~ /^(image|audio|video)/i || !$contentDisposition ) {
		$contentDisposition = "attachment; filename=\"$attachmentName\"";
	}
	
	print CGI->header(
		-content_disposition => $contentDisposition,
		-content_transfer_encoding => $contentTransferEncoding || 'none',
		-type => $contentType,
	);
	print $attachmentDecoded;

	return {};
}

sub loadImage {
	my ( %kvArgs ) = @_;
	my $dbh = Database;

	my $objectId = $kvArgs{object_id};
	my $fileSize = $kvArgs{file_size};
	my $image;
	my $mode = $dbh->{dbh}->{pg_INV_READ};
	
	withTransaction {
		my $lobj_fd = $dbh->{dbh}->func($objectId, $mode, 'lo_open');

		$dbh->{dbh}->func( $lobj_fd, $image, $fileSize, 'lo_read' );
	};

	print CGI->header(
		-type => 'image/png',
		-content_length => $fileSize,
	);
	binmode STDOUT;
	print $image;
}
1;
