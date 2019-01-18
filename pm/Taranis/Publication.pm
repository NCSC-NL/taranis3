# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication;

use Tie::IxHash;
use HTML::Entities qw(decode_entities);
use Carp qw(croak);
use XML::Simple qw(XMLin XMLout);

use Taranis qw(:all);
use Taranis::Database;
use Taranis::Template;
use Taranis::Users;
use Taranis::Config;
use Taranis::Damagedescription;
use Taranis::Publication::Advisory;
use Taranis::Publication::AdvisoryForward;
use Taranis::Publication::EndOfDay;
use Taranis::Publication::EndOfShift;
use Taranis::Publication::EndOfWeek;
use Taranis::SoftwareHardware;
use Taranis::Tagging;
use Taranis::FunctionalWrapper qw(Config Database PublicationEndOfDay Sql);


my %STATUSDICTIONARY = (
	0 => 'pending',
	1 => 'ready4review',
	2 => 'approved',
	3 => 'published',
	4 => 'sending',
);

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		config => $config || Config,
		status => { 
			0 => 'pending', 
			1 => 'ready for review', 
			2 => 'approved',
			3 => 'published',
			4 => 'sending',
		}
	};

	return( bless( $self, $class ) );
}

sub addPublication {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "publication", \%args );

	$self->{dbh}->prepare( $stmnt );
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

# setPublication( where => \%where || id => $publicationID, %update )
# Save changes to a publication, but change only settings stored in table publication.
# One of the two parameters where or id must be set.
#
#     $obj->setPublication( id => 23, contents => $contents_text, status => 2 );
#     OR
#     $obj->setPublication( where => { replacedby_id => 23 }, contents => $contents_text, status => 2 );
#
# If successful returns TRUE. If unsuccessful returns FALSE and sets $obj->{errmsg} to
# Taranis::Database->{db_error_msg}.
sub setPublication {
	my ($self, %args) = @_;

	my $where = defined $args{where}
		? delete $args{where}
		: {id => delete $args{id}};

	Database->simple->update(
		"publication",
		\%args,
		$where
	)->rows > 0 or croak "publication not found";

	return 1;
}

# deletePublication( $publicationDetailsID, $publicationType );
# Delete publications.
# Parameters $publicationDetailsID and $publicationType are mandatory. Valid values for $publicationType are:
# 'advisory', 'forward', 'eow', 'eod' and 'eos'.
#     $obj->deletePublication( 23, 'advisory' );
# If successful returns TRUE. If unsuccessful returns FALSE and sets $obj->{errmsg} to
# Taranis::Database->{db_error_msg}.
sub deletePublication {
	my ( $self, $id, $type ) = @_;
	undef $self->{errmsg};
	
	my $oTaranisPublicationSomething;

	if ( $type eq "advisory" ) {
		$oTaranisPublicationSomething = Taranis::Publication::Advisory->new();

	} elsif ( $type eq "forward" ) {
		$oTaranisPublicationSomething = Taranis::Publication::AdvisoryForward->new();

	} elsif ( $type eq "eod" ) {
		$oTaranisPublicationSomething = PublicationEndOfDay;

	} elsif ( $type eq "eos" ) {
		$oTaranisPublicationSomething = Taranis::Publication::EndOfShift->new();

	} elsif ( $type eq "eow" ) {
		$oTaranisPublicationSomething = Taranis::Publication::EndOfWeek->new();
	}

	if ( $oTaranisPublicationSomething ) {
		$self->{errmsg} = $oTaranisPublicationSomething->{errmsg};
		return $oTaranisPublicationSomething->deletePublication( $id, $self );
	}
}

# addFileToPublication( %fileAndPublicationDetails )
# Add a file to publication which will be send as attachment when publishing by email.
# Parameters `publication_id`, `binary` and `filename` are mandatory.
#
#     $obj->addFileToPublication( publication_id => 233, binary => $binary, filename => 'somefile.pdf', mimetype => 'application/pdf' );
#
# If successful returns the ID of the newly added publication attachment.
# If unsuccessful returns FALSE and sets $obj->{errmsg} to Taranis::Database->{db_error_msg}.
sub addFileToPublication {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  

	if ( !$inserts{publication_id} || $inserts{publication_id} !~ /^\d+$/ || !$inserts{binary} || !$inserts{filename} ) {
		$self->{errmsg} = 'Invalid parameter! (file)';
		return 0;
	}
	
	my $binary = delete( $inserts{binary} );
	
	if ( my $blobDetails = $self->{dbh}->addFileAsBlob( binary => $binary ) ) {
		$inserts{file_size} = $blobDetails->{fileSize};
		$inserts{object_id} = $blobDetails->{oid};
		
		if ( my $id = $self->{dbh}->addObject( 'publication_attachment', \%inserts, 1 ) ) {
			return $id;
		} else {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{errmsg};
		return 0;
	}
}

# linkToPublication( table => $linkTable, %inserts )
# Link publication details to publication.
# This can be software/hardware, an analysis or publication specific details (advisory or eow). It is mandatory to
# specify the table for linking:
#
#     $obj->linkToPublication( table => 'product_in_publication', publication_id => 23, softhard_id => 156 );
#
# Returns TRUE if linking is successful. If unsuccessful returns FALSE and sets $obj->{errmsg} to
# Taranis::Database->{db_error_msg} if database execution fails.
sub linkToPublication {
	my ( $self, %link_data ) = @_;
	undef $self->{errmsg};
	
	my $table = delete $link_data{table};

	my ( $stmnt, @bind ) = $self->{sql}->insert( $table, \%link_data );

	$self->{dbh}->prepare( $stmnt );
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}		
}

# unlinkFromPublication( table => $table, where => {} )
# Method for unlinking details from publication.
# See linkToPublication().
sub unlinkFromPublication {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
	
	my $table = delete $where{table};

	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, \%where );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( $result !~ m/(0E0)/i ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Delete failed, no record found in '$table'.";
		return 0;
	}	
}

