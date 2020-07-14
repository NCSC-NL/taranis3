#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database);

############## EDIT SETTINGS BELOW #########

#my $categoryName = '';
#my $wordlistDescription = '';
#my $andWordlistDescription = ''; # optional

############## NOW STOP EDITING ############

my ( $catName, $wlDescription, $andWlDescription );
my $dbh1 = Database;

while ( $catName eq '' ) {
	print "Enter category name: ";
	$catName = <>;
	$catName =~ s/\n$//;
	if ( !$dbh1->checkIfExists( { name => $catName }, 'category', 'IGNORECASE' ) ) {
		print "!! did not find a matching category !!\n";
		$catName = '';
	}

	if ( $catName ) {
		while ( $wlDescription eq '' ) {
			print "Enter the wordlist description: ";
			$wlDescription = <>;
			$wlDescription =~ s/\n$//;
			if ( !$dbh1->checkIfExists( { description => $wlDescription }, 'wordlist', 'IGNORECASE' ) ) {
				print "!! did not find a matching wordlist !!\n";
				$wlDescription = '';
			}
		}
	}
	
	if ( $catName && $wlDescription ) {
		while ( $andWlDescription eq '' ) {
			print "Enter the AND wordlist description (or enter to leave it blank): ";
			$andWlDescription = <>;
			$andWlDescription =~ s/\n$//;
			if ( !$andWlDescription ) {
				$andWlDescription = 'SKIPMENOW';
			} elsif ( !$dbh1->checkIfExists( { description => $andWlDescription }, 'wordlist', 'IGNORECASE' ) ) {
				print "!! did not find a matching wordlist !!\n";
				$andWlDescription = '';
			}
		}
	}
	
	if ( $catName && $wlDescription && $andWlDescription ) {
		$andWlDescription = undef if ( $andWlDescription =~ /^SKIPMENOW$/ );
		setWordlist( $catName, $wlDescription, $andWlDescription );
	}
}

sub setWordlist {
	my ( $categoryName, $wordlistDescription, $andWordlistDescription ) = @_;
	my $dbh = Database;

	my $catSelectStmnt = "SELECT * FROM category WHERE name ilike ?;";
	$dbh->prepare( $catSelectStmnt );
	$dbh->executeWithBinds( $categoryName );
	
	my $category = $dbh->fetchRow();
	
	my @wordlistIDs;
	my $wlSelectStmnt = "SELECT * FROM wordlist WHERE description ilike ?;";
	$dbh->prepare( $wlSelectStmnt );
	
	foreach ( $wordlistDescription, $andWordlistDescription) {
		$dbh->executeWithBinds( $_ );
		my $wordlist = $dbh->fetchRow();
		if ( $wordlist ) {
			push @wordlistIDs, $wordlist->{id};
		}
	}
	
	if ( 
		$category && 
			( 
				( $wordlistDescription && !$andWordlistDescription && @wordlistIDs == 1 ) 
				|| ( $wordlistDescription && $andWordlistDescription && @wordlistIDs == 2 ) 
			) 
		) {
		
		my @sources;
		my $sourcesSelectStmnt = "SELECT id, sourcename FROM sources WHERE category = ? ORDER BY sourcename";
		
		$dbh->prepare( $sourcesSelectStmnt );
		$dbh->executeWithBinds( $category->{id} );
		while ( $dbh->nextRecord() ) {
			push @sources, $dbh->getRecord();
		}	
		
		my $wordlistSourceInsertStmnt = "INSERT INTO source_wordlist (source_id, wordlist_id, and_wordlist_id) values (?,?,?);";
		my $sourceUpdateStmnt = "UPDATE sources SET use_keyword_matching = true WHERE id = ?;";
		
		withTransaction {
			my $count = 0;
			foreach my $source ( @sources ) {
				print "ADD wordlist to source $source->{sourcename}\n";
				$dbh->prepare( $wordlistSourceInsertStmnt );
				$dbh->executeWithBinds( $source->{id}, $wordlistIDs[0], $wordlistIDs[1] );
				$dbh->prepare( $sourceUpdateStmnt );
				$dbh->executeWithBinds( $source->{id} );
				$count++;
			}
			print "UPDATED $count sources\n";
		};
	} else {
		print "Did not update or add any wordlists to sources.\nPlease check set category name and wordlist descriptions\n";
	}
}
