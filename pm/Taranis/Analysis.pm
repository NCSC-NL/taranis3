# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Analysis;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis qw(:all);
use Tie::IxHash;
use SQL::Abstract::More;
use strict;

my %RATINGDICTIONARY = (
	1 => 'low',
	2 => 'medium',
	3 => 'high',
	4 => 'undefined'
);

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		dbh => Database,
		sql => Sql,
		errmsg => undef,
		result_count => undef,
		limit => 100
	};

	return( bless( $self, $class ) );
}

sub addObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	if ( !exists( $args{table} ) ) {
		$self->{errmsg} = "Missing table argument for routine.";
		return 0;
	}

	my $table = delete $args{table};
	my $newAnalysisId;
	if ( $table eq "analysis" ) {
		$args{id} = $self->getNextAnalysisID();
		$args{status} = "pending" if ( !$args{status} );

		$args{idstring} = " " if ( $args{idstring} eq "" );
		$newAnalysisId = $args{id};
	}

	my ( $stmnt, @bind ) = $self->{sql}->insert( $table, \%args );

	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );
	return $newAnalysisId || 1;
}

sub setAnalysis {
	my ( $self, %updates ) = @_;
	undef $self->{errmsg};

	my %where = ( id => delete( $updates{id} ) );

	if ( exists( $updates{original_status} ) && ( uc( $updates{original_status} ) ne uc( $updates{status} ) ) ) {
		$updates{last_status_change} = nowstring(10);
	}

	delete( $updates{original_status} );

	my ( $stmnt, @bind ) = $self->{sql}->update( "analysis", \%updates, \%where );
	$self->{dbh}->prepare( $stmnt );

	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( defined($result) && ($result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		}
	} else {
		$self->{errmsg} = "Update failed, corresponding id not found in database.";
		return 0;
	}
}

sub getRecordsById {
	my ( $self, %args ) = @_;
	my @records;

	if ( !exists( $args{table} ) ) {
		$self->{errmsg} = "Missing table argument for routine.";
		return 0;
	}

	my $table = delete $args{table};
	my $select = ( $table eq "analysis" ) ? "*, to_char(last_status_change, 'DD-MM-YYYY HH24:MI:SS') AS status_change, to_char(orgdatetime, 'DD-MM-YYYY HH24:MI:SS') AS created, opened_by, owned_by, opened.fullname AS openedbyfullname, owned.fullname AS ownedbyfullname" : "*" ;
	my %where = %args;

	my ( $stmnt, @bind ) = $self->{sql}->select( $table, $select, \%where );

	if ( $table eq 'analysis' ) {
		my %join = (
			"LEFT JOIN users AS opened" => { "opened.username" => "opened_by" },
			"LEFT JOIN users AS owned"  => { "owned.username" => "owned_by" }
		);
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	}

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ) {
		push ( @records, $self->getObject() );
	}

	return \@records;
}