# getLinkedToPublication( join_table_1 => {},	join_table_2 => {}, ... )
# Retrieve the details of linked publication tables.
#
# This method takes three parameters:
#
# * join_table_1, contains a hash for specifying the junction tablename (key) and the matching foreign key (value)
#   which points to the primary key of the details table.
# * join_table_2, contains a hash for specifying the details tablename (key) and the primary key (value) of the details
#   table.
# * 'pu.id', contains the value of the id of the publication.
#
# Example:
#
#     $obj->getLinkedToPublication(
#       join_table_1 => { analysis_publication => 'analysis_id' },
#       join_table_2 => { analysis => 'id' },
#       'pu.id'      => $query->param('id')
#     );
#
# Returns the value of DBI->execute(). Sets $errmsg of this object to Taranis::Database->{db_error_msg} if database
# execution fails.
sub getLinkedToPublication {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};
	
	my $join_table_1 = delete $searchFields{join_table_1};
	my $join_table_2 = delete $searchFields{join_table_2};
	
	my $join_table1_name = [ keys %$join_table_1 ]->[0];
	my $join_table2_name = [ keys %$join_table_2 ]->[0];
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "publication AS pu", $join_table2_name.".*", \%searchFields );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		"JOIN ".$join_table1_name => { "pu.id"	=> $join_table1_name.".publication_id" },
		"JOIN ".$join_table2_name => { $join_table1_name.".".$join_table_1->{ $join_table1_name } => $join_table2_name.".".$join_table_2->{ $join_table2_name } }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds(@bind);

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	return $result;
}

# getLinkedToPublicationIds( table => $table, select_column => $selectColumn, publication_id => $publicationID, advisory_id => $advisoryID )
# Retrieve ID's of details linked to publication or advisory.
# Method can be used to get ID's of tables that have a direct relation with table 'publication' or 'advisory'.
#
# Takes three arguments:
#
# * table, tablename of the table to extract id's from
# * select_column, column name of the specified table
# * a) publication_id, id of the publication or b) advisory_id, id of the advisory
#
# Example:
#
#     $obj->getLinkedToPublicationIds(
#       table          => 'product_in_publication',
#       select_column  => 'softhard_id',
#       publication_id => $publication_id
#     );
#
# or
#
#     $obj->getLinkedToPublicationIds(
#       table         => 'advisory_damage',
#       select_column => 'damage_id',
#       advisory_id   => $advisory_id
#     );
#
# Returns an array with ID's.
sub getLinkedToPublicationIds {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my ( @ids, %where );
	
	my $table = delete $args{table};
	my $select_column = delete $args{select_column};
	my $publication_id = delete $args{publication_id};
	my $advisory_id = delete $args{advisory_id};
	my $advisory_forward_id = delete $args{advisory_forward_id};
	
	$where{publication_id} = $publication_id if ( $publication_id );
	$where{advisory_id} = $advisory_id if ( $advisory_id );
	$where{advisory_forward_id} = $advisory_forward_id if ( $advisory_forward_id );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( $table, $select_column, \%where );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		push @ids, $self->getObject()->{$select_column};
	}
	return @ids;
}

# Lookup tables used by searchFieldsToQuery / getPublicationDetails.
my %publication_search_columns = (
	publication_advisory => [qw( consequences description govcertid hyperlinks ids solution summary title update notes tlpamber )],
	publication_advisory_forward => [qw( govcertid hyperlinks ids summary title update notes tlpamber )],
	publication_endofweek => [qw( closing introduction newondatabank newsitem )],
	publication_endofday => [qw( handler first_co_handler second_co_handler general_info vulnerabilities_threats published_advisories linked_items incident_info community_news media_exposure tlp_amber )],
	publication_endofshift => [qw( handler notes contact_log incident_log special_interest done todo )],
);

my %publication_table_fields = (
	publication_advisory => "publication_advisory.title AS pub_title, '[v' || version || ']' AS version_str",
	publication_advisory_forward => "publication_advisory_forward.title AS pub_title, '[v' || version || ']' AS version_str",
	publication_endofweek => "pu.title AS pub_title, to_char(created_on, 'Dy DD Mon YYYY') AS created_on_str",
	publication_endofday => "pu.title AS pub_title, to_char(publication_endofday.timeframe_begin, 'Dy DD Mon YYYY HH24:MI - ') ||  to_char(publication_endofday.timeframe_end, 'Dy DD Mon YYYY HH24:MI') AS timeframe_str",
	publication_endofshift => "pu.title AS pub_title, to_char(publication_endofshift.timeframe_begin, 'Dy DD Mon YYYY HH24:MI - ') ||  to_char(publication_endofshift.timeframe_end, 'Dy DD Mon YYYY HH24:MI') AS timeframe_str",
);

