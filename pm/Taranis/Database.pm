# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Database;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use DBI;
use DBIx::Simple;
use SQL::Abstract::More;
use Data::Validate qw(is_integer);
use Sys::Syslog qw( :DEFAULT setlogsock );
use ModPerl::Util;
use Encode qw(encode_utf8);
use Data::Dumper;
use Scalar::Util qw(weaken);

use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config Database Sql);
use Taranis qw(:all);
use Taranis::DB  ();


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	withTransaction withRollback
);


# Set $dsn_override to (dsn, user, pass) to override the database connection info from the configuration file.
# Used for testing.
our @dsn_override;

sub new {
	my ($class) = @_;

	my $self = {
		sth => undef,
		record => undef,
		db_error_msg => undef,
		open_transaction_counter => 0,
		log_error_enabled => ( Config->{'syslog'} =~ /^on$/i ) ? 1 : 0,
		sql => Sql,
	};
	bless $self, $class;

	$self->connect;
	return $self;
}

# do( $sql_non_select_query )
# You should use executeWithBinds() instead!!
# The method do() takes an SQL non-select query, but does not handle bindings in SQL.
# Returns the return value of DBI->do().
sub do {
	my ($self, $arg) = @_;
	my $dbh = $self->{dbh};
	my $return_val;

	eval { $return_val = $dbh->do($arg) };

	if ( $@ ) {
		$self->logError($@);
		die $@;
	} else {
		$self->{db_error_msg} = undef;
	}

	return $return_val;
}

sub nextRecord {
	my ($self) = @_;
	return $self->{record} = $self->{sth}->fetchrow_hashref;
}

sub getRecord {
	my ($self) = @_;
	return $self->{record};
}

sub allRecords() {
	my $sth = shift->{sth};
	my @records;
	while(my $record = $sth->fetchrow_hashref) {
		push @records, $record;
	}
	@records;
}

sub fetchRow {
	my ($self) = @_;
	return $self->{sth}->fetchrow_hashref;
}

sub active {
	my ($self) = @_;
	return $self->{dbh}->{Active};
}

sub connect {
	my ($self) = @_;
	my $user     = Config->{dbuser};
	my $name     = Config->{dbname};
	my $pass     = Config->{dbpasswd};
	my $dbhost   = Config->{dbhost};
	my $dbi      = Config->{dbi};
	my $dbdriver = Config->{dbdriver};
	my $dbport   = Config->{dbport};
	my $sslmode  = Config->{dbsslmode} =~ /^(disable|allow|prefer|require)$/
		 ? $1 : 'prefer';

	my $dbparam = $dbhost eq 'peer'
	  ? "dbname=$name"
	  : "dbname=$name;host=$dbhost;port=$dbport;sslmode=$sslmode";

	my $dbh = $self->{dbh} = DBI->connect(
	   "$dbi:$dbdriver:$dbparam", $user, $pass,
	    { AutoCommit => 1, PrintError => 0, RaiseError => 1}
	);
    $dbh or die "Couldn't connect to the database";

	$self;
}

sub simple() {
	my $self = shift;
	$self->{simple} ||= Taranis::DB->new(
		dbh       => $self->{dbh},
		old_style => $self,
	);
}

sub disconnect {
	my ($self) = @_;
	delete $self->{simple};
	$self->{dbh}->disconnect();
}

# Start transaction, or if already in a transaction, a savepoint. Nestable.
# (PostgreSQL doesn't support nested transactions, but savepoints provide roughly the same functionality.)
sub startTransaction {
	my ($self) = @_;

	$self->{open_transaction_counter}++
		# Already in a transaction, so use a savepoint.
		? $self->{dbh}->pg_savepoint("tx$self->{open_transaction_counter}")
		# Not in a transaction yet, so start one.
		: $self->{dbh}->begin_work;
}

# Commit most recent transaction or savepoint.
sub commitTransaction {
	my ($self) = @_;

	$self->{open_transaction_counter} > 1
		? $self->{dbh}->pg_release("tx$self->{open_transaction_counter}")
		: $self->{dbh}->commit;
	$self->{open_transaction_counter}--;
}