sub loadAnalysisCollection {
	my ( $self, %searchFields ) = @_;

	my $offset = ( $searchFields{offset} =~ /^\d+$/ ) ? delete $searchFields{offset} : "0";
	my %where;
	my @nests;

	my @statuses;
	foreach my $status ( @{ $searchFields{status} } ) {
		push @statuses, { 'upper(status)' => uc( $status ) };
	}

	push @nests, \@statuses;

	if ( exists( $searchFields{search} ) && $searchFields{search} ) {
		my $id_search = $searchFields{search};
		$id_search =~ s/AN|-//gi;

		push @nests, [
			title    => {-ilike => '%'.trim($searchFields{search}).'%'},
			comments => {-ilike => '%'.trim($searchFields{search}).'%'},
			idstring => {-ilike => '%'.trim($searchFields{search}).'%'},
			id       => {-ilike => '%'.trim($id_search).'%'}
		];
	}

	if ( exists( $searchFields{rating} ) && @{ $searchFields{rating} } && scalar( @{ $searchFields{rating} } ) != 4 ) {
		my @rating;
		foreach ( @{ $searchFields{rating} } ) {
			push @rating, rating => $_;
		}
		push @nests, \@rating;
	}

	$where{-nest} = {-and => \@nests } if ( @nests );

	my $select = "an.id, an.title, an.comments, an.rating, an.status, " .
		"to_char( an.orgdatetime, 'DD-MM-YYYY HH24:MI:SS') AS created, " .
		"opened_by, owned_by, opened.fullname AS openedbyfullname, owned.fullname AS ownedbyfullname";

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis an", $select, \%where, "an.id DESC");

	my %join = (
		"LEFT JOIN users AS opened" => { "opened.username" => "an.opened_by" },
		"LEFT JOIN users AS owned"  => { "owned.username" => "an.owned_by" }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{result_count} = $self->{dbh}->getResultCount( $stmnt, @bind );

	$stmnt .= " LIMIT ". $self->{limit} ." OFFSET ".$offset;

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	return $result;
}

sub getNextAnalysisID {
	my $self = shift;

	## First search the database for the maximum ID.

	my $stmnt = "SELECT MAX(id) AS maxid FROM analysis;";
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	my $maxid = $self->{dbh}->{sth}->fetchrow_hashref()->{maxid};

	if ( !$maxid || substr( $maxid, 0, 4 ) ne nowstring(6) ) {
		## Year of current max ID doesn't correspond with current
		## year so set ID tot <year>0000
		$maxid = nowstring(6)."0000";
	}

	## Add one to the maximum ID
	$maxid++;

	return $maxid;
}

sub linkToItem {
	my ( $self, $item_digest, $analysis_id, $set_status, $title ) = @_;

	my $is_ok = 0;
	if ( $self->{dbh}->checkIfExists( {digest => $item_digest}, "item" ) && $analysis_id =~ /^\d*$/g ) {
		$is_ok = 1;
		## The item seems to be an existing one, so move on
		## Insert a reference to the item and the analysis
		## into the item_analysis table so now they are linked

		my ( $stmnt, @bind ) = $self->{sql}->insert( "item_analysis", { item_id => $item_digest, analysis_id => $analysis_id } );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		## Update the item status so that it is registered
		## as linked to an Analysis (status 3)

		my %where = ( digest => $item_digest );
		my %args	= ( status => 3	);

		( $stmnt, @bind ) = $self->{sql}->update( "item", \%args, \%where );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		## Check all the ID's (CVE, etc.) linked to the item. These
		## ID's must be added to the Analysis if they are
		## not already in the idstring.

		my $idstring = "";
		$stmnt =  "SELECT id.identifier FROM identifier AS id
								WHERE id.digest = ?
								AND (
											SELECT an.idstring FROM analysis AS an
											WHERE an.id = ?
										)
								NOT ILIKE '%' || id.identifier || '%';";

		@bind = ( $item_digest, $analysis_id );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		while ( $self->nextObject() ) {
			my $recordid = $self->getObject();
			$idstring .= $recordid->{identifier} . " ";
		}

		$idstring =~ s/\s+/ /;
		## Write the new ID string (containing the possibly
		## newly added ID's to the database

		$stmnt = "UPDATE analysis SET idstring = idstring || ' ' || ? WHERE id = ?;";
		@bind = ( $idstring, $analysis_id );

		if ( $set_status ) {
			$stmnt =~ s/(.*\?) (WHERE.*)/$1, status = \? $2/;
			$bind[2] = $bind[1];
			$bind[1] = $set_status;
		}

		if ( $title ) {
			$stmnt =~ s/(.*\?) (WHERE.*)/$1, title = \? $2/;

			if ( $set_status ) {
				$bind[3] = $bind[2];
				$bind[2] = $title;
			} else {
				$bind[2] = $bind[1];
				$bind[1] = $title;
			}

		}

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	} else {
		$self->{errmsg} = "No item found with given ID.";
	}

	$is_ok = 0 if ( $self->{errmsg} );
	return $is_ok;
}

sub unlinkItem {
	my ( $self, $digest, $analysis_id ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->delete( "item_analysis", { item_id => $digest, analysis_id => $analysis_id } );

	$self->{dbh}->prepare( $stmnt );

	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( $result !~ m/(0E0)/i ) {
		if ( $result > 0 ) {
			return 1;
		}
	} else {
		$self->{errmsg} = "Delete failed, no record found in 'item_analysis'.";
		return 0;
	}

}

sub getLinkedItems {
	my ( $self, $analysis_id ) = @_;
	my @items;
	my %where = ( "ia.analysis_id" => $analysis_id );

	my ( $stmnt, @bind ) = $self->{sql}->select( "item AS it", "it.*, to_char( created, 'DD-MM-YYYY HH24:MI:SS' ) AS datetime", \%where, "it.created DESC" );
	my $join = { "JOIN item_analysis AS ia" => {"ia.item_id" => "it.digest"} };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ){
		my $record = $self->getObject();
		push @items, $record;
	}

	if ( !$self->{errmsg} ) {
		return \@items;
	}	else {
		return 0;
	}
}

sub getLinkedItemsBulk {
	my ( $self, %where ) = @_;
	my @items;

	my ( $stmnt, @bind ) = $self->{sql}->select( "item AS it", "it.*, to_char( created, 'DD-MM-YYYY HH24:MI:SS' ) AS datetime, ia.analysis_id", \%where, "it.created DESC" );
	my $join = { "JOIN item_analysis AS ia" => {"ia.item_id" => "it.digest"} };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my %analyses;
	while ( $self->nextObject() ){
		my $record = $self->getObject();
		if ( exists( $analyses{$record->{analysis_id} } ) ) {
			push @{ $analyses{ $record->{analysis_id} } }, $record;
		} else {
			$analyses{ $record->{analysis_id} } = [ $record ];
		}
	}

	return \%analyses;
}

sub getLinkedAdvisories {
	my ( $self, %where ) = @_;
	my @advisories;

	$where{deleted} = 0;

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis_publication AS ap", "pa.*", \%where, "pu.created_on DESC" );
	tie my %join, 'Tie::IxHash';
	%join = (
		"JOIN publication AS pu" => {"pu.id" => "ap.publication_id"},
		"JOIN publication_advisory AS pa" => {"pa.publication_id" => "pu.id"}
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ){
		my $record = $self->getObject();
		push @advisories, $record;
	}

	return \@advisories;
}

sub getLinkedItemsContainingAdvisories {
	my ( $self, %where ) = @_;
	my @items;

	$where{contains_advisory} = 1;

	my ( $stmnt, @bind ) = $self->{sql}->select( "item_analysis AS ia", "i.*, ei.id AS email_item_id", \%where, "i.created DESC" );
	tie my %join, 'Tie::IxHash';
	%join = (
		"JOIN item AS i" => {"i.digest" => "ia.item_id"},
		"JOIN sources AS src" => {"src.id" => "i.source_id"},
		"JOIN email_item AS ei" => {"ei.digest" => "i.digest"}
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ){
		my $record = $self->getObject();
		push @items, $record;
	}

	return \@items;
}

sub getRelatedAnalysisIdMatch {
	my ( $self, $analysis_rights, $analysis_ids, @ids ) = @_;

	my ( @analysis, @nest2 );
	my ( %nest1, %and_nest2 );

	if ( $analysis_rights->{particularization} ) {
		foreach my $status ( @{ $analysis_rights->{particularization} } ) {
			push @{ $nest1{'upper(status)'} }, uc( $status );
		}
	}

	if ( $analysis_ids ) {
		for ( my $i = 0; $i < scalar @$analysis_ids; $i++ ) {
			push @nest2, { id => { "!=" => $analysis_ids->[$i] } };
		}
	}

	%and_nest2 = ( -and => \@nest2 ) if ( @nest2 );

	my @where = (
								-and => {
													idstring => { -ilike, \@ids },
													%nest1,
													%and_nest2
								}
							);

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis", "id, title, status", \@where, "id DESC" );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ) {
		push @analysis, $self->getObject();
	}
	return \@analysis
}

