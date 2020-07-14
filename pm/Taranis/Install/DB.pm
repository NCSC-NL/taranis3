# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::DB;
use base 'Exporter';

use warnings;
use strict;

use Taranis::Install::Config qw(config_release);

use Carp         qw(confess);
use DBIx::Simple ();

our @EXPORT = qw(
	connect_db
	schema_version
	create_taranis_table
	database_load_sql
);

sub connect_db(;$) {
	my $version = shift;
	my $release = config_release $version;

	my $dbconfig = $release->{database} or confess;
	my ($dbname, $dbuser, $dbpasswd, $dbhost, $dbport) =
		@{$dbconfig}{ qw/name user password host port/ };

	$dbport ||= $dbhost =~ s/:([0-9]+)$// ? $1 : 5432;

	my $dsn = "dbi:Pg:dbname=$dbname";
	$dsn   .= ";host=$dbhost" if $dbhost ne 'peer';
	$dsn   .= ";port=$dbport" if $dbport != 5432;

	my  $db = DBIx::Simple->connect($dsn, $dbuser, $dbpasswd,
    	{ AutoCommit => 1, RaiseError => 1 }
	);

	$db;
}

sub create_taranis_table($) {
	my $db = shift;

	$db->query(<<'__CREATE_TABLE')
CREATE TABLE taranis (
	key   CHARACTER VARYING(50) NOT NULL,
	value TEXT
);
INSERT INTO taranis VALUES ('schema_version', 3300);
__CREATE_TABLE
}

sub schema_version($;$) {
	my ($db, $new_version) = @_;

	if(defined $new_version) {
		$db->query(<<'__VERSION_SET', $new_version);
UPDATE taranis SET value = ? WHERE key = 'schema_version'
__VERSION_SET
		return $new_version;
	}

	my ($version) = $db->query( <<'__VERSION_GET')->list;
SELECT value FROM taranis WHERE key = 'schema_version'
__VERSION_GET

	$version;
}

sub database_load_sql($$) {
	my ($db, $fn) = @_;

	my $release  = config_release;
	my $dbconfig = $release->{database};
	my ($dbname, $dbuser, $dbhost) =
		@{$dbconfig}{ qw/name user host/ };

	#XXX MO: I could not find a way to load (large) sql files into
	#    Postgresql via an instruction.  The only trick seems to be
	#	 via a command-line call to psql

	# psql uses TMPDIR, but also runs as a different user: lets change
	# TMPDIR here to stop the "cannot chdir into..." warning.
	local $ENV{TMPDIR} = '/tmp';

	system
		'psql',
		'--username' => $dbuser,
		'--dbname'   => $dbname,
		'--file'     => $fn,
		( $dbhost eq 'peer' ? () : '--host' => $dbhost ),
		'--single-transaction',
		'--quiet'
		and die "ERROR: failed loading sql file $fn: $!\n";
}

1;