sub searchFieldsToQuery {
	my ( $self, %searchFields ) = @_;
	#XXX Some search parameters need to get quoted, but this function does
	#XXX not have the $dbh.  This function will be very different in v4.0,
	#XXX where we extend Publications OO-like.

	use strict;
	undef $self->{errmsg};

	my $table = $searchFields{table};
	my (@where, @bind);

	if($table eq 'publication_advisory') {
		push @where, "NOT deleted";
		push @where, "based_on = '$searchFields{based_on}'"
			if $searchFields{based_on};
	} elsif($table eq 'publication_advisory_forward') {
		push @where, "NOT deleted";
	} elsif($table eq 'publication_endofweek') {
	} elsif($table eq 'publication_endofday') {
		push @where, "type = '$searchFields{publicationType}'"
			if $searchFields{publicationType};
	} elsif($table eq 'publication_endofshift') {
		push @where, "type = '$searchFields{publicationType}'"
			if $searchFields{publicationType};
	}

	my $order_by = $searchFields{order_by}
		|| "pu.status, pu.published_on DESC, pu.created_on DESC";

	my $limit  = val_int $searchFields{hitsperpage};
	my $offset = val_int $searchFields{offset};

	my $start_date   = $searchFields{start_date};
	my $end_date     = $searchFields{end_date};
	if ($start_date && $start_date !~ /\d\d:\d\d$/) {
	    #XXX why?  Not all pages
		$start_date .= ' 000000';
		$end_date   .= ' 235959';
	}

	my $date_column = $searchFields{date_column};
	if($start_date && $end_date) {
		push @where, "$date_column BETWEEN '$start_date' AND '$end_date'";
	} elsif ($start_date) {
		push @where, "$date_column >= '$start_date'";
	} elsif ($end_date) {
		push @where, "$date_column <= '$end_date'";
	}

	if(my @search_status = @{$searchFields{status} || []}) {
		my %take = map +($_ => 1), @search_status;
		$take{4} = 1 if $take{2};
		push @where, 'pu.status IN ('. join(',', sort keys %take) . ')'
			if keys %take != 0 && keys %take != 5;
	}

	push @where, "version = '$searchFields{version}'"
		if $searchFields{version};

	# On purpose, multiple words will be searched as one string.  That's
	# a feature.
	my $search  = $searchFields{search} || '';
	$search     = trim($search);
	$search     =~ s/'//g;   # '
	$search     =~ s/([%_\\])/\\$1/g;

	if(length $search) {
		my $pattern = "%$search%";

		my $search_pu_content = <<__SEARCH_PU;
SELECT pu2.id
  FROM publication AS pu2
 WHERE pu2.contents ILIKE '$pattern'
__SEARCH_PU

		my $fields = join ' OR ',
			map "$table.$_ ILIKE '$pattern'",
				@{$publication_search_columns{$table}};

		my $search_pa_content = <<__SEARCH_PA;
SELECT publication_id
  FROM $table
 WHERE $fields
__SEARCH_PA

		push @where, "pu.id IN ($search_pu_content UNION $search_pa_content)";
	}

	if (my $extra = $searchFields{extraSearchOptions}) {
		#XXX only used in two places, both with a simple numeric values
		push @where, "$_ = $extra->{$_}" for sort keys %$extra;
	}

	my $return_fields = join ", ",
		$publication_table_fields{$table},
		"$table.*",
		"$table.id AS details_id",
		"pu.*",
		"us.fullname";

	my $where = @where ? 'WHERE '.join(' AND ', @where) : '';

	my $stmnt = <<__SEARCH;
SELECT $return_fields
  FROM publication AS pu
       JOIN $table ON $table.publication_id = pu.id
       LEFT JOIN users us ON us.username = pu.opened_by
 $where
 ORDER BY $order_by
__SEARCH

	return ($stmnt, \@bind, $limit, $offset);
}

# loadPublicationsCollection( table => $table, %where )
#
# Retrieves publications and some details specified in the supplied table.
#
# This method takes nine key/value parameters:
#
# * table, name of the table that holds the publication details
# * status, an array reference of all the desired statuses
# * date_column, name of the column to search with start_date and end_date
# * start_date, starting date to search the column specified with date_column
# * end_date, ending date to search the column specified with date_column
# * hitsperpage, number of maximum amount of results
# * offset, the number of the starting point of the range of the results
# * search, search string used to search the columns specified in the constants which are dependent on the table name
#   (see parameter `table`)
# * order_by, columns separated by comma's to specify the order of the results
#
# Example:
#
#     $obj->loadCollection(
#         table       => 'publication_advisory',
#         status      => [2,3],
#         start_date  => 20090525,
#         end_date    => 20090527,
#         date_column => 'published_on',
#         hitsperpage => 100,
#         offset      => 0,
#         search      => 'windows',
#         order_by    => 'govcertid, version'
#     );
#
# Collects per publication all data from table publication and all data of the table specified as argument. 
# Returns an ARRAY containing the publications. Sets $obj->{errmsg} to Taranis::Database->{db_error_msg} if database
# execution fails.
sub loadPublicationsCollection {
	my ($self, %searchFields) = @_;

	my ($stmnt, $bind, $limit, $offset) = $self->searchFieldsToQuery(%searchFields);

	my @publications;

	$stmnt .= " LIMIT $limit OFFSET $offset" if ( defined( $limit ) && defined( $offset ) );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @$bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	while ( $self->nextObject() ) {
		push @publications, $self->getObject();
	}
	return \@publications;
}

# publicationsCollectionCount: same as loadPublicationsCollection, but returns the number of publications instead of
# the actual data.
sub publicationsCollectionCount {
	my ($self, %searchFields) = @_;

	my ($stmnt, $bind, $limit, $offset) = $self->searchFieldsToQuery(%searchFields);

	my $count = $self->{dbh}->getResultCount( $stmnt, @$bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return $count;
}

# getPublicationDetails( table => $table, %where )
# Retrieve details from the table that belongs to a specific publication like 'publication_advisory' or
# 'publication_endofweek'. With parameters `table` and `tablename.columnname` the publication details can be retrieved.
#
#     $obj->getPublicationDetails(
#       table => 'publication_advisory',
#       'publication_advisory.id' => 25
#     );
#
# Returns the publication details as a hash reference. Sets $obj->{errmsg} to Taranis::Database->{db_error_msg} if
# database execution fails.
sub getPublicationDetails {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my $details;
	
	my $table = delete $args{table};
	my %where = $self->{dbh}->createWhereFromArgs( %args );

	defined $publication_table_fields{$table} or croak "invalid publication table $table";

	my $select = "
		$table.*,
		pu.contents, 
		pu.status, 
		pu.title AS pub_title,
		pu.created_by,
		pu.approved_by,
		pu.published_by,
		pu.type,
		pu.replacedby_id,
		pu.type,
		pu.opened_by,
		to_char(created_on, 'YYYYMMDD') AS created_on_str, 
		to_char(published_on, 'YYYYMMDD') AS published_on_str, 
		to_char(approved_on, 'YYYYMMDD') AS approved_on_str,
		$publication_table_fields{$table},
		$table.id AS details_id";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( $table, $select, \%where );
	my %join = ( "JOIN publication AS pu" => { "pu.id" => $table.".publication_id" } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	
	$self->{dbh}->executeWithBinds( @bind );
	$self->{errmsg} = $self->{dbh}->{db_error_msg};	
	
	while ( $self->nextObject() ) {
		$details = $self->getObject();
	}
	
	return $details;
}

# setPublicationDetails( table => $table, where => {}, %update )
# Update publication details. Parameters table and where are mandatory.
#
#    $obj->setPublicationDetails(
#      table => 'publication_advisory',
#      where => { id => 42 },
#      title => 'my new advisory title',
#      damage => '2'
#    );
#
# If successful returns TRUE. If unsuccessful returns FALSE and sets $obj->{errmsg} to
# Taranis::Database->{db_error_msg}.
sub setPublicationDetails {
	my ( $self, %details ) = @_;
	undef $self->{errmsg};
	
	my $table = delete $details{table};
	my $where = delete $details{where};

	my ( $stmnt, @bind ) = $self->{sql}->update( $table, \%details, $where );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg} || "Action failed, corresponding id not found in database. (1)";
		return 0;		
	}
}

