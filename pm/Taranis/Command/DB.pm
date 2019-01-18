# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::DB;

use warnings;
use strict;

use Carp    qw(confess);
use POSIX   qw(strftime);

use Taranis qw(val_date);
use Taranis::Database          qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database);
use Taranis::Install::DB       qw(schema_version);

my %handlers = (
	'archive'        => \&db_archive,
	'close-opened'   => \&db_close_opened,
	'remove-items'   => \&db_remove_items,
	'schema-version' => \&db_schema_version,
);

Taranis::Commands->plugin(db => {
	handler       => \&db_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'before|b=s',
		'schema|s=i',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  archive [-b]          move untagged items before DATE to other tables
  close-opened          remove "opened_by" locks from
  remove-items [-b] SOURCES  remove items from specific sources
  schema-version [-s]   show or change the version of the db schema

OPTIONS:
  --before|-b DATE     DATE like 20170108 or +3d
  --schema|-s SCHEMA   Fix the schema version number
__HELP
} );

sub db_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$args{log}  = 1 unless exists $args{log};
	$handler->(\%args);
}


use constant SECS_PER_DAY => 24 * 60 * 60;

my $start;

sub _before_date($);
sub _exclude_tagged_items($);
sub _show_row_counts($);
sub _archive_email_items($$$);
sub _delete_archived_email_items($);
sub _archive_items($$$);
sub _delete_archived_items($$$);
sub _archive_identifiers($);
sub _delete_archived_identifiers($);
sub _reinitialize_tables($@);
sub _step($);

#    print "Archive records before day (yyyymmdd or +3d): ";

sub db_archive($) {
	my $args   = shift;

	my $before = _before_date $args->{before}
		or die "ERROR: the '--before' parameter is required\n";

	$| = 1;  # flush print() immediately
	print "Archiving records before $before\n";

	my $db     = Database->simple;

	$start     = time;
	_step "record count before archiving:";
	_show_row_counts $db;

	_step "Collecting tagged items, to be excluded";
	my $excludeTaggedAssesItems = _exclude_tagged_items($db) || '1=1';

	#XXX Probably these do not need to be all together in one transaction;
	#XXX pair-wise would suffice.  That may speed it up.

	withTransaction {

    	_step "Archiving email records (table email_item)";
		_archive_email_items $db, $before, $excludeTaggedAssesItems;

    	_step "Delete archived email items";
		_delete_archived_email_items $db;

    	_step "Archiving feed records (table item)";
		_archive_items $db, $before, $excludeTaggedAssesItems;

    	_step "Deleting archived feed records";
    	$excludeTaggedAssesItems =~ s/item/i2/g;
		_delete_archived_items $db, $before, $excludeTaggedAssesItems;

    	_step "Archiving identifiers (table identifier)";
		_archive_identifiers $db;

    	_step "Delete archived identifiers";
		_delete_archived_identifiers $db;

		_step "Completing transaction";

	};  # end of sub

	_step "Re-analyze modified tables";
	_reinitialize_tables $db, qw(identifier email_item item);

	_step "Archiving successfully completed!";

	print "\nRecord count after archiving:\n";
	_show_row_counts $db;
}

### HELPERS

sub _before_date($) {
	my $when = shift or return;

	if($when =~ m/^\s*\+(\d+)d\s*$/a ) {
    	# +1d will mean: keep yesterday as a whole as well
    	my $secs_ago = $1 * SECS_PER_DAY;
    	return strftime "%Y-%m-%d", localtime(time - $secs_ago);
	}

	if(my $date = val_date $when) {
		return $date;
	}

   	die "ERROR: date format: <yyyymmdd>, <yyyy-mm-dd>, or +<n>d\n";
}

 
sub _exclude_tagged_items($) {
	my $db = shift;

	my @tagged_items = $db->query( <<'_TAGGED_ITEMS' )->flat;
 SELECT DISTINCT item_id
   FROM tag_item
  WHERE item_table_name = 'item'
_TAGGED_ITEMS

	print "excluding ".@tagged_items. " tagged items\n";

	#XXX maybe fastter:  "item.digest NOT IN (".join(',',@tagged_items).")";
	join ' AND ',
   		map "item.digest != '$_'", @tagged_items;
}

sub _show_row_counts($) {
	my $db = shift;

    foreach my $set ( qw/item email_item identifier/ ) {
        my ($keep) = $db->query("SELECT COUNT(*) FROM $set")->flat;
        printf "  %-40s %10d\n", $set, $keep;

        my ($arch) = $db->query("SELECT COUNT(*) FROM ${set}_archive")->flat;
        printf "  %-40s %10d\n", "${set}_archive", $arch;

        printf "  %-40s %10d\n\n", 'TOTAL', $keep + $arch;
    }
}

sub _archive_email_items($$$) {
	my ($db, $before, $excludeTaggedAssesItems) = @_;

   	$db->query( <<_ARCHIVE_EMAIL, $before );
 INSERT INTO email_item_archive
  ( SELECT email_item.*
      FROM email_item
      JOIN item ON item.digest = email_item.digest
      LEFT OUTER JOIN item_analysis ON item.digest = item_analysis.item_id
      LEFT OUTER JOIN item_publication_type
           ON item_publication_type.item_digest = item.digest
      LEFT OUTER JOIN dossier_item ON dossier_item.assess_id = item.digest
     WHERE item.is_mail = 't'
       AND item.created < ?
       AND item_publication_type.item_digest IS NULL
       AND item_analysis.item_id  IS NULL
       AND dossier_item.assess_id IS NULL
       AND $excludeTaggedAssesItems
  )
_ARCHIVE_EMAIL
}