# Rollback most recent transaction or savepoint.
sub rollbackTransaction {
	my ($self) = @_;

	$self->{open_transaction_counter} > 1
		? $self->{dbh}->pg_rollback_to("tx$self->{open_transaction_counter}")
		: $self->{dbh}->rollback;
	$self->{open_transaction_counter}--;
}

# Nestable transaction "decorator", inspired by Django's @atomic. Opens a transaction or savepoint, executes the code,
# and commits. If an (uncaught) exception happens inside the code, rolls back the transaction/savepoint instead.
# Usage is something like:
#     withTransaction {
#         do thing;
#         withTransaction {
#             do other thing;
#         };
#         do last thing;
#     };
# This is an ordinary function, not a class method. Doesn't really belong here, among the class methods, but I don't
# know a better place.
sub withTransaction (&) {
	my ($code) = @_;

	Database->startTransaction;

	my $return = eval { $code->() };
	if (my $errmsg = $@) {
		Database->rollbackTransaction;
		die $errmsg;
	}

	Database->commitTransaction;
	return $return;
}

# Nestable transaction "decorator" that rolls back instead of committing.
sub withRollback (&) {
	my ($code) = @_;

	Database->startTransaction;

	my $return = eval { $code->() };
	my $errmsg = $@;

	Database->rollbackTransaction;

	die $errmsg if $errmsg;
	return $return;
}

sub prepare {
	my ( $self, $stmnt ) = @_;
	return $self->{sth} = $self->{dbh}->prepare($stmnt);
}

sub executeWithBinds {
	my ( $self, @binds ) = @_;
	my $return_val;
	eval { $return_val = $self->{sth}->execute(@binds); };

	if ( $@ ) {
		$self->logError( $@ . "\n==> STMNT: " . $self->{sth}->{Statement} . "\n==> BINDS: @binds" );
		die $@;
	} else {
		$self->{db_error_msg} = undef;
	}
	return $return_val;
}


# logError( $error, $syslog_priority )
# Method for logging errors to syslog, but only if $obj->{log_error_enabled} has been set.
# Also causes $db_error_msg of the Database object to be set, causing Taranis::FunctionalWrapper::Croaker (which
# normally wraps this class) to throw an exception.
sub logError {
	my ( $self, $error, $prioritySetting ) = @_;

	my $logging_ok = 0;

	if ( $self->{log_error_enabled} ) {

		my $priority = ( exists( Config->{syslog_priority} ) && Config->{syslog_priority} =~ /^(EMERG|ALERT|CRIT|ERR|WARNING|NOTICE|INFO|DEBUG)$/i )
			? Config->{syslog_priority}
			: undef;

		$priority = $prioritySetting if ( $prioritySetting =~ /^(EMERG|ALERT|CRIT|ERR|WARNING|NOTICE|INFO|DEBUG)$/i );
			
		my $facility = ( exists( Config->{syslog_facility} ) && Config->{syslog_facility} =~ /^local[0-7]$/i )
			? Config->{syslog_facility}
			: undef;

		my $pid = ( exists( Config->{syslog_pid} ) && Config->{syslog_pid} =~ /^on$/i )
			? 'pid'
			: '';

		if ( $priority && $facility ) {
			setlogsock('unix');
			openlog( 'TARANIS', $pid, $facility );
			syslog( $priority, encode_utf8($error) );
			closelog;
			$logging_ok = 1; 
		}
	}

	$self->{db_error_msg} = ( $logging_ok ) 
		? "Database error, please check log for info."
		: "Database error. (Error cannot be logged because logging is turned off or is not configured correctly).";
}