# getLatestPublishedPublicationDate( %where )
# Retrieve a formatted timestamp of the last published publication.
# In case 'advisory (email)' is type 2, this will retrieve the timestamp of the last published advisory:
#     $obj->getLatestPublishedPublicationDate( type => 2 );
# Returns an HASH reference: { published_on_str => '20140331 1800' }
sub getLatestPublishedPublicationDate {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	$where{status} = 3;

	my $select = "MAX( to_char(published_on, 'YYYYMMDD HH24MI')) AS published_on_str";

	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication', $select, \%where );

	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );
	$self->{errmsg} = $self->{dbh}->{db_error_msg}; 

	return $self->{dbh}->fetchRow();
}

# getLatestAdvisoryVersion( govcertId => $advisoryID )
# Retrieve the latest version of an advisory. Parameter `govcertId` is mandatory.
#     $obj->getLatestAdvisoryVersion( govcertId => 'NCSC-2014-0001' );
# Returns the advisory as an HASH reference.
sub getLatestAdvisoryVersion {
	my ( $self, %settings ) = @_;
	
	my $govcertId = $settings{govcertId};

	my $advisoryTable = ( $self->{dbh}->checkIfExists( { govcertid => $govcertId }, 'publication_advisory_forward' ) )
		? 'publication_advisory_forward'
		: 'publication_advisory';

	my $subSelect = "MAX(version)";
	my %subWhere = ( "pa2.govcertid" => $govcertId, "pa2.deleted" => 0 );

	my ( $subStmnt, @subBind ) = $self->{sql}->select( "$advisoryTable pa2", $subSelect, \%subWhere );

	my %where = (
		"pa1.govcertid" => $govcertId,
		"pa1.version" => \[ "IN ($subStmnt)" => @subBind ] 
	);

	return Database->simple->select("$advisoryTable pa1", 'pa1.*', \%where)->hash;
}

# extractSoftwareHardwareFromCve( $idstring )
# Retrieve software/hardware that is linked to a CVE ID. The ID's are to space separated.
#     $obj->extractSoftwareHardwareFromCve( 'CVE-2009-0003 CVE-2009-2345 CVE-2009-4567' );
# Returns a list of software/hardware. The data retrieved is the software/hardware description and all found data from
# table software_hardware.
sub extractSoftwareHardwareFromCve {
	my ( $self, $idstring ) = @_;
	undef $self->{errmsg};
	my ( @sh_list, @cve_ids );
	
	my @ids = split( " ", $idstring );
	
	foreach ( @ids ) {
		if ( $_ =~ /^CVE.*/i ) {
			push @cve_ids, uc( $_ );
		}
	}

	# return if there aren't any CVE id's
	if ( !@cve_ids ) {
		return;
	}
	
	my %where = ( 
		"cc.cve_id"  => \@cve_ids,
		"sh.deleted" => 0 
	);

	my ( $stmnt, @bind ) = $self->{sql}->select( "software_hardware AS SH", "DISTINCT sht.description, sh.*", \%where, "sh.name, sh.version" );

	my $join = { "JOIN cpe_cve AS cc" 				=> { "sh.cpe_id" => "cc.cpe_id"},
							 "JOIN soft_hard_type AS sht" => { "sh.type" 	 => "sht.base" }
						 };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );	

	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );
			
	while ( $self->nextObject() ) {
		push @sh_list, $self->getObject();
	}
	
	return \@sh_list;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

# getPublicationTypeId($publicationTypeName )
# getPublicationTypeId($publicationGroup, $publicationSubgroup)

sub getPublicationTypeId($;$) {
	my $self = shift;
use Carp;
use Scalar::Util 'blessed';
blessed $self->{config} or confess;
	my $name = @_==1 ? shift : $self->{config}->publicationTemplateName(@_);

	my $db   = $self->{dbh}->simple;
	$db->query('SELECT id FROM publication_type WHERE title ILIKE ?', $name)
	   ->list;
}

