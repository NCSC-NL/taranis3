# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Error;

use strict;

use SQL::Abstract::More;
use Encode;
use HTML::Entities qw(encode_entities);

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Install::Config  qw(config_release);

sub logDirectory() {
	my $self = shift;
	return $self->{TE_logdir} if $self->{TE_logdir};

	my $release = config_release;
	my $logdir = "$release->{logs}/collector-errors";
	mkdir $logdir;

	$self->{TE_logdir} = $logdir;
}

sub new {
	my ( $class, $config ) = @_;
	my $self = {
		dbh => Database,
		sql => Sql,
		errmsg => undef,
		result_count => undef
	};
	
	return( bless( $self, $class ) );
}

sub deleteLog {
	my ( $self, $log_id ) = @_;

	my ( $stmnt, @bind ) = $self->{sql}->delete( "errors", { id => $log_id } );
	
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
		$self->{errmsg} = "Error log was not found in database.";
		return 0;
	}	
}

sub deleteLogs {
	my ( $self, $logs, $errorCode ) = @_;
	undef $self->{errmsg};

	## delete all log files (.txt) in log directory 
	my $dir = $self->logDirectory;
	my $dh;
	opendir( $dh, $dir ) or $self->{errmsg} = "Cannot open log directory.";
	
	my @files = readdir( $dh );
	
	chdir( $dir );
		
	foreach my $file ( @files ) {

		if ( exists( $logs->{$file} ) && !unlink( $file ) ) {
			$self->{errmsg} = "Error: cannot delete log $file.";
			return 0;
		} 
	}	
	
	## delete logs from database
	my %where = ( error_code => $errorCode );
	my ( $stmnt, @bind ) = $self->{sql}->delete( 'errors', \%where );
	
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
		$self->{errmsg} = "Error log was not found in database.";
		return 0;
	}
	
}

sub deleteAllLogs {
	my $self = shift;
	undef $self->{errmsg};
	
	## delete all log files (.txt) in log directory 
	my $dir = $self->logDirectory;
	my $dh;
	opendir( $dh, $dir ) or $self->{errmsg} = "Cannot open log directory.";
	
	if ( $self->{errmsg} ) {
		return 0;
	}
	
	my @files = readdir( $dh );
	
	chdir( $dir );
		
	foreach my $file ( @files ) {
		if ( $file =~ /(.*?\.txt)$/ ) {
			$file = $1;
			if ( !unlink( $file ) ) {
				$self->{errmsg} = "Error: cannot delete log $file.";
				return 0;
			} 
		} 
	}	
	
	## delete all log from database
	my $stmnt = "DELETE FROM errors";
	
	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds();

	if ( $result !~ m/(0E0)/i ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Error log was not found in database.";
		return 0;
	}	
	
}

sub getErrorsById {
	my ( $self, $id ) = @_;
	my %where = ( digest => $id );

	my ( $stmnt, @bind ) = $self->{sql}->select( "errors", "*, to_char(time_of_error, 'DD-MM-YYYY HH24:MI:SS') AS time", \%where, "time_of_error DESC" );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @errors;
	while ( $self->nextObject() ) {
		push @errors, $self->getObject();
	}
	
	return \@errors;
	
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

sub getDistinctErrorCodes {
	my ( $self ) = @_;
	my @error_codes;
	
	my $stmnt = "SELECT DISTINCT error_code FROM errors ORDER BY error_code;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		push @error_codes, $self->getObject()->{error_code};
	}
	
	return \@error_codes;	
}

sub loadCollection {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	my $offset = delete( $args{offset} ); 

	my %where = $self->{dbh}->createWhereFromArgs( %args );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "errors err", "err.*, to_char(time_of_error, 'DD-MM-YYYY HH24:MI:SS') AS datetime, src.sourcename, src.id AS sourceid, src.fullurl", \%where, "time_of_error DESC, src.sourcename" );
	my %join = ( "LEFT JOIN sources src" => { "src.digest" => "err.digest" } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{result_count} = $self->{dbh}->getResultCount( $stmnt, @bind );
	
	$stmnt .= " LIMIT 100 OFFSET " . int($offset) if ( defined $offset );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	return $result;
}

