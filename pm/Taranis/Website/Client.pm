# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Website::Client;

use strict;
use warnings;

use Carp qw(confess);

use Taranis qw(find_config);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);

sub new {
	my ($class, %args) = @_;

	my $config = Config->publishWebsite
		or return;

	my $impl   = $config->{implementation};
	eval "require $impl";
	die $@ if $@;

	my $settings;
	if(my $cfn = find_config $config->{configuration}) {
		$settings = Taranis::Config->new($cfn);
	}

	(bless {}, $impl)->init($settings);
}

sub init() { shift }

sub publishAdvisory($$) {
	my ($self, $publication, $emailed) = @_;
	confess "publishAdvisory() needs to be extended.";
}

sub isPublished($) {
	my ($self, $unique) = @_;
	+ { is_success => 1, is_published => 0 };
}

1;


=head1 NAME

Taranis::Website::Client - plugin interface for website communication

=head1 SYNOPSIS

  my $obj = Taranis::Website::Client->new;
  $obj->isPublished($unique);
  my $unique = $obj->publishAdvisory($publication, $emaild);

=head1 DESCRIPTION

With some additional configuration, you can publish advisories to the
website.  This module defines the component which implements the
interface from Taranis to the server which displays the advisory.

There are at least three implementations:

=over 4
=item NCSC_NL::Website::HippoSOAP
An ugly SOAP::Lite connector the OneHippo CMS.  On the CMS server, a
daemon couples Perl with the OneHippo Java libraries.  NCSC-NL internal.

=item NCSC_NL::Website::HippoREST
A REST connector to the OneHippo CMS, which needs a small 'PUT' addition
to the standard REST interface of OneHippo.  NCSC-NL internal.

=item NCSC_NL::Website::ProREST
A REST connector used to display advisories on the MinAZ/PRO managed
website.  This is included in the public sources as reference implementation.

=back

When you start with your own connector, please contact us to get these
examples.

=head1 METHODS

=head2 my $client = $class->new(%config)
Create a client object, which enables transmission.

=head2 my $h = $client->isPublished($unique)

Checks if a publication with specified handle C<$unique> identifier
exists on "the other end".  Returns "success, unpublised" by default.

Returns an HASH with

   { is_success   => 1,
     is_published => 1,
     message => 'possibly an error message',
   }.

On error, it returns C<undef> and sets $self->{errmsg} when there is connection
issue. 

=head2 my $unique = $client->publishAdvisory($publication, $emaild);

Publishes an advisory to the backend.  When publishing was successful,
it returns a unique id, provided by the server.  When C<undef> is it
returned, $self->{errmsg} is set to explain the error.

Parameter C<$publication> contains a subset of the information for the
website publication.  It only gets constructed for real I<after> a
succesful upload.

The publication about the advisory which got C<$emaild> around may contain
additional information you want to distribute: the website publication
object does not contain much.

=cut
