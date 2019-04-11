#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(right);
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Assess;
use Taranis::Template;
use Taranis::Users qw();
use Taranis::Session qw(sessionGet);
use Taranis::Mail qw();
use URI::Escape;
use MIME::Parser;
use HTML::Entities;
use Try::Tiny;
use strict;

my @EXPORT_OK = qw(displayMailAction mailItem displayMailMultipleItems mailMultipleItems);

sub mail_export {
	return @EXPORT_OK; 
}

sub displayMailAction {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $as = Taranis::Assess->new( Config );
	my $tt = Taranis::Template->new;
	
	my $digest = ( exists( $kvArgs{digest} ) ) ? uri_unescape( $kvArgs{digest} ) : undef;
	if ( right("execute") ) {

		if ( my $item = $as->getItem( $digest ) ) {
			my $description = $item->{description};
	
			if ( $item->{is_mail} ) {
				my $parser = MIME::Parser->new();
				my $parserOutputDir = tmp_path(Config->{mimeparser_outputdir} || '/tmp');

				$parser->output_dir( $parserOutputDir );
				mkdir $parserOutputDir;
				chmod 0777, $parserOutputDir;

				my $emailId = $item->{'link'};
				$emailId =~ s/.*?([0-9]*)$/$1/;
				
				my $emailItem = $as->getMailItem( $emailId );
				my $decodedMessage = decode_entities( $emailItem->{body} );
				
				my $entity;
				if($decodedMessage) {
					$entity = eval { $parser->parse_data($decodedMessage) };
					$vars->{messages} = "Mail parsing failed (1): $@" if $@;
				}

				$description = trim(encode_entities(decodeMimeEntity($entity,1,1)))
					if $entity;
			}

			my @mailto_addressess = split( ";", Config->{maillist} ); 
				for ( my $i = 0; $i < @mailto_addressess; $i++ ) {
				$mailto_addressess[$i] = trim( $mailto_addressess[$i] );
			}
	
			my $user = Taranis::Users->new( Config );
	
			my $user_settings = $user->getUser( sessionGet('userid') );	
			$vars->{item_id}		 = $digest;
			$vars->{result} 		 = "";
			$vars->{mailto} 		 = \@mailto_addressess;
			$vars->{mailfrom_sender} = $user_settings->{mailfrom_sender};
			$vars->{mailfrom_email}  = $user_settings->{mailfrom_email};
			$vars->{title} 			 = $item->{title}; 
			$vars->{body} 			 = $description;
			$vars->{screenshot_id}   = $item->{screenshot_object_id};
			$vars->{screenshot_size} = $item->{screenshot_file_size};
			$vars->{is_mail}		 = $item->{is_mail};
			
			if ( !$item->{screenshot_object_id} ) {
				 $vars->{'link'} .= $item->{'link'};
			}
		} else {
			$vars->{message} = $as->{errmsg};
		}
		
		$tpl = 'mail.tt';
		
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = 'Sorry, you do not have enough privileges to send this email...';
	}

	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return { dialog => $dialogContent };		
}

sub displayMailMultipleItems {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, @items );

	my $as = Taranis::Assess->new( Config );
	my $tt = Taranis::Template->new;
	
	my $digest = ( exists( $kvArgs{digest} ) ) ? uri_unescape( $kvArgs{digest} ) : undef;
	
	if ( right("execute") ) {

		my $parser = MIME::Parser->new();
		my $parserOutputDir = tmp_path(Config->{mimeparser_outputdir});

		$parser->output_dir( $parserOutputDir );
		mkdir $parserOutputDir;
		chmod 0777, $parserOutputDir;

		my @ids = flat $kvArgs{id}; 
		foreach my $unescapedId ( @ids ) {
			my $item = $as->getItem( uri_unescape( $unescapedId ) );

			if ( $item->{is_mail} ) {
				my $emailId = $item->{'link'};
				$emailId =~ s/.*?([0-9]*)$/$1/;

				my $emailItem = $as->getMailItem( $emailId );
				my $decodedMessage = decode_entities( $emailItem->{body} );
				
				my $entity;
				if($decodedMessage) {
					$entity = eval { $parser->parse_data($decodedMessage) };
					$vars->{message} = "Mail parsing failed (2): $@";
				}
		
				$item->{description} = trim( encode_entities(
					decodeMimeEntity($entity,1,1))
				) if $entity;
			}
			
			delete $item->{'link'} if ( $item->{screenshot_object_id} );
			
			push @items, $item;
		}
		
		$vars->{items} = \@items;
		
		my @mailto_addressess = map trim($_), split ";", Config->{maillist};

		my $user = Taranis::Users->new( Config );
		my $user_settings = $user->getUser( sessionGet('userid') );
		$vars->{item_id}		 = $digest;
		$vars->{mailto} 		 = \@mailto_addressess;
		$vars->{mailfrom_sender} = $user_settings->{mailfrom_sender};
		$vars->{mailfrom_email}  = $user_settings->{mailfrom_email};
		
		$tpl = 'mail_multiple_items.tt';
		
	} else {
		$tpl = 'dialog_no_right.tt';
		$vars->{message} = 'Sorry, you do not have enough privileges to send this email...';
	}
	
	my $dialogContent = $tt->processTemplate($tpl, $vars, 1);

	return { dialog => $dialogContent };		
}