sub getRelatedAnalysisKeywordMatch {
	my ( $self, $analysis_rights, $analysis_ids, @keywords ) = @_;

	for ( my $i = 0; $i < @keywords; $i++ ) {
		$keywords[$i] = "%".trim($keywords[$i])."%";
	}

	my ( %temp1, %temp2, %nest3, %and_nest4 );
	my ( @nest1, @nest2, @nest4, @nest5 );

	if ( @keywords > 1 ) {
		for (my $i = 0; $i < @keywords; $i++) {
			for (my $j = 0; $j < @keywords; $j++) {
				if ($i != $j && ($j > $i)) {
					%temp1 = ("-and" => [ title => { -ilike, $keywords[$i] }, title => {-ilike, $keywords[$j] } ] );
					push @nest1, %temp1;
				}
			}
		}

		for ( my $i = 0; $i < @keywords; $i++ ) {
			for ( my $j = 0; $j < @keywords; $j++ ) {
				if ( $i != $j && ( $j > $i ) ) {
					%temp2 = ("-and" => [ comments => { -ilike, $keywords[$i] }, comments => {-ilike, $keywords[$j] } ] );
					push @nest2, %temp2;
				}
			}
		}
	} else {
		@nest1 = ( title    => { -ilike, $keywords[0] } );
		@nest2 = ( comments => { -ilike, $keywords[0] } );
	}

	if ( $analysis_rights->{particularization} ) {
		foreach my $status ( @{ $analysis_rights->{particularization} } ) {
			push @{ $nest3{'upper(status)'} }, uc( $status );
		}
	}

	if ( $analysis_ids ) {
		for ( my $i = 0; $i < scalar @$analysis_ids; $i++ ) {
			push @nest4, { id => { "!=" => $analysis_ids->[$i] } };
		}
	}

	%and_nest4 = ( -and => \@nest4 ) if ( @nest4 );

	my @where = (
								-and => {
									-or => [
											-nest => [ \@nest1 ],
											-nest => [ \@nest2 ],
											idstring => { -ilike, \@keywords }
									],
									%nest3,
									%and_nest4
								}
							);

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis", "id, title, status", \@where, "id DESC" );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my @analysis;
	while ( $self->nextObject ) {
		push @analysis, $self->getObject;
	}

	return \@analysis;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;
}

