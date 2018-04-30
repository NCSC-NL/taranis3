# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Constituent_Individual;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Data::Validate qw(is_integer);
use Tie::IxHash;
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg 	=> undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub addObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my $table = delete $args{table};
	my ( $stmnt, @bind ) = $self->{sql}->insert( $table, \%args );

	$self->{dbh}->prepare( $stmnt );
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} .= $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my $table = delete $args{table};
	my %where = ( id => $args{id} );
	delete $args{id};
	my ( $stmnt, @bind ) = $self->{sql}->update( $table, \%args, \%where );	
	
	$self->{dbh}->prepare($stmnt);
	my $result = $self->{dbh}->executeWithBinds(@bind);
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {	
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} .= $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} .= "Action failed, corresponding id not found in database.";
		return 0;
	}
}	

sub deleteObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};  
	my $table = delete $args{table};

	if ( $table eq "constituent_individual" || $table eq "constituent_role" ) {
    $self->{errmsg} .= "Cannot delete from specified table using this method. Please see perldoc for available methods.";
    return 0;		
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, \%args );
	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( $result !~ m/(0E0)/i || $table eq "membership") {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} .= $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} .= "Delete failed, no record found in '$table'.";
		return 0;
	}	
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

sub loadCollection {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};	
	my %join;
	
	my %where = $self->{dbh}->createWhereFromArgs( %searchFields );

	$where{"ci.status"} = { '!=', 1 } if ( $searchFields{"ci.status"} eq '' );

	tie %join, "Tie::IxHash";
	my ( $stmnt, @bind ) = $self->{sql}->select( "constituent_individual AS ci", "ci.*, cr.role_name", \%where, "lastname, firstname" );
	if ( exists $where{"cg.id"} ) {
		
		%join = ( 
			"LEFT JOIN membership AS m"	=> {"m.constituent_id" => "ci.id" },
			"LEFT JOIN constituent_group AS cg" => {"cg.id" => "m.group_id"	},
			"JOIN constituent_role cr" => {"cr.id" => "ci.role" }
		);

	} else {
		%join = ( "JOIN constituent_role cr" => {"cr.id" => "ci.role"} );	
	}
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	return $result;	
}

sub deleteIndividual {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
		
	if ( !defined( $id ) || !is_integer( $id ) ) {
		$self->{errmsg} = "No valid id given for routine.";		
		return 0;
	}
	my $result = $self->setObject( status => 1, id => $id, table => "constituent_individual" );
	if ( $result ) {
		$self->deleteObject( table => "membership", constituent_id => $id );
		$self->deleteObject( table => "constituent_publication", constituent_id => $id );
		return $result;
	}	else {
		return $result;
	}
}

sub deleteRole {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};	
	
	if ( !defined( $id ) || !is_integer( $id ) ) {
		$self->{errmsg} = "No valid id given for routine.";		
		return 0;
	}	
	
	my %check_data = (role => $id);
	
	if ( !$self->{dbh}->checkIfExists( \%check_data, "constituent_individual" ) ) {
		
		my %where = (id => $id);
		my( $stmnt, @bind ) = $self->{sql}->delete( "constituent_role", \%where );
		
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
			$self->{errmsg} = "Delete failed, corresponding id not found in database.";
			return 0;
		}
	}	else {
		$self->{errmsg} = "Cannot delete role, because there is at least one constituent individual with this role.";
		return 0;
	}
}

sub getRoleByID {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};	
	my %where;
	my @role_data;
	
	if ( $id ) { %where = ( id => $id ); }
	my ( $stmnt, @bind ) = $self->{sql}->select( "constituent_role", "*", \%where, "role_name" );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );	

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push ( @role_data, $self->getObject );
		}	
		if( scalar @role_data > 1 ) {
			return @role_data;
		} else {
			return $role_data[0];
		}
	}	
}

sub getRoleIds {
	my ( $self, @role_names ) = @_;
	undef $self->{errmsg};
	my @ids;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "constituent_role", "id", { role_name => { ilike => \@role_names} } );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} )) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return;
	} else {	
		while ( $self->nextObject() ) {
			push @ids, $self->getObject()->{id};
		}
		return \@ids;
	}	
}

