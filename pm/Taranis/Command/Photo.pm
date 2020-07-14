# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Photo;

use warnings;
use strict;

use Carp      qw(confess);
use Text::CSV ();

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::CsvBuilder;

sub photo_control(%);
sub photo_export($);
sub all_products_in_csv($$);
sub select_constituents_in_csv($$$);

my %handlers = (
	export           => \&photo_export,
	import           => \&photo_import,
	'cleanup-issues' => \&photo_cleanup_issues,
);

Taranis::Commands->plugin(photo => {
	handler       => \&photo_control,
	requires_root => 0,
	sub_commands  => [ keys %handlers ],
	getopt        => [
		'constituents|c=s@',
		'empty|e!',
		'output|o=s',
		'quote|q',
		'separator|s=s',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  export [-ceopqs]    create CSV template with
  import              interactive import a CSV
  cleanup-issues      removes all resolved issues from photo imports

EXPORT OPTIONS:
  -c --constituents NAMES  search constituent(s)
  -e --empty               export empty photo
  -o --output FILE         print to file
  -q --quote               quote all fields
  -s --separator CHAR      specify separator character (default comma
__HELP
} );

my %softwareHardwareType = (
	a => 'Applicatie',
	h => 'Hardware',
	o => 'Operating System'
);

sub photo_control(%) {
	my %args = @_;

	my $subcmd = $args{sub_command}
		or confess;

	my $handler = $handlers{$subcmd}
		or confess $subcmd;

	$handler->(\%args);
}

###
### PHOTO EXPORT
###

sub photo_export($) {
	my $args  = shift;
	my $sep   = $args->{separator} || ',';

	my $outfn = $args->{output};
	my $csv   = Taranis::CsvBuilder->new(
		file      => $outfn,
		sep_char  => $sep,
		quote_all => $args->{quote},
	);

	my $want_all     = $args->{empty};
	my @constituents = map {split /\,/} @{$args->{constituents} || []};

	$want_all || @constituents
		or die "ERROR: export requires either -e or constituents\n";

	my $db = Database->simple;

	if($want_all) {
		all_products_in_csv $db, $csv;
	} else {
		select_constituents_in_csv $db, $csv, \@constituents;
	}

	if($outfn) {
		print $csv->csv2file ? "$outfn created.\n" : $csv->print_error;
	} else {
		print $csv->print_csv;
	}
}

### HELPERS

sub all_products_in_csv($$) {
	my ($db, $csv) = @_;

	my $products = $db->query(<<'__SEARCH_PRODUCTS');
 SELECT sh.producer, sh.name, sht.description, sh.cpe_id
   FROM software_hardware sh
        JOIN soft_hard_type AS sht ON sh.type = sht.base
  WHERE NOT sh.deleted
    AND sht.base IN ('a', 'h', 'a')
  GROUP BY sh.producer, sh.name, sht.description, sh.cpe_id
  ORDER BY sh.producer, sh.name, sht.description, sh.cpe_id
__SEARCH_PRODUCTS

	$csv->addLine( "Vendor", "Product", "CPE", "Type" );
	my @field_order = qw/producer name cpe_id description/;

	while(my $product = $products->hash) {
		$product->{name} =~ s/\s+/ /g;
		$csv->addLine( @{$product}{@field_order} );
	}
}

sub select_constituents_in_csv($$$) {
	my ($db, $csv, $victims) = @_;

	my $find_constit = join ' OR ', 'cg.name ILIKE ?' x @$victims;

	my $products = $db->query(<<__SEARCH_PRODUCTS, @$victims);
 SELECT sh.producer, sh.name AS product, sht.description, sh.cpe_id
   FROM software_hardware AS sh
	    JOIN soft_hard_usage   AS shu  ON sh.id   = shu.soft_hard_id
	    JOIN constituent_group AS cg   ON cg.id   = shu.group_id
	    JOIN soft_hard_type    AS sht  ON sh.type = sht.base
  WHERE NOT deleted
    AND ($find_constit)
  GROUP BY sh.producer, sh.name, sht.description, sh.cpe_id 
  ORDER BY sh.producer, sh.name, sht.description, sh.cpe_id
__SEARCH_PRODUCTS

	$csv->addLine( "Vendor", "Product", "CPE", "Type" );

	my @field_order = qw/producer product cpe_id description/;
	while(my $record = $products->hash) {
		$record->{product} =~ s/\s+/ /g;
	    $csv->addLine(@{$record}{@field_order});
	}
}

###
### PHOTO IMPORT
###

sub get_constituent($);
sub print_skipped($$$);
sub read_csv_file();
sub validate_import($$);
sub current_photo($$$);
sub show_photo_details($$);
sub import_sh_usage($$$$);
sub print_boxed(@);
sub print_boxed_error($$);
sub ask($);
sub ask_yn($);

my $normal      = "\033[0m"; # normal font
my $bold        = "\033[1m"; # bold font
my $dashed_line = '-' x 80;

sub photo_import($) {
	my $args = shift;

	my $db     = Database->simple;
	my $doTest = ask_yn "Perform test run (photo will not be changed)";
	my ($constituentName, $constituentId) = get_constituent $db;
	my ($import, $duplicates) = read_csv_file;

	if(@$duplicates) {
		print "duplicate records found in csv:\n";
		print "+$dashed_line+\n";
		print_boxed $_->{producer}, $_->{name}, $_->{type}
			for @$duplicates;
	}

	print "number of records: ".@$import."\n";

	my ($take, $skipped, $notInUse) = validate_import $db, $import;

	print "Skipped: ${bold}".@$skipped."${normal}\n" if @$skipped;
	print "Software/hardware not in use by other constituents: ${bold}"
    	. @$notInUse."${normal}\n" if @$notInUse;
	print "Number of records to import: ${bold}".@$take."${normal}\n";

	if(@$skipped) {
		my $proceed = ask_yn @$skipped." records of import file cannot be imported. Proceed?";

		if( ! $proceed) {
			print "quit import\n\n";
			exit 0;
		}
	}

	my ($deletePhoto, $deletedCurrentPhoto) =
		current_photo $db, $constituentName, $constituentId;

	my $imported;
	withTransaction {

		if($deletePhoto) {
			print "\n${bold}ACTION: deleting photo...\n${normal}";
			$doTest or $db->query( <<'__DELETE', $constituentId);
DELETE FROM soft_hard_usage WHERE group_id = ?
__DELETE

			print "deleted usage for constituent group $constituentId\n";
			print "...no worries, this is a test run, nothing is deleted yet...\n"
				if $doTest;
		}

		print "\n${bold}ACTION: importing photo...${normal}\n\n";
		import_sh_usage $db, $take, $constituentId, $doTest;
		$imported += @$take;
	};

	print "${bold}STATS --> imported: $imported, "
    	. "skipped: ".@$skipped.", "
    	. "deleted: $deletedCurrentPhoto, "
    	. "duplicates in csv: ".@$duplicates.", "
    	. "not in use: ".@$notInUse
		. "\n${normal}";

	print_skipped $skipped, $notInUse, $constituentName;

	print "\nEND OF IMPORT\n\n";
}

#### HELPERS

sub get_constituent($) {
	my ($db) = @_;

	my ($name, $id);
	while(1) {
		$name = ask "Constituent name: ";
		length $name or next;

		my ($id) = $db->query(<<'__GET_CID', $name)->list;
 SELECT id FROM constituent_group WHERE name ILIKE ?  AND status = 0
__GET_CID

		defined $id and last;
		print "constituent '$name' does not exist.\n";
	}

	($name, $id);
}

sub print_skipped($$$) {
	my ($skipped, $notInUse, $constituentName) = @_;

	@$skipped || @$notInUse
		or return;

	my $do_print = ask_yn "Print skipped records and records not in use by other constituents to file?";
	$do_print or return;

	my $outfile;
	while(!$outfile ) {
		$outfile = ask "Print file: ";

		open PRINTFILE, ">", $outfile
			and last;

		print "$!\n";
	}

	print "\n${bold}ACTION: printing to file...\n${normal}";
	my $old_out = select PRINTFILE;

	if(@$skipped) {
		print "IMPORT SCRIPT SKIPPED RECORDS FOR $constituentName\n\n";
		print "+$dashed_line+\n";
		print_boxed $_->{producer}, $_->{name}, $_->{type}, $_->{_pedReason}
			for @$skipped;
	}

	if(@$notInUse) {
		print "\n\n" if @$skipped;
		print "IMPORT SCRIPT RECORDS NOT IN USE BY OTHER CONSTITUENTS\n\n";
		print "+$dashed_line+\n";
		print_boxed $_->{producer}, $_->{name}, $_->{type}
			for @$notInUse;
	}

	close PRINTFILE;
	select $old_out;
}

sub read_csv_file() {
	local *CSV;

	while(1) {
		my $csvFile = ask "CSV file: ";
		length $csvFile or redo;

		open CSV, "<", $csvFile	
			and last;

		print "$!\n";
		return ();
	}

	print "\n${bold}ACTION: reading CSV file...\n${normal}";
	my %seen;

	my (@import, @duplicates);
	my $csv = Text::CSV->new;

  LINE:
	while(<CSV>) {
		unless($csv->parse($_)) {
			my $err = $csv->error_input;
			print "Failed to parse line: $err\n";
			next LINE;
		}

		my ($producer, $name, $type) = $csv->fields;
		my $record = { producer => $producer, name => $name, type => $type};
		my $unique = lc "$producer\0$name\0$type";
		if($seen{$unique}++) { push @duplicates, $record }
		else                 { push @import,     $record }
	}
	print "\n";
	close CSV;

	(\@import, \@duplicates);
}

sub validate_import($$) {
	my ($db, $import) = @_;

	print "\n${bold}ACTION: checking if import software/hardware exists...\n\n${normal}";

	my (@import, @skipped, @notInUse);

  IMPORT:
	foreach my $record (@$import) {
		my $producer = $record->{producer};
		my $name     = $record->{name};
		my ($cnt)    = $db->query( <<'__MATCH_PRODUCT', $producer, $name)->list;
 SELECT COUNT(*) AS cnt
   FROM software_hardware
  WHERE producer ILIKE ?  AND  name ILIKE ?
    AND NOT deleted
__MATCH_PRODUCT

		if($cnt==0) {
			my $not_found = $import->{skippedReason} = "Not found in database";
			print  "+$dashed_line+\n" unless @skipped;
			print_boxed_error $record, $not_found;

			push @skipped, $import;
			next IMPORT;
		}

		if($cnt==1) {
			my ($usage) = $db->query( <<'__COUNT_USAGE', $producer, $name)->list;
 SELECT COUNT(shu.*) AS cnt
   FROM soft_hard_usage shu
        JOIN software_hardware sh ON shu.soft_hard_id = sh.id
  WHERE producer ILIKE ?  AND  name ILIKE ?
    AND NOT deleted
__COUNT_USAGE

			push @import, $import;
			push @notInUse, $record if !$usage;
			next IMPORT;
		}

		# cnt > 1
		print "+$dashed_line+\n" unless @skipped;
		my $repeated = $import->{skippedReason} = "Found $cnt times in database";
		print_boxed_error $record, $repeated;
		push @skipped, $import;
	}

	(\@import, \@skipped, \@notInUse);
}

sub current_photo($$$) {
	my ($db, $constituentName, $constituentId) = @_;

	print "\n${bold}ACTION: checking for existing photo for $constituentName ...${normal}\n";

	my $has_usage = $db->query( <<'__FIND_CONSTITUENT', $constituentId)->list;
SELECT 1 FROM soft_hard_usage WHERE group_id = ?
__FIND_CONSTITUENT

	if(! $has_usage) {
		print "no photo found\n";
		return (0, 0);
	}

	my $photo_rows = show_photo_details $db, $constituentId;

	my $action;
	$action = ask "A photo with ${bold}$photo_rows${normal} items of constituent $constituentName already exists. Do you want to delete (and insert new photo) or quit import? [d|q]: "
		until $action =~ /^[qd]/i;

	if($action =~ /^q/i) {
		print "quit import\n\n";
		exit 0;
	}

	(1, $photo_rows);
}

sub show_photo_details($$) {
	my ($db, $constituentId) = @_;

	print "Current photo details:\n";

	my $photo = $db->query( <<'__COLLECT_PHOTO', $constituentId);
 SELECT sh.producer, sh.name AS product, sht.description
   FROM software_hardware sh
        JOIN soft_hard_usage AS shu ON sh.id   = shu.soft_hard_id
        JOIN soft_hard_type  AS sht ON sh.type = sht.base
  WHERE shu.group_id = ?
  ORDER BY sh.producer, sh.name, sht.description
__COLLECT_PHOTO

	my $products = 0;
	print "+$dashed_line+\n";
	while(my $rec = $photo->hash) {
		print_boxed $rec->{producer}, $rec->{product}, $rec->{description};
		$products++;
	}

	$products;
}

sub import_sh_usage($$$$) {
	my ($db, $import, $constituentId, $doTest) = @_;

	foreach my $record (@$import) {
		my $producer = $record->{producer};
		my $name     = $record->{name};

		$doTest or $db->query(<<'__INSERT', $constituentId, $producer, $name);
 INSERT INTO soft_hard_usage (group_id, soft_hard_id)
 VALUES (?, (SELECT id FROM software_hardware
             WHERE producer ILIKE ?  AND name ILIKE ? AND NOT deleted
        )   )
__INSERT

		print "imported '$producer $name'\n";
	}

	print "...no worries, this is a test run, nothing is imported yet...\n"
		if $doTest;
}

sub print_boxed(@) {
	my @lines = @_;
	printf "| %-80s |\n", $_ for @lines;
	print "+$dashed_line+\n";
}

sub print_boxed_error($$) {
	my ($record, $error) = @_;
	print_boxed $record->{producer}, $record->{name}, $error;
}

sub ask($) {
	my $message = shift;

	my $answer  = '';
	until(length $answer) {
		print "$message\n";
		my $answer = <STDIN>;
		$answer =~ s/^\s*//;
		$answer =~ s/\s*$//;
	}

	$answer;
}

sub ask_yn($) {
	my $message = shift;
	my $answer;
	$answer = ask "$message [yn]:"
		until $answer =~ /^[yn]/i;
	$answer =~ /^y/i;
}
 
### CLEAN ISSUES

sub photo_cleanup_issues($) {
	my $args = shift;

	my $db = Database->simple;

	# Remove all remaining records about a successfully imported photo
	$db->query( <<'__A' );
  DELETE FROM import_photo_software_hardware
  WHERE import_sh IN
    ( SELECT ish.id
	    FROM import_software_hardware ish
	         LEFT JOIN import_issue ii ON ish.issue_nr = ii.id
	   WHERE ii.status = 3  OR  ish.issue_nr IS NULL
    )
   AND photo_id IN
    ( SELECT id
	    FROM import_photo
	   WHERE imported_on IS NOT NULL
    )
__A

	$db->query( <<'__B');
 DELETE FROM import_software_hardware
  WHERE id IN
    ( SELECT ish.id
	    FROM import_software_hardware ish
	         LEFT JOIN import_issue ii  ON  ish.issue_nr = ii.id
	   WHERE ii.status = 3  OR  ish.issue_nr IS NULL
    )
   AND id NOT IN
    ( SELECT DISTINCT import_sh
      FROM import_photo_software_hardware
    )
__B

	# Delete resolved issues
	$db->query( <<'__C' );
 DELETE FROM import_issue
  WHERE status = 3
    AND id NOT IN
     ( SELECT DISTINCT followup_on_issue_nr
         FROM import_issue
		WHERE status <> 3  AND  followup_on_issue_nr IS NOT NULL
	 )
__C

}

1;
