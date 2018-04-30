# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::SpecInt;

use warnings;
use strict;

use Carp           qw(confess);
use List::Util     qw(first);
use HTML::Entities qw(decode_entities);

use Taranis        qw(:all);
use Taranis::Log   ();
use Taranis::Config;
use Taranis::Database;
use Taranis::Report::SpecialInterest;
use Taranis::FunctionalWrapper qw(Config Database ReportSpecialInterest);
use Taranis::Mail  ();

my %handlers = (
	'send-reminders' => \&specint_send_reminders,
);

Taranis::Commands->plugin(specint => {
	handler       => \&specint_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'log|l'
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  send-reminders [-l]     send 3 days special interest reminders

OPTIONS:
  -l --log FILENAME       alternative logging (maybe '-' for stdout)
__HELP
} );

sub specint_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

# was half of backend_tools/report.pl

sub specint_send_reminders($) {
	my $args   = shift;
	my $db     = Database->{simple};

	my $logger = Taranis::Log->new('specint-reminders', $args->{log});

	my @reminders = $db->query( <<'__REMINDERS' )->hashes;
 SELECT *, to_char(date_end, 'DD-MM-YYYY') AS date_end_str
   FROM report_special_interest
  WHERE ( date_end - '3 days'::INTERVAL ) < NOW()
    AND timestamp_reminder_sent IS NULL
__REMINDERS

	@reminders
		or return;

	$logger->info("Got ".@reminders." special interest reminders to send.");

  REMINDER:
	foreach my $reminder (@reminders) {
		my $requestor = $reminder->{requestor};
		my $topic     = $reminder->{topic};

		my $msg       = Taranis::Mail->build(
			To          => $requestor,
			Subject     => decode_entities( "[Taranis] Reminder for $topic" ),
			plain_text  => decode_entities( <<__BODY ),
This is an automated message for $requestor.

Monitoring of topic $topic will end after $reminder->{date_end_str}.
__BODY
		);
		$msg->send;

		$logger->info("reminder to $requestor sent");

		ReportSpecialInterest->setSpecialInterest(
			id => $reminder->{id},
			timestamp_reminder_sent => \'NOW()',
		);
	}

	$logger->close;
	$db->disconnect;
}