sub getGroups {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};	
	
	if ( !defined( $id ) || !is_integer( $id ) ) {
		$self->{errmsg} = "No valid id given for routine.";		
		return;
	}	
	
	my %where = ( "ci.id" => $id );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "constituent_group AS cg", "cg.*, ct.type_description", \%where, "name" );
	tie my %join, "Tie::IxHash";
	%join = ( "JOIN membership AS m" => { "m.group_id" => "cg.id" },
		"JOIN constituent_individual AS ci" => { "ci.id" => "m.constituent_id" },
		"JOIN constituent_type AS ct" => { "ct.id" => "cg.constituent_type" }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
 							 
	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	return $result;	
}

sub getGroupIds {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	my @group_ids;
	my %where = ( "ci.id" => $id );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "constituent_individual AS ci", "cg.id", \%where);
	tie my %join, "Tie::IxHash";
	%join = (
		"JOIN membership AS m" => { "m.constituent_id" => "ci.id" }, 
		"JOIN constituent_group AS cg" => { "cg.id" => "m.group_id" } 
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} )) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push( @group_ids, $self->getObject->{id} );
		}
		return @group_ids;
	}		
}

sub getPublicationTypesForIndividual {
  my ( $self, $id ) = @_;
  undef $self->{errmsg};
  my @types;

  my %where = ( "ci.id" => $id );
  
  tie my %join, "Tie::IxHash";
  my ( $stmnt, @bind ) = $self->{sql}->select("publication_type AS pt", "pt.*", \%where );
  %join = ( 
            "JOIN constituent_publication AS cp" => { "cp.type_id" => "pt.id"             }, 
            "JOIN constituent_individual AS ci"  => { "ci.id"      => "cp.constituent_id" } 
          );

  $stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
  
  $self->{dbh}->prepare( $stmnt );
  $self->{dbh}->executeWithBinds( @bind );
  
  if ( defined( $self->{dbh}->{db_error_msg} )) {
    $self->{errmsg} = $self->{dbh}->{db_error_msg};
    return 0;
  } else {
    while ( $self->nextObject ) {
      push( @types, $self->getObject() );
    }
    return \@types;
  } 
}	
	

=head1 NAME 

Taranis::Constituent_Individual - administration of constituent individuals

=head1 SYNOPSIS

  use Taranis::Constituent_Individual;

  my $obj = Taranis::Constituent_Individual->new( $oTaranisConfig );

  $obj->addObject( table => $table_name, column_name => $input_value, column_name => $input_value );

  $obj->setObject( table => $table_name, id => $id_nr, column_name => $input_value, column_name => $input_value );

  $obj->deleteObject( table => $table_name, id => $id_nr );

  $obj->nextObject();

  $obj->getObject();

  $obj->loadCollection( column_name => $search_value, column_name => $search_value );

  $obj->deleteIndividual( $constituent_individual_id );

  $obj->deleteRole( $constituent_role_id );

  $obj->getRoleByID( $constituent_role_id );

  $obj->getRoleIds( @role_names );

  $obj->getGroups( $constituent_individual_id );

  $obj->getGroupIds( $constituent_individual_id );

  $obj->getPublicationTypesForIndividual( $constituent_individual_id );

=head1 METHODS

=head2 new( )

Constructor of the Taranis::Constituent_Individual module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Constituent_Individual->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by;

    $obj->{errmsg};		  

Returns the blessed object.	  

=head2 addObject( table => $table_name, column_name => $input_value, column_name => $input_value )

Method for adding a constituent individual (table: C<constituent_individual>) or constituent role (table: C<constituent_role>) or a membership (table: C<membership>) or constituent publication wishes (table: C<constituent_publication>).
Arguments are HASH types: C<< {column_name => "input value", column_name => etc.} >>. It's mandatory to specify the table: C<< table => "my_table_name" >>: 

    $obj->addObject( table => "constituent_individual", firstname => "John", lastname => "Doe", constituent_role => 4, etc... );

Returns TRUE if database execution is successful. Returns FALSE if database execution and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 setObject( table => $table_name, id => $id_nr, column_name => $input_value, column_name => $input_value )

Method for editing (or rather updating) of constituent individual and constituent role and membership and constituent publication.
Argument are HASH types: C<< {column_name => "input value", column_name => etc.} >>. It's mandatory to specify the table and id: C<< table => "my_table_name", id => 3 >>: 

    $obj->setObject( id => 3 , table => "constituent_role", role_name => "System administrator" );

Returns TRUE if database update is successful. Returns FALSE if update is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.	

=head2 deleteObject( table => $table_name, id => $id_nr )