#### data struture $join_columns is { "JOIN table" => { column_id => column_id } }
# (INNER) JOIN: Return rows when there is at least one match in both tables
# LEFT (OUTER) JOIN: Return all rows from the left table, even if there are no matches in the right table
# RIGHT (OUTER) JOIN: Return all rows from the right table, even if there are no matches in the left table
# FULL JOIN: Return rows when there is a match in one of the tables
sub sqlJoin {
	my ( $self, $join_columns, $stmnt ) = @_;
	my ( $str, $table_key);
	my %columns;

	for $table_key ( keys %$join_columns ) {
		$str .= " " . $table_key . " ON ";
		my $columns = $join_columns->{$table_key};
		for my $column_key ( keys %$columns ) {
			$str .= $column_key . " = " . $columns->{$column_key};
		}
	}

	if ( $stmnt =~ m/(WHERE)/ ) {
		$stmnt =~ s/( WHERE \()/$str WHERE \(/;
	} elsif ( $stmnt =~ m/(ORDER BY)/ ) {
		$stmnt =~ s/( ORDER BY )/$str ORDER BY /;
	} else {
		$stmnt .= $str;
	}
	return $stmnt;
}

# checkIfExists( \%checkData, $table_name, $case_sensitivity )
# Method for checking if certain data exists in database.
# Takes 3 arguments, first two are mandatory;
# * an HASH reference where the keys are table column names and values are the data to check for.
# * table name
# * case sensitivity, set to true for case insensitive search
# Example: $obj->checkIfExists( { name => 'news' }, 'category', 'IGNORE_CASE' );
sub checkIfExists {
	my ( $self, $checkData, $table, $case ) = @_;
	my %where;

	if ( $case  ) {
		for my $key ( keys( %$checkData ) ) {
			if ( defined( is_integer( $checkData->{$key} ) ) || ( ref( $checkData->{$key} ) eq "HASH" ) ) {
				$where{$key} = $checkData->{$key};
			} elsif ( $checkData->{$key} ) {
				$where{$key}{-ilike} = $checkData->{$key};
			}
		}
	} else {
		%where = %$checkData;
	}

	return !! $self->simple->select($table, "count(*)", \%where)->list;
}

# countRows( \%checkData, $table_name, $case_sensitivity )
# Does exactly the same as checkIfExists() , but LIMIT 1 is left out and it returns the result of COUNT(*).
sub countRows {
	my ( $self, $checkData, $table, $case, $include_undef ) = @_;
	my %where;

	if ( $case ) {
		for my $key ( keys( %$checkData ) ) {
			if (
				defined( is_integer( $checkData->{$key} ) )
				|| ( ref( $checkData->{$key} ) =~ /^(HASH|SCALAR|ARRAY)$/ ) 
				|| ( $include_undef && !$checkData->{$key} ) 
			) {
				$where{$key} = $checkData->{$key};
			} elsif ( $checkData->{$key} ) {
				$where{$key}{-ilike} = $checkData->{$key};
			}
		}
	} else {
		%where = %$checkData;
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( $table, "COUNT(*)", \%where );
	$self->prepare( $stmnt );
	$self->executeWithBinds( @bind );

	my $cnt = $self->{sth}->fetch;
	$cnt->[0];
}

sub getLastInsertedId {
	my ( $self, $table ) = @_;
	my $id = eval { $self->{dbh}->last_insert_id( undef, undef, $table, undef, undef ) };
	if ( $@ ) { 
		$self->logError( $@ );
		return 0;
	}

	$id;
}

# createWhereFromArgs( %args )
# Create a where HASH suitable for using with SQL::Abstract::More.
# It will turn strings into ILIKE comparison with wildcards (%) at start and end of string. Integers will be set to
# an = comparison.
# ARRAYs will be turned into ARRAY reference ( = \@ ) comparison for SQL::Abstract::More.
#    $obj->createWhereFromArgs( %args );
# Returns a HASH.
sub createWhereFromArgs {
	my ( $self, %args ) = @_;
	my %where;
	
	for my $key ( keys(%args) ) {
		if ( ref( $args{$key} ) eq "ARRAY" ) {
			$where{$key} = \@{ $args{$key} };
		} elsif ( $args{$key} ne "" && $args{$key} =~ /^\d+$/ ) {
			$where{$key} = $args{$key};
		} elsif ( $args{$key} ne "" ) {
			$where{$key}{-ilike} = "%" . trim( $args{$key} ) . "%";
		}
	}
	
	return %where;
}

# sqlJoin( \%join_columns, $sql_query )
# Edit an SQL query with a JOIN part, return the SQL query with the JOIN inserted.
# It takes two mandatory arguments:
# * HASH reference, that has several parts:
#   * JOIN part, 'JOIN mytable AS alias'
#   * ON part, is an HASH with the two joining columns: { 'alias1.id_column' => 'alias2.id_column' }
# * the SQL query to edit the JOIN in
# Example:
#     $obj->sqlJoin( 
#                    {
#                      'JOIN item' => { 'item.digest' => 'email_item.digest' },
#                      'JOIN category' => { 'item.category' => 'category.id' } 
#                    },
#                    $sql_query
#                  );
# Replace 'JOIN' by 'LEFT JOIN' etc. as desired.
sub getResultCount {
	my ( $self, $stmnt, @bind ) = @_;
	
	$stmnt =~ s/SELECT .*? FROM/SELECT COUNT(*) FROM/is;
	$stmnt =~ s/ORDER.*//i;

	return scalar $self->simple->query($stmnt, @bind)->list;
}

sub addObject {
	my ( $self, $table, $inserts, $returnID ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( $table, $inserts );
	$self->prepare( $stmnt );
	
	if ( defined( $self->executeWithBinds( @bind ) ) > 0 ) {
		if ( $returnID ) {
			return $self->getLastInsertedId( $table );
		} else {
			return 1;
		}
	} else {
		return 0;
	}
}

# setObject( $table, $where, $update )
# Method to execute an SQL UPDATE. Takes three mandatory arguments:
# * tablename
# * an HASH reference representing the WHERE clause
# * an HASH reference representing the update settings
sub setObject {
	my ( $self, $table, $where, $update ) = @_;

	unless(keys %$where) {
		$self->{db_error_msg} = "Cannot perform update, because whereclause is missing.";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( $table, $update, $where );
	$self->prepare( $stmnt );

	$self->executeWithBinds( @bind );

	if ( defined( $self->{db_error_msg} ) ) {
		return 0;
	} else {
		return 1;
	}
}

# deleteObject( $table, \%where )
# Generic method for deleting a record of table C<$table>. C<%where> must be defined.
#     $obj->deleteObject( 'collector', { id => 93 } );
sub deleteObject {
	my ( $self, $table, $where ) = @_;

	if ( !scalar( %$where ) ) {
		$self->{db_error_msg} = "Cannot perform update, because whereclause is missing.";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, $where );

	$self->prepare( $stmnt );
	my $result = $self->executeWithBinds( @bind );
	if ( defined($result) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{db_error_msg} ) ) {
			return 0;
		}
	} else {
		$self->{db_error_msg} = "Delete failed, corresponding id not found in database.";
		return 0;
	}
}

# Add a binary as large object to database.
sub addFileAsBlob {
	my ( $self, %args ) = @_;
	my $binary = $args{binary};
	
	$self->startTransaction();  # lo_* can only be used within a transaction.

	my $mode = $self->{dbh}->{pg_INV_WRITE};
	if ( my $oid = $self->{dbh}->func( $mode, 'lo_creat' ) ) {

		my $lobj_fd = $self->{dbh}->func( $oid, $mode, 'lo_open' );
		my $fileSize = $self->{dbh}->func( $lobj_fd, $binary, length( $binary ), 'lo_write' );
		my %blobDetails = ( oid => $oid, fileSize => $fileSize );

		$self->commitTransaction();

		return \%blobDetails;
	} else {
		$self->rollbackTransaction();
		$self->{errmsg} = 'Could not create large object (lo_creat)';
		return 0;
	}
}

# getBlob( object_id => $oid, size => $file_size )
# Retrieves a binary from database, returns the binary or 0 on error.
sub getBlob {
	my ( $self, %args ) = @_;

	if ( $args{object_id} =~ /^\d+$/ && $args{size} =~ /^\d+$/ ) {
		my $blob;
		my $mode = $self->{dbh}->{pg_INV_READ};

		withTransaction {  # lo_* can only be used within a transaction.
			my $lobj_fd = $self->{dbh}->func( $args{object_id}, $mode, 'lo_open' );
			$self->{dbh}->func( $lobj_fd, $blob, $args{size}, 'lo_read' );
		};
		return $blob;
	}
	
	return 0;
}

1;