# getItemLinks( { analysis_id => $analysisID || publication_id => $publicationID } )
# Retrieve links from an item that are linked to an analysis. On of the two parameters `analysis_id` or
# `publication_id` is mandatory.
#     $obj->getItemLinks( analysis_id => 25 );
#     OR
#     $obj->getItemLinks( publication_id => 76 );
sub getItemLinks {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my @links;
	my %where;
	tie my %join, "Tie::IxHash";
	
	if ( exists( $args{analysis_id} ) ) {	
		%where = ( "an.id" => $args{analysis_id}, "item.is_mail" => 'f' );
		%join  = ( 
			"JOIN item_analysis AS ia" => { "ia.item_id" => "item.digest" },
			"JOIN analysis AS an" => { "an.id" => "ia.analysis_id" }
		);
	} elsif ( exists( $args{publication_id} ) ) {
		%where = ( "ap.publication_id" => $args{publication_id}, "item.is_mail" => 'f' );
		%join  = ( 
			"JOIN item_analysis AS ia" => { "ia.item_id" => "item.digest" },
			"JOIN analysis AS an" => { "an.id" => "ia.analysis_id" },
			"JOIN analysis_publication AS ap" => { "an.id" => "ap.analysis_id" }
		);
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "item", "item.link", \%where, "item.link" );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds(@bind);
	
	while ( $self->nextObject() ) {
		push @links, $self->getObject()->{"link"};
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return \@links;
}

# listSoftwareHardware(%options)
# * ids, ID's of the records to retrieve
# * columns, the column names of the desired information
#
#     $obj->listSoftwareHardware(ids => [46533,46561,46550],
#         columns => ["producer","name","version"]);
#
#XXX needs to be relocated

sub listSoftwareHardware {
	my ($self, %args) = @_;
	undef $self->{errmsg};

	my @ids     = flat $args{ids};
	my @columns = flat $args{columns};
	my $table   = $args{table} || 'software_hardware';

	my @preview_parts;
	
	if(@ids) {
		my @where = ( id => \@ids ); 
		my $select = "DISTINCT ".join(', ', @columns);

		my ( $stmnt, @bind ) = $self->{sql}->select('software_hardware', $select, \@where, $columns[0]);
	
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
			
		while($self->nextObject) {
			my $part = $self->getObject;
			my @cols = map ucfirst($_), grep defined, @{$part}{@columns};

			# first and second column sometimes start the same... not nice
			pop @cols if @cols > 1 && $cols[0] eq $cols[1];

			push @preview_parts, join ' ', @cols;
		}
		
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
	}

	join "\n", @preview_parts;
}

# processPreviewXml( $advisoryID )
# Create the XML output of an advisory. For advisories only.
#
#     $obj->processPreviewXml( 34 );
#
# Note: the content of the XML is placed between CDATA tags.
# Returns the XML as a string.
sub processPreviewXml {
	my ( $self, $advisory_id ) = @_;
	undef $self->{errmsg};
	my $usr = Taranis::Users->new( $self->{config} );
	my $dd = Taranis::Damagedescription->new( $self->{config} );
	
	my $publication = $self->getPublicationDetails( 
		table => "publication_advisory",
		"publication_advisory.id" => $advisory_id 
	);
	my @test =  keys %$publication;																							 		

	my $advisoryXMLTemplate = find_config $self->{config}->{advisory_xml_template};

	my $advisory = XMLin(
		$advisoryXMLTemplate,
		KeepRoot => 1,
		ForceArray => 1
	);

	my %advisoryScale = ( 1 => "high", 2 => "medium", 3 => "low" );
	
	my $organisation = $self->{config}->{organisation};
	
	### SIMPLE CONVERSIONS ###
	$publication->{update_information} = $publication->{update};
	$publication->{abstract} = $publication->{summary};
	$publication->{tlp_amber} = $publication->{tlpamber};
	$publication->{reference_number} = $publication->{govcertid};
#	$publication->{issuer} = $usr->getUser( $publication->{created_by} )->{fullname};
	$publication->{issuer} .= "$organisation" if ( $organisation );
	$publication->{date} = $publication->{published_on_str};
	$publication->{damage} = $advisoryScale{ $publication->{damage} };
	$publication->{probability} = $advisoryScale{ $publication->{probability} };
	
	### START FILLING THE GAPS ###
	foreach my $element ( %{ $advisory->{xml_advisory}->[0] } ) {
	
		# XMLSimple treats elements named 'content' differently,
		# because of this a check for 'HASH' or 'ARRAY' must be done first
		if ( ref($element) eq "HASH" ) {
			foreach ( keys %$element ) {
				
				if ( /additional_resources/ ) {
					
					my @hyperlinks = split( "\n", $publication->{hyperlinks} );
					my $resource_element = $element->{$_}->[0]->{resource};
					
					for ( my $i = 0 ; $i < @hyperlinks ; $i++ ) {
						$resource_element->[$i] = $hyperlinks[$i];
					}
				
				} elsif ( /disclaimer/ ) {
					next;
				} else {
					$element->{$_}->[0] = $publication->{$_};
				}
			}
	
		} elsif ( ref($element) eq "ARRAY" ) {
	
			foreach my $key ( keys %{ $element->[0] } ) {
	
				if ( $key =~ /vulnerability_identifiers/ ) {
					my $cve_cnt = 0;
					
					my %unique_ids;					
					foreach ( split( ",", $publication->{ids} ) ) {
						$_ =~ s/\s*//;
						$unique_ids{ trim( $_ ) } = 1;
					}
					
					my @ids = sort keys %unique_ids;
					
					for (@ids) {
						if (/^CVE.*/) {
							$element->[0]->{$key}->[0]->{cve}->[0]->{id}->[$cve_cnt] = $_;
							$cve_cnt++;
						}
					}
				}	elsif ( $key =~ /version_history/) {
					my $current_version = { version => $publication->{version}, 
						date => $publication->{published_on_str}, 
						update => $publication->{update}
					};
					my $previous_versions = $self->getPreviousVersions( $publication->{publication_id } );
					my @versions = @$previous_versions;
					push @versions, $current_version;
					
					for ( my $i = 0; $i < @versions; $i++ ) {
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{date}->[0] = $versions[$i]->{date};
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{version}->[0] = $versions[$i]->{version};
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{change_descr}->[0] = $versions[$i]->{update};
					}
				}	elsif ( $key =~ /vulnerability_effect/) {
					my @damage_ids	= $self->getLinkedToPublicationIds( 
						table => "advisory_damage",
						select_column => "damage_id",
						advisory_id => $advisory_id
					);
					if ( @damage_ids ) {
						my @damage_descriptions	= $dd->getDamageDescription( id => \@damage_ids );					
						
						for ( my $i = 0; $i < @damage_descriptions; $i++ ) {
							$element->[0]->{$key}->[0]->{effect}->[$i] = $damage_descriptions[$i]->{description};
						}
					}
				}	elsif ( $key =~ /system_information/) {
					for ( keys %{ $element->[0]->{$key}->[0]->{systemdetail}->[0] } ) {
						if(/^affected_product$/) {
							$self->getLinkedToPublication(
								join_table_1 => { "product_in_publication" => "softhard_id" },
								join_table_2 => { "software_hardware" => "id" },
								"pu.id" => $publication->{publication_id}
							);
							my $i = 0;
							while ( $self->nextObject() ) {
								my $product = $self->getObject();
								foreach my $productDetail ( 'producer', 'name', 'version', 'cpe_id' ) {
									$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0]->{product}->[$i]->{$productDetail}->[0] = $product->{$productDetail};
								}
								$i++;
							}
						} elsif (/^affected_platform$/) {
							$self->getLinkedToPublication(
								join_table_1 => { "platform_in_publication" => "softhard_id" },
								join_table_2 => { "software_hardware" => "id" },
								"pu.id" => $publication->{publication_id}
							);
							my $i = 0;
							while ( $self->nextObject() ) {
								my $platform = $self->getObject();
								foreach my $productDetail ( 'producer', 'name', 'version', 'cpe_id' ) {
									$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0]->{platform}->[$i]->{$productDetail}->[0] = $platform->{$productDetail};
								}								
								$i++;
							}							

						} elsif (/^affected_platforms_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $publication->{platforms_text} if ( $publication->{platforms_text} );
						} elsif (/^affected_products_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $publication->{products_text} if ( $publication->{products_text} );
						} elsif (/^affected_products_versions_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $publication->{versions_text} if ( $publication->{versions_text} );
						}
					}
				} elsif ( $key =~ /publisher_analysis/) {
					for ( keys %{ $element->[0]->{$key}->[0] } ) {
						$element->[0]->{$key}->[0]->{$_}->[0] = $publication->{$_}
					}
				} elsif ( $key =~ /availability/ ) {
					next; # data for availability already in blank XML file.
				} elsif ( $key =~ /taranis_version/ ) {
					next;
				} else {
					$element->[0]->{$key}->[0] = $publication->{$key};
				}
			}
		}
	}
 
	my $xml = XMLout(
		$self->setCdata( $advisory ),
		KeepRoot => 1,
		NoSort => 1,
		XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>'
	);

	# The database is poluted with \r which we do not want
	$xml =~ s/\r//g;

	# decoding is done because XMLout does html encoding 
	return decode_entities( $xml );

}