sub _delete_archived_email_items($) {
	my ($db) = @_;

   	$db->query( <<_DELETE_EMAIL );
 DELETE FROM email_item
  WHERE digest IN
    ( SELECT digest
      FROM email_item_archive
    )
_DELETE_EMAIL
}

sub _archive_items($$$) {
	my ($db, $before, $excludeTaggedAssesItems) = @_;

    $db->query( <<_ARCHIVE_ITEMS );
 INSERT INTO item_archive
 SELECT * FROM item
  WHERE created < '$before'
   AND digest IN 
     ( SELECT item.digest FROM item
       LEFT OUTER JOIN item_analysis ON item_analysis.item_id = item.digest
       LEFT OUTER JOIN item_publication_type
                         ON item_publication_type.item_digest = item.digest
       LEFT OUTER JOIN dossier_item ON dossier_item.assess_id = item.digest
       WHERE item_analysis.item_id             IS NULL
         AND item_publication_type.item_digest IS NULL
         AND dossier_item.assess_id            IS NULL
     )
    AND $excludeTaggedAssesItems
_ARCHIVE_ITEMS
}

sub _delete_archived_items($$$) {
	my ($db, $before, $excludeTaggedAssesItems) = @_;;

    $db->query( <<_DELETE_FEEDS );
  DELETE FROM item
   WHERE digest IN
    ( SELECT i2.digest
      FROM item i2
           LEFT OUTER JOIN item_analysis ON item_analysis.item_id = i2.digest
           LEFT OUTER JOIN item_publication_type
                        ON item_publication_type.item_digest = i2.digest
      LEFT OUTER JOIN dossier_item ON dossier_item.assess_id = i2.digest
      WHERE i2.created < '$before'
        AND item_publication_type.item_digest IS NULL
        AND item_analysis.item_id             IS NULL
        AND dossier_item.assess_id            IS NULL
        AND $excludeTaggedAssesItems
    )
_DELETE_FEEDS
}

sub _archive_identifiers($) {
	my ($db) = @_;

    $db->query( <<'_ARCHIVE_IDS' );
  INSERT INTO identifier_archive
  SELECT id.*
    FROM identifier id
         LEFT JOIN item i USING (digest)
   WHERE i.digest IS NULL;
_ARCHIVE_IDS
}

sub _delete_archived_identifiers($) {
	my ($db) = @_;

    $db->query( <<'_DELETE_IDS' );
 DELETE FROM identifier id 
  USING identifier_archive ar 
  WHERE id.digest = ar.digest;
_DELETE_IDS
}
 
sub _reinitialize_tables($@) {
	my ($db, @tables) = @_;
	for my $table (@tables) {
    	$db->query("ANALYZE $table");
    	$db->query("ANALYZE ${table}_archive");
	}
}

sub _step($) {
    my $text  = shift;
    my $now   = time;
    my $stamp = strftime "%H:%M:%S", localtime($now);

    printf "(+%5ds) %s %s\n", $now-$start, $stamp, $text;
}

### subcommand close-opened

sub db_close_opened($) {
	my $args = shift;
	my $db   = Database->simple;
	$db->query('UPDATE analysis SET opened_by = NULL WHERE opened_by IS NOT NULL');
	$db->query('UPDATE publication SET opened_by = NULL WHERE opened_by IS NOT NULL');
}

### subcommand remove-items

sub _remove_from($$$) {
	my ($db, $source, $before) = @_;

	$db->query(<<'__DELETE_ANALYSIS', $source, $before);
DELETE FROM item_analysis
 WHERE item_id IN
   (SELECT DISTINCT(item_analysis.item_id)
      FROM item
           JOIN item_analysis ON item_analysis.item_id = item.digest
     WHERE item.source  = ?
       AND item.created < ?
   )
__DELETE_ANALYSIS

    $db->query(<<'__DELETE_TYPE', $source, $before);
DELETE FROM item_publication_type
 WHERE item_digest IN
   (SELECT digest
      FROM item
     WHERE item.source  = ?
       AND item.created < ?
   )
__DELETE_TYPE

	$db->query(<<'__DELETE_ITEMS', $source, $before);
DELETE FROM item
 WHERE source  = ?
   AND created < ?
__DELETE_ITEMS

	$db->query(<<'__DELETE_ITEMS', $source, $before);
DELETE FROM item_archive
 WHERE source  = ?
   AND created < ?
__DELETE_ITEMS

}

sub db_remove_items($) {
    my $args   = shift;

    my $before = _before_date $args->{before}
        or die "ERROR: the '--before' parameter is required\n";

	my $sources = $args->{files} || [];
	@$sources
		or die "ERROR: you must specify one or more sources\n";

	my $db     = Database->simple;

	$| = 1;  # flush print() immediately
	print "Removing items collected before $before\n";

	foreach my $source (@$sources) {
		print " . cleaning up $source\n";
		_remove_from $db, $source, $before;
	}
}

sub db_schema_version($) {
	my $args   = shift;

	my $files = $args->{files} || [];
	die "ERROR: no filenames expected for this sub-command\n" if @$files;

	my $db  = Database->simple;
	my $old = schema_version $db;
	my $new = $args->{schema};

	if(defined $new && $new != $old) {
		print "The old database schema version was $old\n";

		schema_version $db, $new;
		print "The new database schema version is $new\n";
	} else {
		print "The database version is $old\n";
	}
}

1;
