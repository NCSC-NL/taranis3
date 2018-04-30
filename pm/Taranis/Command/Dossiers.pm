# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Dossiers;

use warnings;
use strict;

use Carp           qw(confess);

use Taranis        qw(:all);
use Taranis::Log   ();
use Taranis::Config;
use Taranis::Dossier;
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Mail ();

use Data::Dumper;
use HTML::Entities qw(decode_entities);


my %handlers = (
	'send-reminders' => \&dossiers_send_reminders,
);

Taranis::Commands->plugin(dossiers => {
	handler       => \&dossiers_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l=s'
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  send-reminders [-l]     inform about open dossiers which saw activity

OPTIONS:
	-l --log FILENAME     redirect log
__HELP
} );

sub dossiers_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

sub dossiers_send_reminders($) {
	my $args          = shift;
	my $logger        = Taranis::Log->new('dossier-reminders', $args->{log});

	my $config        = Taranis::Config->new();
	my $dossier_admin = Taranis::Dossier->new(Config);
	my %statuses      = reverse %{ $dossier_admin->getDossierStatuses };

	my $dossiers      = $dossier_admin->getDossiers;
	my $mails_sent    = 0;

  DOSSIER:
	foreach my $dossier (@$dossiers) {
		my $dossier_id       = $dossier->{id};
		my $latestActivity   = $dossier_admin->getDateLatestActivity($dossier_id);

		my $reminderDossiers = $dossier_admin->getDossiers( 
			"( NOW() - d.reminder_interval )" => { '>' => $latestActivity },
			'd.id' => $dossier_id,
			status => $statuses{ACTIVE}
		);

		my $requestor = $dossier->{mailfrom_email};
		@$reminderDossiers && $requestor
			or next DOSSIER;

		my $topic = decode_entities $dossier->{description};
		my $msg   = Taranis::Mail->build(
			To         => $requestor,
			Subject    => "[Taranis] Reminder for dossier '$topic'",
			plain_text => "Last activity for '$topic' was $latestActivity\n",
		);
		$msg->send;

		$logger->info("reminder send to $requestor about '$topic'");
		$dossier_admin->setDossier(
			id     => $dossier_id,
			status => $statuses{INACTIVE},
		);
		$mails_sent++;
	}

	$logger->info("$mails_sent dossier reminders sent.")
		if $mails_sent;
}