# processPreviewXmlRT( \%formData )
# Same as processPreviewXml(), except it uses all data set by parameter %formData to create the preview.
sub processPreviewXmlRT {
	my ( $self, $formData ) = @_;
	undef $self->{errmsg};
	my $usr = Taranis::Users->new( $self->{config} );
	my $dd = Taranis::Damagedescription->new( $self->{config} );
	my $sh = Taranis::SoftwareHardware->new( $self->{config} );

	my $advisoryXMLTemplate = find_config $self->{config}->{advisory_xml_template};
	
	my $advisory = XMLin(
		$advisoryXMLTemplate,
		KeepRoot => 1,
		ForceArray => 1
	);

	my %advisoryScale = ( 1 => "high", 2 => "medium", 3 => "low" );
	
	my $organisation = $self->{config}->{organisation};
	
	### SIMPLE CONVERSIONS ###
	$formData->{update_information} = $formData->{update};
	$formData->{abstract} = $formData->{summary};
	$formData->{tlp_amber} = $formData->{tlpamber};
	$formData->{reference_number} = $formData->{govcertid};
#	$formData->{issuer} = $formData->{created_by};
	$formData->{issuer} .= "$organisation" if ( $organisation );
	$formData->{date} = '';
	$formData->{damage} = $advisoryScale{ $formData->{damage} };
	$formData->{probability} = $advisoryScale{ $formData->{probability} };
	
	### START FILLING THE GAPS ###
	foreach my $element ( %{ $advisory->{xml_advisory}->[0] } ) {
	
		#	XMLSimple treats elements named 'content' differently,
		# because of this a check for 'HASH' or 'ARRAY' must be done first
		if ( ref($element) eq "HASH" ) {
			foreach ( keys %$element ) {
				
				if ( /additional_resources/ ) {
					
					my @hyperlinks = split( "\n", $formData->{hyperlinks} );
					my $resource_element = $element->{$_}->[0]->{resource};
					
					for ( my $i = 0 ; $i < @hyperlinks ; $i++ ) {
						$resource_element->[$i] = $hyperlinks[$i];
					}
				
				} elsif ( /disclaimer/ ) {
					next;
				} else {
					$element->{$_}->[0] = $formData->{$_};
				}
			}
	
		} elsif ( ref($element) eq "ARRAY" ) {
	
			foreach my $key ( keys %{ $element->[0] } ) {
	
				if ( $key =~ /vulnerability_identifiers/ ) {
					my $cve_cnt = 0;
					
					my %unique_ids;					
					foreach ( split( ",", $formData->{ids} ) ) {
						$_ =~ s/\s*//;
						$unique_ids{ trim( $_ ) } = 1;
					}
					
					my @ids = sort keys %unique_ids;
					
					for (@ids) {
						if (/^CVE.*/) {
							$element->[0]->{$key}->[0]->{cve}->[0]->{id}->[$cve_cnt] = $_;
							$cve_cnt++;
						}
					}
				} elsif ( $key =~ /version_history/) {
					my $current_version = { 
						version => $formData->{version}, 
						date => $formData->{published_on_str}, 
						update => $formData->{update}
					};
					my $previous_versions = $self->getPreviousVersions( $formData->{publication_id } );
					my @versions = @$previous_versions;
					push @versions, $current_version;
					
					for ( my $i = 0; $i < @versions; $i++ ) {
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{date}->[0] = $versions[$i]->{date};
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{version}->[0] = $versions[$i]->{version};
						$element->[0]->{$key}->[0]->{version_instance}->[$i]->{change_descr}->[0] = $versions[$i]->{update};
					}
				} elsif ( $key =~ /vulnerability_effect/) {
					
					if ( @{ $formData->{damageIds} } ) {
						my @damage_descriptions	= $dd->getDamageDescription( id => \@{ $formData->{damageIds} } );					
						
						for ( my $i = 0; $i < @damage_descriptions; $i++ ) {
							$element->[0]->{$key}->[0]->{effect}->[$i] = $damage_descriptions[$i]->{description};
						}
					}
				} elsif ( $key =~ /system_information/) {
					for ( keys %{ $element->[0]->{$key}->[0]->{systemdetail}->[0] } ) {
						if(/^affected_product$/) {
							if ( @{ $formData->{products} } ) {

								my $products = $sh->loadCollection( id => \@{ $formData->{products} } );	

								my $i = 0;
								foreach my $product ( @$products ) {
									foreach my $productDetail ( 'producer', 'name', 'version', 'cpe_id' ) {
										$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0]->{product}->[$i]->{$productDetail}->[0] = $product->{$productDetail};
									}
									$i++;
								}
							}
						} elsif (/^affected_platform$/) {
							if ( @{ $formData->{platforms} } ) {
							
								my $platforms = $sh->loadCollection( id => \@{ $formData->{platforms} } );	

								my $i = 0;
								foreach my $platform ( @$platforms ) {
									foreach my $productDetail ( 'producer', 'name', 'version', 'cpe_id' ) {
										$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0]->{platform}->[$i]->{$productDetail}->[0] = $platform->{$productDetail};
									}
									$i++;
								}
							}				
						} elsif (/^affected_platforms_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $formData->{platforms_text} if ( $formData->{platforms_text} );
						} elsif (/^affected_products_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $formData->{products_text} if ( $formData->{products_text} );
						} elsif (/^affected_products_versions_text$/) {
							$element->[0]->{$key}->[0]->{systemdetail}->[0]->{$_}->[0] = $formData->{versions_text} if ( $formData->{versions_text} );
						}
					}
				} elsif ( $key =~ /publisher_analysis/) {
					for ( keys %{ $element->[0]->{$key}->[0] } ) {
						$element->[0]->{$key}->[0]->{$_}->[0] = $formData->{$_}
					}
				} elsif ( $key =~ /availability/ ) {
					next; # data for availability already in blank XML file.
				} elsif ( $key =~ /taranis_version/ ) {
					next;
				} else {
					$element->[0]->{$key}->[0] = $formData->{$key};
				}
			}
		}
	}
	
	my $xml = XMLout(
		$self->setCdata( $advisory ),
		KeepRoot => 1,
		NoSort => 1,
		XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>'
	);

	# The database is poluted with \r which we do not want
	$xml =~ s/\r//g;

	# decoding is done because XMLout does html encoding 
	return decode_entities( $xml );
}