sub searchAnalysis {
	my ( $self, $search, $status, $analysis_rights, $analysis_ids ) = @_;
	undef $self->{errmsg};

	my @nests;
	my %and_nests;

	if ( $analysis_ids ) {
		for ( my $i = 0; $i < scalar @$analysis_ids; $i++ ) {
			push @nests, { id => { "!=" => $analysis_ids->[$i] } };
		}
	}

	%and_nests = ( -and => \@nests ) if ( @nests );

	my %where = (
									-or => [
											title    => { -ilike => "%" . trim($search) . "%" },
											comments => { -ilike => "%" . trim($search) . "%" },
											idstring => { -ilike => "%" . trim($search) . "%" },
											id       => { -ilike => "%" . trim($search) . "%" }
										],
										%and_nests
							);

	if ( $status ) {
		$where{status} = { -ilike => $status };
	} else {
		if ( $analysis_rights->{particularization} ) {
			$where{status} = {-ilike , \@{ $analysis_rights->{particularization} } };
		}
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis", "id, title, status", \%where, "id DESC" );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my @analysis;
	while ( $self->nextObject ) {
		push @analysis, $self->getObject;
	}

	return \@analysis;
}

sub openAnalysis {
	my ( $self, $username, $id ) = @_;
	return $self->setAnalysis( id => $id, opened_by => $username );
}

sub closeAnalysis {
	my ( $self, $id ) = @_;
	return $self->setAnalysis( id => $id, opened_by => undef );
}

sub isOpenedBy {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->select( "analysis AS an", "an.opened_by, us.fullname", { id => $id } );

	my %join = ( "JOIN users AS us" => { "us.username" => "an.opened_by" } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	return $self->{dbh}->fetchRow();
}

sub setOwnerShip {
	my ( $self, $username, $id ) = @_;
	return $self->setAnalysis( id => $id, owned_by => $username );
}

sub getOwnerShip {
	my ( $self, $id ) = @_;

	my $analysis = $self->getRecordsById( table => 'analysis', id => $id );

	if ( scalar( @$analysis ) == 1 ) {
		return $analysis->[0]->{owned_by} || '';
	} else {
		return undef;
	}
}

sub getAnalysisRatingFromAdvisory {
	my ( $self, %advisoryRating ) = @_;

	my %advisoryScale = ( 'low' => 3, 'medium' => 2, 'high' => 1 );
	my %analysisScale = ( 'low' => 1, 'medium' => 2, 'high' => 3 );

	my %ratingsMapping = (
		6 => 1, # L + L = 6 -> L
		5 => 1, # L + M = 5 -> L
		4 => 2, # L + H = 4 -> M & M + M = 4 -> M
		3 => 2, # M + H = 3 -> M
		2 => 3, # H + H = 2 -> H
	);

	return $ratingsMapping{ $advisoryScale{ $advisoryRating{damage} } + $advisoryScale{ $advisoryRating{probability} } };
}

sub getRatingDictionary {
	return \%RATINGDICTIONARY;
}

1;

=head1 NAME

Taranis::Analysis - functionality for Analysis

=head1 SYNOPSIS

  use Taranis::Analysis;

  my $obj = Taranis::Analysis->new( $objTaranisConfig );

  $obj->addObject( table => $table_name, argument => $argument , argument_x => $argument_x, etc... );

  $obj->setAnalysis( id => $analysis_id, status => $status, original_status => $original_status, title => $title,
                     comments => $comments, idstring => $idstring, rating => $rating );

  $obj->getRecordsById( table => $table_name, argument => $argument );

  $obj->loadAnalysisCollection( search => $search_string, status => \@status, rating => \@rating, offset => $offset );

  $obj->getNextAnalysisID();

  $obj->linkToItem( $item_digest, $analysis_id, $set_status, $title );

  $obj->unlinkItem( $item_digest, $analysis_id );

  $obj->getLinkedItems( $analysis_id );

  $obj->getLinkedItemsBulk( 'ia.analysis_id' => \@listOfAnalysisIDs );

  $obj->getLinkedAdvisories( 'ia.analysis_id' => $analysis_id );

  $obj->getLinkedItemsContainingAdvisories( 'ia.analysis_id' => $analysis_id );

  $obj->getRelatedAnalysisIdMatch( $analysis_rights, $analysis_ids, @ids );

  $obj->getRelatedAnalysisKeywordMatch( $analysis_rights, $analysis_ids, @keywords );

  $obj->searchAnalysis( $search, $status, $analysis_rights, $analysis_ids );

  $obj->nextObject();

  $obj->getObject();

  $obj->openAnalysis( $username, $id );

  $obj->closeAnalysis( $id );

  $obj->isOpenedBy( $id );

  $obj->setOwnerShip( $username, $id );

  $obj->getOwnerShip( $analysis_id );

  $obj->getAnalysisRatingFromAdvisory( damage => $damage, probability => $probability );

  $obj->getRatingDictionary();

  Taranis::Analysis->getRatingDictionary();

=head1 DESCRIPTION

When editing, adding or searching for Analyses this module can be used to perform checks, save data to the database and query the database.
Most methods involve database actions and use the C<Taranis::Database> module for this, which can be accessed by C<< $obj->{dbh} >>.
The SQL statements are created using the CPAN module C<SQL::Abstract::More> which can be accessed by C<< $obj->{sql} >>.
All SQL queries are executed by prepared statements with placeholders, to prevent SQL injection.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Analysis> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Analysis->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the maximum viewable analysis per page via limit which can be accessed by:

    $obj->{limit};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Clears the counted results. Can be accessed by:

    $obj->{result_count};

Returns the blessed object.

=head2 addObject( table => $table_name, column_name => $input_value, column_name => ... )

Method for adding an analysis (table: analysis) or a link between an analysis and item (table: item_analysis).

Arguments must be specified as C<< column_name => "input value" >>. Also specify the table as below.

    $obj->addObject( table => "analysis", comments => "description from item", title => "item title" );

Note: C<orgdatetime> and C<last_status_change> can be left out because it is set to C< now() > by default.

If it concerns the addition of an analysis, the C<idstring> is set to an emtpy string, because when linking to an item the C<idstring> cannot be NULL.
Also, when it concerns the addition of an analysis and no status has been specified, the status for that analysis is set to 'pending'.

Returns the analysis ID when adding an analysis. Returns TRUE when linking an analysis and item.

=head2 setAnalysis( id => $id, column_name => $input_value, column_name => ... )

Method for the editing (or rather updating) an analysis.

Arguments must be specified as C<< column_name => "input value" >>. Id has to be specified as below. This is mandatory.

    $obj->setAnalysis( id => 3, comments => "my new comments", title => "my new title" );

Note: if C<original_status> and status are passed as arguments the method will set C<last_status_change> to the date and time of now. The format for update insertion is '20081222 161322' ('YearMonthDay HoursMinutesSeconds').

Returns TRUE if database update is successful.

=head2 getRecordsById( table => $table_name, id => $id )

Will fetch all records that match a certain id for a specific table.
It's also possible to use other columns to search for records.

Table argument is mandatory and should be specified as follows:

    $obj->getRecordsById( table => "analysis", id => "20081222" );

Note: for table analysis the columns C<last_status_change> and C<orgdatetime> are formatted into string notation ('22-12-2008 16:21:55'). Both correspond to different key names in the result array, where column C<last_status_change> will be C<status_change> and C<orgdatetime> will be C<created>.
Also, if other table than C<analysis> is used it will retrieve all columns of the specified table. ( in SQL C<"*"> )

Returns an array containing all found search results.

=head2 loadAnalysisCollection( search => $search, status => \@status, rating => \@rating, offset => $offset )

Fetches all analysis that meet the criteria set by the following variables:

=over

=item *

C<< $search >> = free format string

=item *

C<< @status >> = array of strings that corresponds to the available statuses

=item *

C<< @rating >> = array of integers ranging from 1 to 4. ( 1 (low), 2 (medium), 3 (high), 4 (undefined) ).

=back

The argument search is used for matching content in columns C<title>, C<comments> and C<idstring>. Search argument also tries to match the content of the column C<id>, but only after stripping the characters AN- from the search string.

Note: A fourth argument can be passed to set the record C<offset>. Also before database execution the private method getResultCount() is called.

The resulting values of column C<orgdatetime> is changed to string and is split into a date string and a time string. ( C<< org_date => '22-12-2008' >>, C<< org-time => '16:49:55' >>).

Returns the return value of C<< DBI->execute() >>.

=head2 getNextAnalysisID( )

Retrieves a new available analysis C<id>.

    $obj->getNextAnalysisID();

If there's no C<id> for this year in database, this method will generate a new year C<id>, e.g. 20100001. It will be in the form YYYYXXXX where YYYY equals a year and XXXX a number.

Returns the next available Analysis C<id> based on the current year.

=head2 linkToItem( $item_digest, $analysis_id, $set_status, $title )

Links the currently selected Analysis to an item, based on the Item digest.

Takes four arguments:

=over

=item 1

item digest

=item 2

analysis id

=item 3

status

=item 3

new title for analysis

=back

Example:

    $obj->linkToItem( 'PhvM2gkMDxlUD+n0qJIjmA', '20080012', 'pending', 'my new title' );

linkToItem() performs several database actions:

=over

=item *

checks if the supplied item digest belongs to an item

=item *

links the item to the analysis

=item *

sets the linked item to status 3 (waitingroom)

=item *

checks all the ID's (CVE, etc.) linked to the item

=item *

these ID's must be added to the analysis if they are not already in the C<idstring>

=item *

update the status of the Analysis to C<< $set_status >> if C<< $set_status >> is supplied

=back

Note: it is recommended to use this method within a transaction. ( see C<< Taranis::Database->startTransaction() >> and friends )

Returns TRUE if all goes well.

=head2 unlinkItem( $item_digest, $analysis_id )

Unlink assess item from analysis. Needs the assess item digest and the analysis_id.

    $obj->unlinkToItem( 'PhvM2gkMDxlUD+n0qJIjmA', '20080012' );

=head2 getLinkedItems( $analysis_id )

Retrieves all the items that are linked to an analysis.

Takes an analysis C<id> as argument:

    $obj->getLinkedItems( '20080012' );

Returns all the items that are linked to an analysis.

=head2 getLinkedItemsBulk( 'ia.analysis_id' => \@listOfAnalysisIDs )

Retrieves all linked items of a list of analysis.

Returns a HASH reference where the key is the analysis ID and value is a list of assess items:

  { '20100001' => [ $assessItem1, $assessItem2, etc ], '20100002' => [ ... ] }

=head2 getLinkedAdvisories( 'ap.analysis_id' => $analysis_id )

Retrieves all advisories linked to an analysis.
Use columns of tables analysis_publication with alias 'ap', publication with alias 'pu' or publication_advisory with alias 'pa' for argument to method.

  $obj->getLinkedAdvisories( 'ap.analysis_id' => '20100001', 'pu.status' => {'!=' => 3} );

Returns a list of advisories.

=head2 getLinkedItemsContainingAdvisories( 'ia.analysis_id' => $analysis_id )

Retrieves assess items which can contain Taranis XML advisory.

Use columns of tables item with alias 'i', sources with alias 'src', email_item with alias 'ei' or item_analysis with alias 'ia' for arguments to method.

  $obj->getLinkedItemsContainingAdvisories( 'ia.analysis_id' => '20100001' );

Returns a list of assess items.

=head2 getRelatedAnalysisIdMatch( $analysis_rights, $analysis_ids, @ids )

Searches the C<idstring> of all analysis for matching id's (CVE, etc.).

Takes three arguments:

=over

=item 1

analysis rights, which are the particularization rights on entitlement 'analysis'

=item 2

analysis id's, which are the id's of the analysis that are already linked

=item 3

CVE id's, an array holding any number of id's as argument

=back

Example:

    $obj->getRelatedAnalysisIdMatch( $analysis_rights, $analysis_ids, @ids );

Returns the found analysis.

=head2 getRelatedAnalysisKeywordMatch( $analysis_rights, $analysis_ids, @keywords )

Searches the columns C<title>, C<comments> and C<idstring> for supplied keywords.

Takes three arguments:

=over

=item 1

analysis rights, which are the particularization rights on entitlement 'analysis'

=item 2

analysis id's, which are the id's of the analysis that are already linked

=item 3

an array of keywords

=back

Example:

    $obj->getRelatedAnalysisKeywordMatch( $analysis_rights, $analysis_ids, @keywords );

The search in columns C<title> and C<comments> is done by combining two keywords:

    ...( ( title ILIKE 'keyword_1' ) AND ( title ILIKE 'keyword_2' ) ) OR ( ( title ILIKE 'keyword_1 ) AND ( title ILIKE 'keyword_3' ) )...

The method creates all combinations of keywords.

Returns the found analysis.

=head2 searchAnalysis( $search, $status, $analysis_rights, $analysis_ids )

Searches columns C<title>, C<comments>, C<idstring> and C<id> with the search string combined with the specified status.

Takes four arguments:

=over

=item 1

search string

=item 2

status of analysis

=item 3

analysis rights, which are the particularization rights on entitlement 'analysis' (HASH ref)

=item 4

analysis id's, which are the id's of the analysis that are already linked (ARRAY ref)

=back

Example:

    $obj->searchAnalysis( 'linux vulnerability', 'pending', $analysis_rights, $analysis_ids );

Performs a case-insensitive search.

Returns the found analysis.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method  like loadCollection().

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=head2 openAnalysis( $username, $analysis_id ) & closeAnalysis( $analysis_id )

Sets the C<opened_by> flag for analysis. Both require the analysis ID. Only openAnalysis() requires a username.

    $obj->openAnalysis( 'userx', '20100012' );

    $obj->closeAnalysis( '20100012' );

Actually ports to setAnalysis() with arguments C<opened_by> and C<id>. Will therefore return the same as setAnalysis().

When C<opened_by> is C<undef> a analysis is closed, so closeAnalysis() will use C<undef> as value to C<opened_by>.

=head2 isOpenedBy( $analysis_id )

Takes the analysis ID as argument and fetches the C<opened_by> fullname.

    $obj->isOpenedBy( '20100012' );

Returns the username and fullname if the analysis is opened. Otherwise both values are C<undef>.

=head2 setOwnerShip( $username, $analysis_id )

Same as openAnalysis() the difference being that the C<owned_by> flag is set.

To get ownership:

    $obj->setOwnerShip( 'userx', '20100012' );

To delete ownership:

    $obj->setOwnerShip( undef, '20100012' );

Ports to setAnalysis() which also takes care of the return.

=head2 getOwnerShip( $analysis_id )

Retrieves analysis owner or, in case there is none, undef.

=head2 getAnalysisRatingFromAdvisory( damage => $damage, probability => $probability )

Converts an advisory classification to an analysis rating. Both damage and probability arguments are needed.

  $obj->getAnalysisRatingFromAdvisory( damage => 1, probability => 2 );

Analysis rating is determined according the following:

Low + Low = Low
Low + Medium = Low
Low + High = Medium
Medium + Medium = Medium
Medium + High = Medium
High + High = High

Returns an analysis rating:

=over

=item *

1 = low

=item *

2 = medium

=item *

3 = high

=back

=head2 getRatingDictionary()

Returns analysis rating mapping as HASH reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing table argument for routine.>

Caused by not specifying table argument in methods addObject() or getRecordsById()

=item *

I<Update failed, corresponding id not found in database.>

This can be caused when setAnalysis() wants to update a record that does not exist. You should check if argument C<id> has been specified. The method uses this in its WHERE clause.

=back

=cut