sub getError {
	my ( $self, $id ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "errors err", "err.*, src.sourcename", { 'err.id' => $id } );
	my %join = ( "LEFT JOIN sources src" => { "src.digest" => "err.digest" } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $error = $self->{dbh}->fetchRow();
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	return $error;
}

sub writeError {
	my ($self, %arg ) = @_;

	my $error     	= $arg{error};
	my $errorCode 	= $arg{error_code};
	my $timeStamp 	= nowstring(2);
	my $content   	= $arg{content};
	my $referenceId	= $arg{reference_id} || undef;

	my $source      = $arg{source};
	my $digest    	= $arg{digest}     || $source->{digest};
	my $sourceName 	= $arg{sourceName} || $source->{sourcename};

	my $filename = "";
	
	$error = encode_entities( $error ) if ( $error );
	$errorCode = $self->getCollectorErrorCode( $errorCode ); 

	if ( $content ) {
		my $logDirectory = $self->logDirectory;
	
		my $unique = generateToken(4);
		$filename  = "$logDirectory/$timeStamp-feederror-$sourceName-$unique.txt";
		
		eval { 
			open my $fh, ">:encoding(utf8)", $filename;
			$fh->print("ERROR($errorCode): $error\n");
			$fh->print("REF-ID: $referenceId\n");
			$fh->print($content);
			$fh->close;
	  };
	
		if ( $@ ) {
			$error .= "\nFailed to write error logfile: $@";
		}
	}
	
	my %insert = ( digest => $digest, error => $error, error_code => $errorCode, logfile => $filename, reference_id => $referenceId );
	my ( $stmnt, @bind ) = $self->{sql}->insert( 'errors', \%insert );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
	}
}

sub getCollectorErrorCode {
	my ( $self, $codeNumber ) = @_;

	my $defaultCode = "C000";
	my %errorCode = (
		503 => "C503",
		502 => "C502",
		500 => "C500",
		404 => "C404",
		403 => "C403",
		401 => "C401",
		400 => "C400",
		301 => "C301",
		204 => "C099",
		408 => "C001",
		'010' => "C010", # imap/pop3 connection error
		'011' => "C011", # MIME parsing error
		'012' => "C012", # Link exceeds max length ( in case of mail source: caused by scriptroot setting in main config )
		'013' => "C013", # Not in use anymore
		'014' => "C014", # CVE/Identifier write error
		'015' => "C015", # Advisory import error
		'016' => "C016", # Collector notification regarding Advisory imports
		'017' => "C017", # software/hardware problem during advisory import
		'018' => "C018", # imported advisory has references to original publisher
		'019' => "C019", # screenshot failure
		'020' => "C020"  # End-of-Shift auto send notification
	);
 
	return $errorCode{ $codeNumber } ? $errorCode{ $codeNumber } : $defaultCode;
}


=head1 NAME 

Taranis::Error - module for controlling data in table errors, as well as log files generated by the collector.

=head1 SYNOPSIS

  use Taranis::Error;

  my $obj = Taranis::Error->new( $oTaranisConfig );

  $obj->deleteLog( $log_id );

  $obj->deleteLogs( $logs, $errorCode );

  $obj->deleteAllLogs();

  $obj->getErrorsById( $source_digest );

  $obj->nextObject();

  $obj->getObject();

  $obj->getDistinctErrorCodes();

  $obj->loadCollection( \%args );

  $obj->getError( $log_id );

  $obj->writeError(source => $source, error => 'Error message', error_code => '404', content => $errorContent );

  $obj->getCollectorErrorCode( $errorCodeNumber );

=head1 DESCRIPTION

When running the collector all kinds of errors may occur. This module deals with saving these errors to database and in some cases creating a log file on disk.
Next to save and creating this module also provides methods for deleting logs from database and disk.

=head1 METHODS

=head2 new( $oTaranisConfig )

Constructor of the Taranis::Error module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};
	  
Clears error message for the new object. Can be accessed by:
   
    $obj->{errmsg};	  

Returns the blessed object.

=head2 deleteLog( $log_id )

Method for deleting logs from database. (not file logs)
Takes the id of a log as parameter:

    $obj->deleteLog( '23' );

Returns TRUE if deletion is successful. 
Returns FALSE if deletion is unsuccessful and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.  

=head2 deleteLogs( $logs, $errorCode )

Deletes the logs with the specified errorcode from database, and deletes all files in logs argument. 