# setCdata( $args )
# Add CDATA tags to all values in $args.
#     $obj->setCdata( $args );
# Returns the data structure where all the values are enclosed by CDATA tags.
sub setCdata {
	my ( $self, $arg ) = @_;
	if ( ref( $arg ) eq 'ARRAY' ) {
		for ( my $i = 0; $i < @$arg; $i++ ) {
			if ( ref( $arg->[$i] ) eq 'HASH' || ref( $arg->[$i] ) eq 'ARRAY' ) {
				$arg->[$i] = $self->setCdata( $arg->[$i] );
			} else {
				if ( $arg->[$i] !~ /^\d*$/ ) {
					$arg->[$i] = "<![CDATA[". $arg->[$i] ."]]>" if ( $arg->[$i] );
				}
			}
		}		
	} elsif ( ref( $arg ) eq 'HASH' ) {
		foreach ( keys %$arg ) {
			if ( ref( $arg->{$_} ) eq 'HASH' || ref( $arg->{$_} ) eq 'ARRAY' ) {
				$arg->{$_} = $self->setCdata( $arg->{$_} );
			} else {
				if ( $_ eq "xmlns:xsi" || $_ eq "xsi:noNamespaceSchemaLocation" ) {
					next;
				} else {
					if ( $arg->{$_} !~ /^\d*$/ ) {
						$arg->{$_} = "<![CDATA[". $arg->{$_} ."]]>" if ( $arg->{$_} );
					}
				}
			}
		}
	} else {
		if ( $arg !~ /^\d*$/ ) {
			$arg = "<![CDATA[". $arg ."]]>";
		}
	}
	return $arg;	
}