sub mailItem {
	my ( %kvArgs ) = @_;
	my $message;

	if ( right("execute") ) {

		my $as = Taranis::Assess->new( Config );
		my $user = Taranis::Users->new( Config );
		my $user_settings = $user->getUser( sessionGet('userid') );
	
		my $item_id = uri_unescape( $kvArgs{item_id} );

		
		my $image;
		
		if ( $kvArgs{screenshot_id} =~ /^\d+$/ && $kvArgs{screenshot_size} =~ /^\d+$/ ) {
			
			my $mode = Database->{dbh}->{pg_INV_READ};
			
			withTransaction {
				my $lobj_fd = Database->{dbh}->func( $kvArgs{screenshot_id}, $mode, 'lo_open' );

				Database->{dbh}->func( $lobj_fd, $image, $kvArgs{screenshot_size}, 'lo_read' );
			};
		}

		my @addresses = flat $kvArgs{mailto};

		my $subject   = decode_entities $kvArgs{subject};
		$subject      =~ s/\s+/ /g;

		my $from_name = decode_entities $user_settings->{mailfrom_sender};
		my $from       = qq{"$from_name" <$user_settings->{mailfrom_email}>};
		my $text       = decode_entities $kvArgs{description};

		my $screenshot = $image ? Taranis::Mail->attachment(
			filename  => 'screenshot.png',
			mime_type => 'image/png',
			data      => $image,
		) : undef;

		foreach my $address ( @addresses ) {
			my $msg = Taranis::Mail->build(
				From       => $from,
				To         => $address,
				Subject    => $subject,
				plain_text => $text,
				attach     => $screenshot,
			);
			$msg->send;
		}

		$as->setIsMailedFlag($item_id)
			or $message .= "Error updating statistics mailed setting: " . $as->{errmsg} . "<br>";

	} else {
		$message = '<div id="dialog-error">Sorry, you do not have enough privileges to send this email...</div>';
	}

	my $dialogContent = $message
		? qq{<div class="dialog-form-wrapper block">$message</div>}
		: undef;

	return {
		params => {
			isMailed => ($message ? 0 : 1)
		},
		dialog => $dialogContent
	};
	
}

sub mailMultipleItems {
	my ( %kvArgs ) = @_;
	my $message;
		
	if ( right("execute") ) {

		my $as = Taranis::Assess->new( Config );
		my $user = Taranis::Users->new( Config );
		my $user_settings = $user->getUser( sessionGet('userid') );

		my @addresses = split(',', $kvArgs{addresses} );
			
		my $mailItemsJson = $kvArgs{items};
		$mailItemsJson =~ s/&quot;/"/g;
		my $mailItems = from_json( $mailItemsJson );

		foreach my $mailItem ( @$mailItems ) {
			my $image;
			my $isMailed = 0;
			my $item = $as->getItem( uri_unescape( $mailItem->{id} ) );
			
			if ( $item->{screenshot_object_id} ) {
				my $mode = Database->{dbh}->{pg_INV_READ};
				
				withTransaction {
					my $lobj_fd = Database->{dbh}->func( $item->{screenshot_object_id}, $mode, 'lo_open' );

					Database->{dbh}->func( $lobj_fd, $image, $item->{screenshot_file_size}, 'lo_read' );
				};
			}

			my $subject   = decode_entities( $mailItem->{subject} );
			$subject      =~ s/\s+/ /g;

			my $from_name = decode_entities $user_settings->{mailfrom_sender};
			my $from      = qq{"$from_name" <$user_settings->{mailfrom_email}>};
			my $text      = decode_entities( $mailItem->{body} ),

			my $screenshot = $image ? Taranis::Mail->attachment(
				filename  => 'screenshot.png',
				mime_type => 'image/png',
				data      => $image,
			) : undef;

			foreach my $address ( @addresses ) {
				my $msg = Taranis::Mail->build(
					From       => $from,
					To         => $address,
					Subject    => $subject,
					plain_text => $text,
					attach     => $screenshot,
				);
				$msg->send;
			}

			$as->setIsMailedFlag( uri_unescape( $mailItem->{id} ) )
				or $message .= "Error updating statistics mailed setting: $as->{errmsg}<br>";
		}

	} else {
		$message = '<div id="dialog-error">Sorry, you do not have enough privileges to send this email...</div>';
	}

	$message
		or return { close_dialog => 1 };

	my $dialogContent = '<div class="dialog-form-wrapper block">' . $message . '</div>';
	return { dialog => $dialogContent };
}
1;
