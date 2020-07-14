# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

# This script can be used to update advisories on the website.

package Taranis::Command::Website;

use warnings;
use strict;
use utf8;

use Carp;
use HTTP::Status             qw(HTTP_NOT_ACCEPTABLE);
use HTML::Entities           qw(decode_entities);

use Taranis::Database        ();
use Taranis::Publication     ();
use Taranis::Website::Client ();
use Taranis::Log             ();

sub _get_webpubs($);
sub _get_emailed_advisory($);
sub _update_webpub_id($$);

my ($logger, $db);

my %handlers = (
	resend    => \&website_resend,
);

Taranis::Commands->plugin(website => {
	handler       => \&website_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'continue|c!',
		'log|l=s',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  resend [-lc] CERTIDS    upload website advisories again to the website

OPTIONS:
  -c --continue           skip advisories with content issues
  -l --log FILENAME       alternative logging (maybe '-' for stdout)

CERTIDS like 'NCSC-2016' or 'NCSC-2017-0111'.  Existing IDs filtered
with trailing '%'.  May contain other db wildcard symbols.
__HELP
});

sub website_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

###
### taranis website resend
###

sub website_resend($) {
	my $args = shift;

	$logger      = Taranis::Log->new('website-resend', $args->{log});
	my $certids  = $args->{files}    || [];
	my $continue = $args->{continue} || 0;

	@$certids
		or die "ERROR: No cert-ids specified (f.i. NCSC-2018 or NCSC-2019-0112)\n";

	die "ERROR: Illegal character in certid '$_'\n"
		for grep !/^[a-z0-9-]+$/i, @$certids;

	$db   = Taranis::Database->new->simple;
	my $client  = Taranis::Website::Client->new
		or die "ERROR: No website client configured (yet).\n";

	$logger->info("Using website backend " . ref($client));

	my $webpubs_feed = _get_webpubs $certids;
	my $nr_updates   = 0;
	my $nr_issues    = 0;

  PUBLICATION:
	while(my $webpub = $webpubs_feed->hash) {
		my $emailed = _get_emailed_advisory $webpub;

		my $certid  = $webpub->{govcertid};
		my $version = $emailed->{version};
		$logger->info("Sending $certid $version");

		my $external_ref = $client->publishAdvisory($webpub, $emailed);
		unless($external_ref) {
			$nr_issues++;
			my $code  = $client->{error_code};
			my $error = $client->{errmsg};
			$logger->error("$code: $error");

			if($code==HTTP_NOT_ACCEPTABLE) {
				next PUBLICATION if $continue;
				print "HINT: use '--continue' to skip simple issues.\n";
			}
			last PUBLICATION;
		}

		$nr_updates++;
		_update_webpub_id $webpub, $external_ref;
	}

	my $issues = $nr_issues ? ", $nr_issues issues" : '';
	$logger->info("Updated $nr_updates advisories$issues.");
}

###
### HELPERS
###

sub _get_webpubs($) {
	my $certids = shift;
	my $take_certids = join ' OR ',
		map "pw.govcertid ILIKE '$_%'", @$certids;

	my $feed = $db->query(<<__GET_PUBS);
SELECT pu.id, pu.contents, pu.published_on, pu.status, pu.xml_contents,
       pw.id AS publication_id, pw.govcertid, pw.title, pw.advisory_id,
       pw.advisory_forward_id
  FROM publication_advisory_website AS pw
       LEFT JOIN publication        AS pu  ON pu.id = pw.publication_id
 WHERE $take_certids
   AND pu.status = 3
   AND pu.published_on IS NOT NULL
 ORDER BY pw.govcertid, pw.version
__GET_PUBS

	$feed;
}

sub _get_emailed_advisory($) {
	my $webpub = shift;

	my $publications = Taranis::Publication->new;
	if(my $adv_id = $webpub->{advisory_id}) {
		return $publications->getPublicationDetails(
			table => 'publication_advisory',
			'publication_advisory.id' => $adv_id,
		);
	}

	if(my $fwd_id = $webpub->{advisory_forward_id}) {
		return $publications->getPublicationDetails(
			table => 'publication_advisory_forward',
			'publication_advisory_forward.id' => $fwd_id,
		);
	}

	undef;
}

sub _update_webpub_id($$) {
	my ($webpub, $reference) = @_;

	my $publications = Taranis::Publication->new;
	$publications->setPublicationDetails(
		table       => "publication_advisory_website",
		where       => { id => $webpub->{publication_id} },
		handle_uuid => $reference,
		document_uuid => undef,    # not used since 3.5.0
	);
}

1;