# getPreviousVersions( $publicationID )
# For advisories only. Retrieve previous versions of an advisory.
#     $obj->getPreviousVersions( 35 );
# Returns each found advisory with the publication_id (as 'pub_id'), replacedby_id, version, update and published_on
# (as 'date').
sub getPreviousVersions {
	my ( $self, $publication_id ) = @_;
	undef $self->{errmsg};
	my @versions;

	my ( $stmnt, $pub_id ) = $self->{sql}->select( "publication pu", "pu.id AS pub_id, replacedby_id, version, update, to_char(published_on, 'YYYYMMDD') AS date", { replacedby_id => $publication_id } );
	my %join = ( "JOIN publication_advisory pa" => { "pa.publication_id" => "pu.id" } );
	$stmnt = $self->{dbh}->sqlJoin(  \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	while ( $pub_id ) {
		$self->{dbh}->executeWithBinds( $pub_id );
		my $version = $self->{dbh}->fetchRow();
		push @versions, $version if ( $version );
		$pub_id = ( $version->{replacedby_id} ) ? $version->{pub_id} : 0;		
	}
	return \@versions;	
}

# getNextVersions( $replacedByID )
# Retrieve all newer related publications. For instance if $replacedByID is an advisory with ID 'NCSC-2014-0123 V1.3',
# it will retrieve all 'NCSC-2014-0123' advisories that have a higher version number.
#     $obj->getNextVersions( 876 );
sub getNextVersions {
	my ( $self, $replacedById ) = @_;
	my @publications;
	my $stmnt = "SELECT * FROM publication WHERE id = ?;";
	
	$self->{dbh}->prepare( $stmnt );

	while ( $replacedById ) {
		$self->{dbh}->executeWithBinds( $replacedById );
		my $publication = $self->{dbh}->fetchRow();
		push @publications, $publication if ( $publication );
		
		$replacedById = ( $publication->{replacedby_id} ) ? $publication->{replacedby_id} : 0;
	}

	return \@publications;
}

# getRelatedPublications( \@cve_ids, $publicationType )
# For advisories only. Retrieve related advisories based on a list of CVD ID's @cve_ids. Parameter $publicationType
# must be set to 'advisory' or 'forward'.  Searches for latest vesions (replacedby_id = NULL) of published (status = 3)
# advisories.
#
#     $obj->getRelatedPublications( [ 23, 56, 76 ], 'advisory' );
#     OR
#     $obj->getRelatedPublications( undef, 'advisory' );
#
# Returns reference to array of hashes. e.g.:
# [
#   {
#     'details_id' => 5,
#     'named_id' => 'NCSC-2015-0003',
#     'publication_id' => 5,
#     'publication_title' => 'advisory 3',
#     'version' => '1.00'
#   }
# ]
sub getRelatedPublications {
	my ($self, $cve_ids, $publicationType, %args) = @_;
	undef $self->{errmsg};
	my @publications;
	my  %where;

	if ($cve_ids && @$cve_ids) {
		%where = ( ids => { -ilike, [map "%".trim($_)."%", @$cve_ids] } );
	}

	$where{"pu.status"} = 3
		unless $args{allow_incomplete};
	$where{"replacedby_id"} = undef; # will create SQL 'replacedby_id IS NULL'

	my $stmnt;
	my @bind;

	if ( $publicationType eq 'advisory' ) {
		( $stmnt, @bind ) = $self->{sql}->select( "publication_advisory pa", "govcertid AS named_id, pa.id AS details_id, pa.title AS publication_title, version, publication_id", \%where, "govcertid DESC, version DESC" );
	} else { # publicationType = forward
		( $stmnt, @bind ) = $self->{sql}->select( "publication_advisory_forward pa", "govcertid AS named_id, pa.id AS details_id, pa.title AS publication_title, version, publication_id", \%where, "govcertid DESC, version DESC" );
	}

	my %join = ( "JOIN publication pu" => { "pu.id" => "pa.publication_id" } );	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	while ( $self->nextObject() ) {
		push @publications, $self->getObject();
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return \@publications;
}

# searchPublishedPublications( $searchString, $publicationType )
# Same as getRelatedPublications(), but instead search for a string in columns 'contents', 'notes' and 'ids'.
sub searchPublishedPublications {
	my ( $self, $search, $publicationType, $include_open) = @_;

	my $advisoryTable = $publicationType eq 'advisory' ? 'publication_advisory' : 'publication_advisory_forward';

	my $pattern = "%".trim($search)."%";
	my %where   = (
		'pu.replacedby_id' => undef,
		-or => [
			'pu.contents' => {-ilike => $pattern},
			'pa.ids'      => {-ilike => $pattern},
			'pa.notes'    => {-ilike => $pattern},
		],
	);

	$where{'pu.status'} = 3
		unless $include_open;

	return [ Database->simple->select(
		-from => [-join =>
			'publication|pu',  'id=publication_id',  "$advisoryTable|pa"
		],
		-columns => [qw(
			pa.id|details_id   pa.govcertid|named_id   pa.version   pa.title|publication_title   pa.publication_id
		)],
		-where => \%where,
		-order_by => "pa.govcertid DESC, pa.version DESC"
	)->hashes ];
}

sub getDistinctPublicationTypes {
	my $self = shift;
	my @types;

	#XXX T3 does not have a pluggable infrastructure, so we need tricks to
	#    disable components.
	my $include_white = ($self->{config}{publish_eod_white} || 'ON') =~ /ON/i;

	my $stmnt = "SELECT DISTINCT title FROM publication_type ORDER BY title DESC;";
	
	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		my $type = $self->getObject;
		next if $type->{title} =~ /white/ && ! $include_white;
		push @types, $type->{title};
	}
	
	return @types;
}

sub openPublication {
	my ( $self, $username, $id ) = @_;
	return $self->setPublication( id => $id, opened_by => $username );
}

sub closePublication {
	my ( $self, $id ) = @_;
	return $self->setPublication( id => $id, opened_by => undef );
}

# isOpenedBy( $publicationID )
# Retrieves the username and fullname of the user which is set in `opened_by`.
#
#     $obj->isOpenedBy( 96 );
#
# Returns a hash reference with keys `opened_by` and `fullname`.
sub isOpenedBy {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "publication AS p", "p.opened_by, us.fullname", { id => $id } );

	my %join = ( "JOIN users AS us" => { "us.username" => "p.opened_by" } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return $self->{dbh}->fetchRow();
}

# getPublishedPublicationsByAnalysisId( table => $table, analysis_id => $analysisID, %where )
# Retrieve published publications which were created from analysis with `analysis_id`. Parameters `table` and
# `analysis_id` are mandatory.
#
#     $obj->getPublishedPublicationsByAnalysisId( table => 'publication_advisory', analysis_id => 20140001, govcertid => 'NCSC-2014-0001' );
sub getPublishedPublicationsByAnalysisId {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	croak "no analysis_id provided" unless $args{analysis_id};
	croak "no table provided" unless $args{table};

	my $table = delete $args{table};
	
	return [ Database->simple->select(
		-from => [-join =>
			"$table|p",   'publication_id=id',   'publication|pu',
			              'id=publication_id',   'analysis_publication|ap',
		],
		-columns => ['p.*'],
		-where => {
			'pu.status' => 3,
			%args,
		},
	)->hashes ];
}

# getPublicationAttachments( %where )
# Retrieve linked publication attachments details. The actual attachment can be retrieved using getBlob() in
# Taranis::Database.
#     $obj->getPublicationAttachments( publication_id => 354 );
sub getPublicationAttachments {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'publication_attachment', '*', \%where, 'filename' );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @attachments;
	while ( $self->{dbh}->nextRecord() ) {
		push @attachments, $self->{dbh}->getRecord();
	}
	return \@attachments;
}

sub getStatusDictionary {
	return \%STATUSDICTIONARY;
}

1;
