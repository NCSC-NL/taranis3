#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis::Template;
use Taranis::Assess;
use Taranis::Config;
use Taranis::SessionUtil qw(rightOnParticularization);
use Taranis::FunctionalWrapper qw(Config);
use Taranis qw(decodeMimeEntity trim tmp_path);
use URI::Escape;
use MIME::Parser;
use HTML::Entities;

my @EXPORT_OK = qw(displayMail);

sub show_mail_export {
	return @EXPORT_OK; 
}

sub displayMail {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $as = Taranis::Assess->new( Config );
	my $tt = Taranis::Template->new;

	my $id = ( exists( $kvArgs{id} ) && $kvArgs{id} =~ /^\d+$/ ) ? $kvArgs{id} : undef;

	if ( my $item = $as->getMailItem( $id ) ) {
		if ( rightOnParticularization( $item->{category} ) ) {

			my $parser = MIME::Parser->new();
			my $outputDir = tmp_path 'display-mail-attachments';
			mkdir $outputDir;
			$parser->output_dir( $outputDir );		

			my $decodedMessage = HTML::Entities::decode( $item->{body} );
			my $entity = $parser->parse_data($decodedMessage);
		
			$vars->{id} = $id;
			$vars->{attachments} = $as->getAttachmentInfo($entity);
			$vars->{text} = trim( HTML::Entities::encode( decodeMimeEntity( $entity, 1, 1 ) ) );
			$vars->{originalText} = trim( $item->{body} ); 
			$vars->{title} = $item->{title};
			
			$tpl = 'show_mail.tt';
		} else {
			$tpl = 'dialog_no_right.tt';
			$vars->{message} = 'Sorry, you do not have enough privileges to view this email...';
		}
	} else {
		$tpl = 'show_mail.tt';
		$vars->{message} = $as->{errmsg};
	}
	
	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);
	
	return { dialog => $dialogContent };
}

1;