Method for deleting one or more records from the specified table.
Takes arguments as key value:

    $obj->deleteObject( table => 'membership', group_id => '23' );

Table is mandatory but may not be C<constituent_individual> or C<constituent_role> (use deleteIndividual() and deleteRole() instead).

Returns TRUE is deletion is successful and FALSE if database action fails. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by method loadCollection() . 

This way of retrieval can be used to get data from the database one-by-one. Both methods do not take arguments.

Example:

    $obj->loadCollection( $arg );

    while( $obj->nextObject ) {
      myFunction( $obj->getObject );
    }

=head2 loadCollection( column_name => $search_value, column_name => $search_value )

Method for retrieval of a list of individuals (or one individual).

Arguments are HASH types where the key is a column name.

To retrieve all individuals where status is normal (= 0):

    $obj->loadCollection( status => 0 );

To retrieve all individuals no arguments should be supplied:

    $obj->loadCollection();

To retrieve a specific individual:

    $obj->loadCollection( id => 5 );

Note: For values that are of type integer a SQL '=' comparison is done. For values of other types a SQL ILIKE comparison is done! (= case insensitive LIKE comparison). Also, this method does not retrieve individuals with status 1 (=deleted).

Returns the return value of C<< DBI->execute() >>. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 deleteIndividual( $constituent_individual_id )

Method for 'deleting' a constituent individual. Which means the status of the individual is changed to 3 (deleted);

Argument is a scalar of type Integer which represents the constituent individual ID:

    $obj->deleteIndividual( 4 );

Note: will also delete all the memberships (table C<membership>) of this user and all settings for receiving publications (table C<constituent_publication>). 
Also, because this method will perform several database actions the method should be called within a transaction. (see C<< Taranis::Database >> for startTransaction() and friends ).

Returns TRUE if status change is successful. Returns FALSE if status change is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteRole( $constituent_role_id )

Method for deleting a constituent role. 
Argument is a scalar of type integer that expects the ID of the role to be deleted:
  
    $obj->deleteRole( 4 );

Note: also checks whether there is a dependency in table C<constituent_individual>. 

Returns TRUE if database delete is successful. Returns FALSE if delete is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRoleByID( $constituent_role_id )

Method for retrieval of all or one constituent roles.
Argument is scalar of type integer and represents the id of a role.

Note: if no arguments are specified all roles will be retrieved

To retrieve one role:

    $obj->getRoleByID( 3 );

To retrieve all roles:

    $obj->getRoleByID();

Returns a HASH with all found roles. Returns C<undef> if there's a database error and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRoleIds( @role_names )

Method for retrieval of the id's for the supplied role names.
Argument is an ARRAY containing role names. Matching is done case-insensitive:

    $obj->getRoleIds( ['DSC Backup', 'System controller'] );

Return an ARRAY with id's. Returns C<undef> if there's a database error and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 getGroups( $constituent_individual_id )

Method for retrieval of all groups where an individual is a member of.
Argument is a scalar of type integer which is the id of an individual:

    $obj->getGroups( 5 );

Returns the return value of C<< DBI->execute() >>. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getGroupIds( $constituent_individual_id )

Method for retrieving the id's of constituent group where the individual is member of.
Argument is a scalar of type integer which is the id of an individual:

    $obj->getGroupIds( 23 );

Returns an ARRAY with all the id's. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getPublicationTypesForIndividual( $constituent_individual_id )

Retrieves the publication types which are configured for the selected constituent individual.

    $obj->getPublicationTypesForIndividual( 87 );

Returns an ARRAY reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Action failed, corresponding id not found in database.> & I<Delete failed, corresponding id not found in database.> & I<Delete failed, no record found in 'table_x'.>

This can be caused when setObject() , deleteRole() or deleteObject() wants to update/delete a record that does not exist. You should check if argument C<id> has been specified. The method uses this in its WHERE clause. 

=item *

I<No valid id given for routine.>

For getGroups() , deleteRole() and deleteIndividual() the id is a mandatory argument. If the id is undefined this message will be set.

=item *

I<Cannot delete role, because there is at least one constituent individual with this role.>

Caused by deleteRole() when the specified type still has entries in table C<constituent_individual>.

=item *

I<Cannot delete from specified table using this method. Please see perldoc for available methods.>

Caused by deleteObject() when the table argument has been set to C<constituent_individual> or C<constituent_role>.

=back

=cut

1;
