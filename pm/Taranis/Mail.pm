# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Mail;
use base 'Mail::Message';

use warnings;
use strict;

use Mail::Message;
use Mail::Transport;
use Mail::Message::Body::String     ();
use Mail::Message::Body::Multipart  ();
use Mail::Message::Construct::Build ();
use Mail::Message::Field::Full      ();

use Taranis::Config;
use Carp qw(confess);

my $config;

=head1 NAME

Taranis::Mail - create/send an email

=head1 SYNOPSIS

  my $message = Taranis::Mail->build(...options...);
  $message->send;

=head1 DESCRIPTION

This module is a modest wrapper around L<Mail::Message> and L<Mail::Transport>,
which mainly hides Taranis specific configuration.

=head1 METHODS

=over 4

=item my $msg = $class->build(%options);

See L<Mail::Message::Construct::Build>.  Header fields always start with
a capital.

=cut

sub build(%) {
	my ($class, %args) = @_;
	$config ||= Taranis::Config->new;

	if(my $f = delete $args{config_from}) {
		$args{From} = $config->{$f};
	} elsif( ! $args{From} ) {
		$args{From} = $config->{mail_from_address};
	}

	if(my $t = delete $args{config_to}) {
		$args{To}   = $config->{$t};
	}

	if(my $r = $args{'Reply-To'} || $args{reply_to} || $config->{mail_reply_to}) {
		$args{'Reply-To'} = $r;
	}

	my $subject = delete $args{Subject} || 'No subject';
	my $s       = Mail::Message::Field::Full->new(Subject => $subject, charset => 'utf8');

	my $body  =  delete $args{body} || $class->_make_body(\%args);
 	my $msg   = $class->SUPER::build($body, $s, %args);

	$msg;
}

sub _make_body($) {
	my ($class, $args) = @_;
	my $plain = delete $args->{plain_text} || '';
	my $html  = delete $args->{html_text}  || '';

	length $plain || length $html
		or $plain = "See the attachment.\n";

	my ($plain_body, $html_body);
	$plain_body = Mail::Message::Body::String->new(data => $plain,
		mime_type => 'text/plain') if length $plain;

	$html_body  = Mail::Message::Body::String->new(data => $html,
		mime_type => 'text/html') if length $html;

	return $plain_body || $html_body
		unless $plain_body && $html_body;

	Mail::Message::Body::Multipart->new(
		parts     => [ $plain_body, $html_body ],
		mime_type => 'multipart/alternative',
	);
}


=item my $attach = Taranis::Mail->attachment(%options);

Produce an attachement.

=cut

sub attachment($%) {
	my ($class, %args) = @_;
	Mail::Message::Body::String->new(%args);
}


=item $msg->send;

Send the prepare message.  If there is an smtpserver specified, then we
sent emails via direct smtp.  Otherwise, we simply run local delivery.

=cut

sub send() {
	my $self = shift;
	if(my $server = $config->{smtpserver}) {
		return $self->SUPER::send(
			via      => 'smtp',
			hostname => $server,
            port     => $config->{smtpport} || 25,
            user     => $config->{smtpuser},
            password => $config->{smtppass},
		);
	}

	$self->SUPER::send;
}

=back

=cut

1;
