#!/usr/bin/env perl
# Try to load the actual schema in a new database
# This will not affect the running application.
#
# This logic is closely related to the installation scripts
# install/422.postgres-startup and install/640.db-load
# Please check thise scripts as well when you make changes here.
#
# Preparations:
#    . This only works in an installed Taranis environment
#    . Allow access from user taranis to database testload in hba.conf

use warnings;
use strict;

use Taranis::Install::Config qw(config_release);
use Taranis::Install::DB qw(
	connect_db
	schema_version
    database_load_sql
);
use Data::Dumper;
use DBIx::Simple;
use Test::More;
use Time::HiRes qw(time);

my $dbname = 'testload';

### Configure a temporary database

# The read configuration is cached globally, so we can modify it to
# direct "connect_db" somewhere else.
my $release = config_release;
my $dbconf  = $release->{database} or die;
ok(defined $dbconf->{name}, "Active database name $dbconf->{name}");

$dbconf->{name} = $dbname;
ok(defined $dbconf->{name}, "Test database name $dbconf->{name}");

my $dbuser = $dbconf->{user};
ok(defined $dbuser, "DB user $dbuser");

### Create the database

my $pg = DBIx::Simple->connect("dbi:Pg:dbname=postgres", 'postgres', '',
    { AutoCommit => 1, RaiseError => 1 }
);
ok defined $pg, "Connected to the postgresql server";

eval { $pg->query("DROP DATABASE $dbname") };
$@ or diag "Database $dbname still existed";
$pg->query("CREATE DATABASE $dbname WITH OWNER $dbuser ENCODING 'UTF8'");

### Load the database schema

my $db = connect_db;
ok defined $db, "Connected to the test database";

my $hasname = $db->query('SELECT current_database()')->list;
is $hasname, $dbname, "Checked dbname again";

$db->query('CREATE EXTENSION IF NOT EXISTS lo');
ok 1, "loaded lo";

$db->query('CREATE EXTENSION IF NOT EXISTS pg_trgm');
ok 1, "loaded pg_trgm";

my $full_schema    = "install/db-load/taranis-schema.sql";
ok -f $full_schema, "Using schema $full_schema";

my $start = time;
database_load_sql $db, $full_schema;
my $elapse = sprintf "%d", (time - $start) * 1000;
ok 1, "database schema loaded succesfully in $elapse ms";

### Test the database

my $version = schema_version $db;
cmp_ok $version, '>', 3000, "Schema version $version";

### Remove the test database

undef $db;
$pg->query("DROP DATABASE $dbname");
ok 1, "Dropped database $dbname";

done_testing;