The logs argument is an HASH reference where the keys are the filename of the logs and the values are at least a true value.

    my $logs = { 'file_x.txt' => 1, 'file_y.txt' => 1 };
    $obj->deleteLogs( $logs, 'C012' );

Returns TRUE if file and database deletion are successful. 
Returns FALSE if a database error occurs and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
Will also return FALSE if deletion of logfiles fails, which will lead to C<< $obj->{errmsg} >> to be set with an error description. 

=head2 deleteAllLogs( )

Method for deleting all database entries in table C<errors> and all files in log directory.

    $obj->deleteAllLogs();

Returns TRUE if file and database deletion are successful. 
Returns FALSE if a database error occurs and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
Will also return FALSE if deletion of logfiles fails, which will lead to C<< $obj->{errmsg} >> to be set with an error description.

=head2 getErrorsById( $log_id )

Method for retrieving all errors of a particular source.
Takes the source digest as parameter:

    $obj->getErrorsById( 'UU/GiHB5oN0M+f7OMttUkA' );

Returns an ARRAY containing all the errors for the source.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method  like loadCollection() .

This way of retrieval can be used to get data from the database one-by-one. Both methods don't take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=head2 getDistinctErrorCodes( )

Method for retrieving a list of all (currently set) error codes.
Takes no arguments;

    $obj->getDistinctErrorCodes();

Returns an ARRAY containing all (currently set) error codes.

=head2 loadCollection( \%args )

Method for retrieving error logs from database.
Takes arguments that correspond with columns of table C<errors>. The format for this is C<< column_name => value >>.

    $obj->loadCollection( error_code => 'C100', digest => 'UU/GiHB5oN0M+f7OMttUkA' );

Returns the return value of C<< DBI->execute() >>. Sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getError( $log_id )

Method for retrieving an errorlog from database.
Takes the ID of a log as parameter:

    $obj->getError( '23' );

Returns an HASH containing the error log details. Sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 writeError(source => $source, error => 'Error message', error_code => '404', content => $errorContent )

Method for logging an error to database and creating a logfile. The contents of the logfile is set the C<content> argument. 

    $obj->writeError(
         source => $source,
         error => 'error message',
         error_code => '010',
         content    => 'error contents for log file'
    );

Returns TRUE if successful. 
Returns FALSE if a database error occurs and will set C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
Will also return FALSE if writing a logfile fails, which will lead to C<< $obj->{errmsg} >> to be set with an error description.

=head2 getCollectorErrorCode( $errorCodeNumber )

Retrieves the Taranis error code. The argument is one of the codes below without the leading 'C'. Except for C099, which has codenumber 204.

    $obj->getCollectorErrorCode( '010' );

Currently defined Taranis error codes are:

=over

=item *

B<C010>, imap/pop3 connection error.

=item *

B<C011>, MIME parsing error.

=item *

B<C012>, Link exceeds max length ( in case of mail source: caused by scriptroot setting in main config ).

=item *

B<C014>, CVE/Identifier Parse Error.

=item *

B<C015>, Advisory import error

=item *

B<C016>, Collector notification regarding Advisory imports

=item *

B<C017>, Software/hardware problem during advisory import

=item *

B<C018>, Imported advisory has references to original publisher

=item *

B<C019>, Screenshot failure

=item *

B<C099>, No items found.

=item *

B<C301>, B<C400>, B<C401>, B<C403>, B<C404>, B<C500>, B<C502> and B<C503>, corresponds with the HTTP status code (without the leading 'C').

=item *

B<C000>, other undefined error. 

=back

Returns the Taranis error code. If code number cannot be matched with a code number in the method the Taranis error code 'C000' will be returned.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Error log was not found in database.>

Caused by not deleteLog() , deleteLogs() or deleteAllLogs() when the
log cannot be found in database.  For deleteLog() you should check the
C<$log_id> argument. For deletelogs() you should check the C<$errorCode>
argument.

=item *

I<Cannot open log directory.>

You should check if the C<< $obj->logDirectory >> setting has been set correctly and if the rights for the directory are sufficient.

=item *

I<Error: cannot delete log 'file_x'> & I<Failed to write error logfile: 'specific error message'>

You should check if the C<< $obj->logDirectory >> setting has been
set correctly and if the rights for the directory are sufficient.
You should also check if the supplied 'file_x' is present and if the
rights for the file are sufficient for writing.

=back

=cut

1;
