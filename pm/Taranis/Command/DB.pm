# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::DB;

use warnings;
use strict;

use Carp   qw(confess);
use POSIX  qw(strftime);

use Taranis::Database          qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database);

my %handlers = (
	'archive'  => \&db_archive,
	'close-opened' => \&db_close_opened,
);

Taranis::Commands->plugin(db => {
	handler       => \&db_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'before|b=s',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  archive [-b]         move untagged items before DATE to other tables
  close-opened         remove "opened_by" locks from 

OPTIONS:
  --before|-b DATE     DATE like 20170108 or +3d
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
sub db_archive($);
sub before_date($);
sub exclude_tagged_items($);
sub show_row_counts($);
sub archive_email_items($$$);
sub delete_archived_email_items($);
sub archive_items($$$);
sub delete_archived_items($$$);
sub archive_identifiers($);
sub delete_archived_identifiers($);
sub reinitialize_tables($@);
sub step($);

#    print "Archive records before day (yyyymmdd or +3d): ";

sub db_archive($) {
	my $args   = shift;

	$| = 1;  # flush print() immediately

	my $before = before_date $args->{before}
		or die "ERROR: the '--before' parameter is required\n";

	print "Archiving records before $before\n";

	my $db     = Database->{simple};

	$start     = time;
	step "record count before archiving:";
	show_row_counts $db;

	step "Collecting tagged items, to be excluded";
	my $excludeTaggedAssesItems = exclude_tagged_items($db) || '1=1';

	#XXX Probably these do not need to be all together in one transaction;
	#XXX pair-wise would suffice.  That may speed it up.

	withTransaction {

    	step "Archiving email records (table email_item)";
		archive_email_items $db, $before, $excludeTaggedAssesItems;

    	step "Delete archived email items";
		delete_archived_email_items $db;

    	step "Archiving feed records (table item)";
		archive_items $db, $before, $excludeTaggedAssesItems;

    	step "Deleting archived feed records";
    	$excludeTaggedAssesItems =~ s/item/i2/g;
		delete_archived_items $db, $before, $excludeTaggedAssesItems;

    	step "Archiving identifiers (table identifier)";
		archive_identifiers $db;

    	step "Delete archived identifiers";
		delete_archived_identifiers $db;

		step "Completing transaction";

	};  # end of sub

	step "Re-analyze modified tables";
	reinitialize_tables $db, qw(identifier email_item item);

	step "Archiving successfully completed!";

	print "\nRecord count after archiving:\n";
	show_row_counts $db;
}

### HELPERS

sub before_date($) {
	my $when = shift or return;

	if($when =~ m/^\s*(\d\d\d\d)(\d\d)(\d\d)\s*$/) {
    	my ($year, $month, $day) = ($1, $2, $3);
    	$year  >= 2000 && $year  <= 2100 or die "ERROR: invalid year '$year'\n";
    	$month >= 1    && $month <= 12 or die "ERROR: invalid month '$month'\n";
    	$day   >= 1    && $day   <= 31 or die "ERROR: invalid day '$day'\n";
    	return "$year$month$day";
	}

	if($when =~ m/^\s*\+([0-9]+)d\s*$/ ) {
    	# +1d will mean: keep yesterday as a whole as well
    	my $secs_ago = $1 * SECS_PER_DAY;
    	return strftime "%Y%m%d", localtime(time - $secs_ago);
	}

   	die "ERROR: date format: <yyyymmdd> or +<n>d\n";
}
 
sub exclude_tagged_items($) {
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

sub show_row_counts($) {
	my $db = shift;

    foreach my $set ( qw/item email_item identifier/ ) {
        my ($keep) = $db->query("SELECT COUNT(*) FROM $set")->flat;
        printf "  %-40s %10d\n", $set, $keep;

        my ($arch) = $db->query("SELECT COUNT(*) FROM ${set}_archive")->flat;
        printf "  %-40s %10d\n", "${set}_archive", $arch;

        printf "  %-40s %10d\n\n", 'TOTAL', $keep + $arch;
    }
}

sub archive_email_items($$$) {
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

sub delete_archived_email_items($) {
	my ($db) = @_;

   	$db->query( <<_DELETE_EMAIL );
 DELETE FROM email_item
  WHERE digest IN
    ( SELECT digest
      FROM email_item_archive
    )
_DELETE_EMAIL
}

sub archive_items($$$) {
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

sub delete_archived_items($$$) {
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

sub archive_identifiers($) {
	my ($db) = @_;

    $db->query( <<'_ARCHIVE_IDS' );
  INSERT INTO identifier_archive
  SELECT id.*
    FROM identifier id
         LEFT JOIN item i USING (digest)
   WHERE i.digest IS NULL;
_ARCHIVE_IDS
}

sub delete_archived_identifiers($) {
	my ($db) = @_;

    $db->query( <<'_DELETE_IDS' );
 DELETE FROM identifier id 
  USING identifier_archive ar 
  WHERE id.digest = ar.digest;
_DELETE_IDS
}
 
sub reinitialize_tables($@) {
	my ($db, @tables) = @_;
	for my $table (@tables) {
    	$db->query("ANALYZE $table");
    	$db->query("ANALYZE ${table}_archive");
	}
}

sub step($) {
    my $text  = shift;
    my $now   = time;
    my $stamp = strftime "%H:%M:%S", localtime($now);

    printf "(+%5ds) %s %s\n", $now-$start, $stamp, $text;
}

### subcommand close-opened

sub db_close_opened($) {
	my $args = shift;

	my $db     = Database->{simple};
	$db->query('UPDATE analysis SET opened_by = NULL WHERE opened_by IS NOT NULL');
	$db->query('UPDATE publication SET opened_by = NULL WHERE opened_by IS NOT NULL');
}

1;
