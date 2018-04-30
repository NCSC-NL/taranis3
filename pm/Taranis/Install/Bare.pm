# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Bare;
use base 'Exporter';

use warnings;
use strict;

# This module exports some functions which do not need any other support
# programs or Perl modules.  We need this to be separate to be able to
# bootstrap installation.

#!!! Only the basic necessities in here to run bootstrap !!!

use Carp        qw(croak);
use File::Copy  qw(copy);
use IO::Handle  ();         # needed for older Perl's

sub _os_info_legacy_convert();

our @EXPORT = qw(
	get_os_info
	create_dir
	clone_dir
	copy_file
	wrap_print
	is_opensuse
	is_centos
	is_ubuntu
	is_redhat
	has_internet
	sloppy_parse_xml
	unpack_tar
	version_from_filename
);

our %EXPORT_TAGS = (
    os_checks => [ qw/is_opensuse is_centos is_ubuntu is_redhat/ ],
);

# Read version info from an /etc/os-release file
my $os_info;
sub get_os_info(;$) {
	my $fn = shift || '/etc/os-release';

	return $os_info
		if $os_info;

	-f $fn
		or return $os_info = _os_info_legacy_convert;

	open my $info, '<:encoding(utf8)', $fn
		or die "ERROR: cannot read $fn: $!\n";

	my %info;
	while(my $line = $info->getline) {
		my ($field, $value) = split /\=/, $line, 2;
		defined $field && defined $value or next;

		$value =~ s/\s*$//;
		$value =~ s/^(["'])(.*)\1$/$2/;
		$info{$field} = $value;
	}

	$os_info = \%info;
}

sub create_dir($$$$) {
	my ($dir, $dirmode, $userid, $groupid) = @_;
	my ($mode, $uid, $gid) = (stat $dir)[2,4,5];

	my $is_new = 0;
	unless(-d $dir) {
		print "Create directory $dir\n";
		mkdir $dir
			or croak "ERROR: cannot create directory: $!";
		$is_new++;
	}

	if(!defined $mode || $dirmode != ($mode & 07777)) {
		printf "Change mode to 0%o on $dir\n", $dirmode unless $is_new;
		chmod $dirmode, $dir
			or croak "ERROR: cannot change mode to $dirmode: $!";
	}

	if(!defined $uid || $uid != $userid || $gid != $groupid) {
		print "Change owner to $userid/$groupid on $dir\n" unless $is_new;
		chown $userid, $groupid, $dir
			or croak "ERROR: cannot change owner/group to $userid/$groupid: $!";
	}
}

# Copy the content of the first directory into the second directory.
sub clone_dir($$) {
	my ($fromdir, $todir) = @_;
	$fromdir .= '/' if $fromdir !~ m!/$!;
	system "rsync", "--archive", $fromdir, $todir
		and die "failed cloning $fromdir -> $todir: $!\n";
}

sub copy_file($$;$) {
	my ($from, $to, $mode) = @_;
	copy $from, $to
		or die "ERROR: cannot copy $from --> $to: $!\n";

	if($mode) {
		chmod $mode, $to
			or die sprintf "ERROR: cannot chmod %s to %o: %s\n",
				$to, $mode, $!;
	}
}

sub wrap_print($$) {
	my ($prefix, $string) = @_;
	length $string or return;

	while(length $string > 70) {
		$string =~ s/^(.{1,69})[ ]//;
		print "$prefix$1\n";
	}

	print "$prefix$string\n"
		if $string =~ /\S/;
}

sub is_opensuse() { get_os_info->{ID} eq 'opensuse' }
sub is_centos()   { get_os_info->{ID} eq 'centos' }
sub is_ubuntu()   { get_os_info->{ID} eq 'ubuntu' }
sub is_redhat()   { get_os_info->{ID} =~ /^(:redhat|rhel|fedora)$/ }

sub has_internet() {
	# set by taranis-install option --no-internet
	($ENV{TARANIS_INTERNET} || 'yes') ne 'no';
}

sub unpack_tar($$) {
	my ($tar, $dest) = @_;

	print "*   unpacking tarball $tar --> $dest\n";

    -f $tar
        or die "ERROR: Cannot find '$tar'\n";

	system tar => '--extract',
		'--auto-compress',
        '--file'      => $tar,
        '--directory' => $dest
        and die "ERROR: failed to extract tar from $tar: $!\n";
}

# Also in taranis-bootstrap
sub version_from_filename($) {
	my $fn = shift;
	$fn =~ m! \b taranis-([0-9]+\.[0-9]\.[0-9]*(?:\-(?:rc|alpha|α|beta|β)[0-9]+)?) !x;
	$1;
}

# We swiftly need some simple facts from an XML-file, but have only
# very little resources... no CPAN modules, for instance.  So: parse
# with limits.
sub sloppy_parse_xml($) {
	my $xmlfn = shift;
	-f $xmlfn or return undef;

	open my $fh, '<', $xmlfn
		or die "ERROR: cannot read XML from $xmlfn: $!\n";

	my %data;
	while(my $line = $fh->getline) {
		$data{$1} = $2 if $line =~ m!\<([^>]+)\>([^<]+)</\1>!;
	}
#use Data::Dumper;
#warn Dumper \%data;

	$fh->close
		or die "ERROR while reading $xmlfn: $!\n";

	\%data;
}

sub _os_info_legacy_convert() {
	# All Linux'es have moved to a os-release file, but old set-ups may
	# still miss it.  Fake the file
	my %info;

	if(open my $fh, '<', '/etc/system-release-cpe') {
		# RedHad 6
		my $cpe = $info{CPE_NAME} = $fh->getline;

		# cpe:/o:redhat:enterprise_linux:6server:ga:server
		($info{ID}, $info{VERSION_ID}) = (split /\:/, $cpe)[2,4];
		$fh->close;
	}

	if(open my $fh, '<', '/etc/redhat-release') {
		$info{PRETTY_NAME} = $fh->getline;
		$fh->close;
	}

	\%info;
}

1;
