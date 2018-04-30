# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

# Very basic logger, just to remove code replication.  Later, this may
# move towards a more modern framework.

package Taranis::Log;

use warnings;
use strict;

use Taranis::Install::Config  qw(config_release);
use Taranis qw(nowstring);

=head1 NAME

Taranis::Log - logging framework

=head1 SYNOPSIS

 my $logger = Taranis::Log->new('default_name', $alt_dest);
 $logger->info($msg);
 $logger->close;

=head1 DESCRIPTION

This simple logging module directs logs for different components into
separate logfiles.

In the future, we may want to be able to redirect to syslog as well.  And
probably support for debugging and log-levels.

=head1 METHODS

The following methods are available:

=over 4

=item my $logger = Taranis::Log->new($name, $alt_dest);

Initialize the logger.  It dies when the logfile cannot be opened.

When the alternative destination is defined, the log will not appear on
the default location.  That C<$alt_dest> value can be '-' (a single dash)
to write to STDOUT, a filehandle, or a filename.  The filename '/dev/null'
is useful during development, to make all logging disappear.

=cut

sub new($;$) {
	my ($class, $default, $filename) = @_;

	my $logfh;
	if(!defined $filename) {
		# usual case: default log destination
		my $release = config_release;
		$filename   = "$release->{logs}/$default.log";

   		open $logfh, '>>:encoding(utf8)', $filename
       		or die "ERROR: cannot log to $filename: $!\n";

	} elsif($filename eq '-') {
		# print to screen
		$logfh = \*STDOUT;

	} elsif(ref $filename) {
		# any object or GLOB will do, as long as it support a few print
		# methods.
		$logfh    = $filename;
		$filename = 'file-handle';

	} else {
   		open $logfh, '>>:encoding(utf8)', $filename
       		or die "ERROR: cannot log to $filename: $!\n";
	}

   	$logfh->autoflush(1);
	bless { TL_to => $logfh, TL_fn => $filename }, $class;
}


=item my $fh = $logger->logfh;

Returns the filehandle which the logger uses.

=item my $fn = $logger->filename;

When opened to a file, this will return a usefull name.

=cut

sub logfh()    { shift->{TL_to} }
sub filename() { shift->{TL_fn} }


=item $logger->close;

Close the log destination.

=cut

sub close() {
	my $self = shift;
	my $to   = delete($self->{TL_to});
	$to->close if $to;
}


=item $logger->print($message)

Print a line to the logfile. Trailing blanks and superfluous new-lines are
removed from the C<$message>.

A time-stamp will be prepended, but there is no indication about the
importance of the message.  Use the next methods to express that.

=cut

sub print($) {
	my ($self, $message) = @_;
	$message    =~ s/\s*$//;   # strip accidental trailing blanks and \n

    my $line    = nowstring(7). " $message\n";

    my $to = $self->{TL_to};
	$to->print($line) if $to;
}


=item $logger->info($message)

Informational message express expected, normal behavior.

=cut

sub info($) {
	my ($self, $message) = @_;
	$self->print("INFO: $message");
}


=item $logger->warning($message)

Warnings are resolvable issues.  The program will proceed.

=cut

sub warning($) {
	my ($self, $message) = @_;
	$self->print("WARNING: $message");

	$self->filename eq '-'
		or warn "ERROR: $message\n";
}


=item $logger->error($message)

When an unresolvable issue emerges, the program usually stops.  This method
itself will not do that: it just writes a line to the logfile.

=cut

sub error($) {
	my ($self, $message) = @_;
	$self->print("ERROR: $message");

	$self->filename eq '-'
		or warn "ERROR: $message\n";
}

=back

=cut


1;
