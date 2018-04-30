# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Constituent_Group;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use strict;
use SQL::Abstract::More;
use Tie::IxHash;
use Data::Validate qw(is_integer);

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
	my ( $stmnt, @bind ) = Sql->insert( $table, \%args );

	Database->prepare( $stmnt );
	if ( defined( Database->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = Database->{db_error_msg};
		return 0;
	}
}

sub setObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	if ( !defined( $args{id} ) || !is_integer( $args{id} ) ) {
		$self->{errmsg} = "No valid id given for routine.";		
		return 0;
	}	
	
	my $table = delete $args{table};
	my %where = ( id => delete( $args{id} ) );

	my ( $stmnt, @bind ) = Sql->update( $table, \%args, \%where );	

	Database->prepare( $stmnt );
	my $result = Database->executeWithBinds( @bind );
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( Database->{db_error_msg} ) ) {
			$self->{errmsg} = Database->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = Database->{db_error_msg} || "Action failed, corresponding id not found in database.";
		return 0;		
	}
}	

sub deleteObject {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};  
	my $table = delete $args{table};

	if ( $table eq "constituent_group" || $table eq "constituent_type" ) {
    $self->{errmsg} = "Cannot delete from specified table using this method. Please see perldoc for available methods.";
    return 0;		
	}
	
	my ( $stmnt, @bind ) = Sql->delete( $table, \%args );
	Database->prepare( $stmnt );
	my $result = Database->executeWithBinds( @bind );

	if ( $result !~ m/(0E0)/i ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( Database->{db_error_msg} ) ) {
			$self->{errmsg} = Database->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Delete failed, no record found in '$table'.";
		return 0;
	}	
}

sub nextObject {
	my ( $self ) = @_;
	return Database->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return Database->getRecord;		
}

sub loadCollection {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};
	
	my %where = Database->createWhereFromArgs( %searchFields );

	$where{status} = { '!=', 1 } if ( $searchFields{status} eq '' );
	
	my ( $stmnt, @bind ) = Sql->select( "constituent_type AS ct", "cg.*, ct.type_description", \%where, "name" );
	
	my $join = { "JOIN constituent_group cg " => {"ct.id" => "cg.constituent_type"} };
	$stmnt = Database->sqlJoin( $join, $stmnt );

	Database->prepare( $stmnt );
	my $result = Database->executeWithBinds( @bind );

	$self->{errmsg} = Database->{db_error_msg};
	return $result;
}

sub getGroupById {
	my ( $self, $id) = @_;
	undef $self->{errmsg};
	
	return 0 if ( $id !~ /^[0-9]*$/ );
	
	my $where = { id => $id };
	
	my ( $stmnt, @bind ) = Sql->select( 'constituent_group', '*', $where );
	
	Database->prepare( $stmnt );
	Database->executeWithBinds( @bind );
	
	$self->{errmsg} = Database->{db_error_msg};
	
	return Database->fetchRow();
}

sub getMemberIds {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	my @member_ids;
	my %where = ( "cg.id" => $id );
	
	my ( $stmnt, @binds ) = Sql->select( "constituent_group AS cg", "ci.id", \%where);
	tie my %join, "Tie::IxHash";
	%join = (
		"JOIN membership AS m" => { "m.group_id" => "cg.id" }, 
		"JOIN constituent_individual AS ci" => { "ci.id" => "m.constituent_id" } 
	);
						 
	$stmnt = Database->sqlJoin( \%join, $stmnt );

	Database->prepare( $stmnt );
	Database->executeWithBinds( $id );
	
	if ( defined( Database->{db_error_msg} )) {
		$self->{errmsg} = Database->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push( @member_ids, $self->getObject->{id} );
		}
		return @member_ids;
	}		
}

sub getMembers {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	my @members;
	my %where = ( "cg.id" => $id );

	my ( $stmnt, @binds ) = Sql->select( "constituent_group AS cg", "ci.*", \%where);
	tie my %join, "Tie::IxHash";
	%join = (
		"JOIN membership AS m"              => { "m.group_id" => "cg.id"            }, 
		"JOIN constituent_individual AS ci" => { "ci.id"      => "m.constituent_id" } 
	);

	$stmnt = Database->sqlJoin( \%join, $stmnt );

	Database->prepare( $stmnt );
	Database->executeWithBinds( $id );

	if ( defined( Database->{db_error_msg} )) {
		$self->{errmsg} = Database->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push( @members, $self->getObject() );
		}
		return @members;
	}
}

sub getTypeByID {
	my ($self, $id) = @_;
	undef $self->{errmsg};
	my %where;
	my @type_data;
	
	if ( $id ) { %where = ( id => $id ); }
	my ( $stmnt, @bind ) = Sql->select( "constituent_type", "*", \%where, "type_description" );

	Database->prepare( $stmnt );
	Database->executeWithBinds( @bind );
	
	if ( defined( Database->{db_error_msg} ) ) {
		$self->{errmsg} = Database->{db_error_msg};
		return 0;
	} else {
		while ( $self->nextObject ) {
			push ( @type_data, $self->getObject );
		}	
		if ( scalar @type_data > 1 ) {
			return @type_data;
		} else {
			return $type_data[0];
		}
	}			
}

sub deleteGroup {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	if ( !defined( $id ) || !is_integer( $id ) ) {
		$self->{errmsg} = "No valid id given for routine.";		
		return 0;
	}
		
	if ( Database->checkIfExists( {group_id => $id}, "membership" ) ) {
		$self->{errmsg} = "Cannot delete group, because this group still has members.";
		return 0;
	} else {

		# cleanup linking table for software/hardware usage
		my %where = ( group_id => $id );
		my( $stmnt, @bind ) = Sql->delete( "soft_hard_usage", \%where );

		Database->prepare( $stmnt );
		Database->executeWithBinds( @bind );
		
		return $self->setObject( status => 1, id => $id, table => "constituent_group" );
	}
}

sub deleteType {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	my $check_data = {constituent_type => $id};
	
	if ( !Database->checkIfExists( $check_data, "constituent_group" ) ) {
		
		# cleanup linking table
		my %where1 = ( constituent_type_id => $id );
		my( $stmnt1, @bind1 ) = Sql->delete( "type_publication_constituent", \%where1 );
		Database->prepare( $stmnt1 );
		Database->executeWithBinds( @bind1 );
	
		# delete constituent type
		my %where2 = ( id => $id );
		my( $stmnt2, @bind2 ) = Sql->delete( "constituent_type", \%where2 );
	
		Database->prepare( $stmnt2 );
	
		if ( Database->executeWithBinds( @bind2 ) > 0 ) {
			return 1;
		} elsif ( defined( Database->{db_error_msg} ) ) {
			$self->{errmsg} = Database->{db_error_msg};
			return 0;
		} else {
			$self->{errmsg} = "Delete failed, corresponding id not found in database.";
			return 0;
		}
	}	else {
		$self->{errmsg} = "Cannot delete type. A constituent group with this type still exists in the system.";
		return 0;
	}
}

sub deleteConstituentPublication {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	my @bind;
	
	my $sql =  "DELETE FROM constituent_publication
							WHERE constituent_publication.id NOT IN (
								SELECT cp2.id FROM constituent_publication AS cp2
								JOIN publication_type AS pt ON pt.id = cp2.type_id
								JOIN type_publication_constituent AS tpc ON tpc.publication_type_id = pt.id
								JOIN constituent_group AS cg ON cg.constituent_type = tpc.constituent_type_id
								JOIN membership AS m ON m.group_id = cg.id
							)";
							
	my $sql2 =  " WHERE m.constituent_id = ? )
						  AND constituent_publication.constituent_id = ?";

	if ( exists( $args{individual_id} ) ) {
		$sql =~ s/\)$/$sql2/;
		@bind = ( $args{individual_id}, $args{individual_id} );
	}

	Database->prepare( $sql );
	Database->executeWithBinds( @bind );
	
	if ( defined( Database->{db_error_msg} ) ) {
		$self->{errmsg} = Database->{db_error_msg};
		return 0;
	} else {
		return 1;
	}
}

sub getSoftwareHardwareIds {
	my ( $self, $id ) = @_;
	my %where = ( "cg.id" => $id );
	my @sh_ids;
	
	tie my %join, "Tie::IxHash";
	my ( $stmnt, @binds ) = Sql->select( "software_hardware AS sh", "sh.id", \%where, "sh.producer, sh.name, sh.version" );
	%join = ("JOIN soft_hard_usage AS shu" 	=> {"sh.id" => "shu.soft_hard_id"}, 
					 "JOIN constituent_group AS cg" => {"cg.id" => "shu.group_id" 	 } 
					);
	$stmnt = Database->sqlJoin( \%join, $stmnt );
	
	Database->prepare( $stmnt );
	Database->executeWithBinds( @binds );

	if ( defined( Database->{db_error_msg} ) ) {
		$self->{errmsg} = Database->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push( @sh_ids, $self->getObject->{id} );
		}
		return @sh_ids;
	}		
}

sub getSoftwareHardware {
	my ( $self, $id ) = @_;
	my %where = ( "cg.id" => $id );
	my @sh_data;
	
	tie my %join, "Tie::IxHash";
	my ( $stmnt, @binds ) = Sql->select( "software_hardware AS sh", "sh.*, sht.description", \%where, "sh.name" );
	%join = ( "JOIN soft_hard_usage AS shu"  => {"sh.id" 		=> "shu.soft_hard_id"	}, 
						"JOIN constituent_group AS cg" => {"cg.id" 		=> "shu.group_id" 		}, 
						"JOIN soft_hard_type AS sht" 	 => {"sht.base" => "sh.type" 					} 
					);
	$stmnt = Database->sqlJoin( \%join, $stmnt );

	Database->prepare( $stmnt );
	Database->executeWithBinds( @binds );
	
	if ( defined( Database->{db_error_msg} ) ) {
		$self->{errmsg} = Database->{db_error_msg};
		return;
	} else {
		while ( $self->nextObject ) {
			push( @sh_data, $self->getObject );
		}
		return \@sh_data;
	}	
}

sub callForHighHighPhoto {
	my ($self, $group_id) = @_;
	my $db = Database->{simple};
	$db->query(<<'__PHOTO_HH', $group_id)->list;
 SELECT 1 FROM constituent_group
  WHERE id = ?  AND use_sh  AND call_hh
__PHOTO_HH
}

sub callForHighHighAny {
	my ($self, $group_id) = @_;
	my $db = Database->{simple};
	$db->query(<<'__ANY_HH', $group_id)->list;
 SELECT 1 FROM constituent_group
  WHERE id = ?  AND NOT use_sh  AND any_hh
__ANY_HH
}

=head1 NAME 

Taranis::Constituent_Group - administration of constituent groups

=head1 SYNOPSIS

  use Taranis::Constituent_Group;

  my $obj = Taranis::Constituent_Group->new( $oTaranisConfig );

  $obj->addObject( table => $table_name, name => $my_groupname, use_sh => $yes_no, constituent_type => $constituent_type_id, status => $my_status );

  $obj->setObject( table => $table_name, id => $id, use_sh => $yes_no, etc... );

  $obj->deleteObject( table => $table, id => $id, status => $status, etc... );

  $obj->nextObject();

  $obj->getObject();

  $obj->loadCollection( use_sh => $yes_no, name => $group_name, etc... );

  $obj->getGroupId( $group_id );

  $obj->getMemberIds( $group_id );

  $obj->getMembers( $constituentGroupID );

  $obj->getTypeByID( $constituent_type_id );

  $obj->deleteGroup( $constituent_group_id );

  $obj->deleteType( $constituent_type_id );
  
  $obj->deleteConstituentPublication( individual_id => $individual_id );

  $obj->getSoftwareHardwareIds( $constituent_group_id );

  $obj->getSoftwareHardware( $constituent_group_id );		

  $obj->callForHighHighPhoto( $constituent_group_id );

  $obj->callForHighHighAny( $constituent_group_id );

=head1 METHODS

=head2 new( )

Constructor of the Taranis::Constituent_Group module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Constituent_Group->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};	  

Returns the blessed object.	

=head2 addObject( table => 'constituent_group', name => $my_groupname, use_sh => $yes_no, constituent_type => $constituent_type_id, status => $my_status )

Method for adding a constituent group (table: C<constituent_group>) or constituent type (table: C<constituent_type>).

Arguments must be specified as C<< column_name => "input value" >>. Also specify the table as below:

    $obj->addObject( table => "constituent_group", name => "Govcert", use_sh => 1, status -> 1, constituent_type => 4 );

Note: status can be left out because it is set to 0 (normal) by default.

Returns TRUE if insertion is successful, or FALSE if unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 setObject( able => $table_name, id => $id, use_sh => $yes_no, etc... )

Method for editing a constituent group or constituent type.
Arguments must be specified as C<< column_name => "input value" >>. Also specify the C<table> and C<id> as below. Both are mandatory:

    $obj->setObject( table => "constituent_type", id => 3, type_description => "Participant - Goverment" );

Returns TRUE if database update is successful or returns FALSE if update is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.	

=head2 deleteObject(  table => $table, id => $id, status => $status, etc... )

Method for deleting one or more records from specified table.
Takes arguments as C<< key => value >> where argument C<table> is mandatory:

    $obj->deleteObject( table => 'membership', group_id => '23' );

Table is mandatory but may not be C<constituent_group> or C<constituent_type> (use deleteGroup() and deleteType() instead).

Returns TRUE is deletion is successful and FALSE if database action fails. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by method loadCollection() . 

This way of retrieval can be used to get data from the database one-by-one. Both methods do not take arguments.

Example:

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
  	  myFunction( $obj->getObject );
    }

=head2 loadCollection( use_sh => $yes_no, name => $group_name, etc... )

Method for retrieval of a list of groups (or one group).
Arguments must be specified as C<< column_name => "input value" >>.

To retrieve all groups where status is normal (= 0) and which have supplied a list of software hardware usage:

    $obj->loadCollection( status => 0, use_sh => 0 );

To retrieve all groups no arguments should be supplied:

    $obj->loadCollection();

To retrieve a specific group:

    $obj->loadCollection( id => 5 );

Note: For values in C<$searchFields> that are of type integer an SQL '=' comparison is done. For values of other types an SQL ILIKE comparison is done! (= case insensitive LIKE comparison). 
Also, this method does not retrieve groups with status 1 (=deleted).

Returns the return value of C<< DBI->execute() >>. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getGroupId( $group_id )

Method for retrieving one group by group id, which is the mandatory argument.

    $obj->getGroupById( 87 );

Note: only retrieves data from table C<constituent_group>.

Returns the constituent group as a HASH reference. Sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 getMemberIds( $group_id )

Retrieves the id's of the members of one specific group.
The group id is a mandatory argument.

    $obj->getMemberIds( 24 );

When using this method the receiving variable should be an array:

    @ids = $obj->getMemberIds( '24' );

Returns an ARRAY with all the id's. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getMembers( $constituentGroupID )

Retrieves the details of all constituent individuals of a constituent group.

    $obj->getMembers( 89 );

Returns an ARRAY.

=head2 getTypeByID( $constituent_type_id )

Method for retrieval of one or all constituent types.
Optional argument id of a constituent type. If no argument is supplied all constituent types will be retrieved.

To retrieve one constituent type:

    $obj->getTypeByID( 3 );

To retrieve all constituent types:

    $obj->getTypeByID();

Returns an ARRAY of HASHES with all found types, except when the constituent type id is specified. In that case it will return a HASH.
Returns FALSE if there is a database error and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteGroup( $constituent_group_id )

Method for setting the status of a constituent group to deleted (status = 1).
A group can never be permenantly deleted from the database. Instead there are three status types:

=over

=item	*

0 = normal

=item *

1 = deleted

=item *

2 = temporally disabled

=back

The constituent group id is a mandatory argument.

    $obj->deleteGroup( 3 );

Note: also checks whether there is a dependency in table membership. If so it will return FALSE and set an error description in C<< $obj->{errmsg} >>.

Returns TRUE if database update is successful. 
Returns FALSE if delete is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.	

=head2 deleteType( $constituent_type_id )

Method for deleting a constituent type.
Constituent type id is a mandatory argument for this method.

    $obj->deleteType( 2 );

Note: also checks whether there is a dependency in table C<constituent_group>. If so it will return FALSE and set an error description in C<< $obj->{errmsg} >>.  

Returns TRUE if database deletion is successful.
Returns FALSE if delete is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteConstituentPublication( individual_id => $individual_id )

Deletes records from table constituent_publication that the consituent individual has no right to receive.
Which publication types an individual may receive depends on his memberships to groups and of what types those groups are, 
and how these types are configured. So when one of these factors changes the publication types for an individual have to be corrected where needed. 
This method takes care of just that.

The method takes one argument which is optional:

    $obj->deleteConstituentPublication( individual_id => '23' );

The argument should only be supplied when members are deleted from groups. The argument then corresponds to the member id.

Returns TRUE if database execution is successful. Returns FALSE if database execution fails and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 getSoftwareHardwareIds( $constituent_group_id )   

Retrieves the id's from the table C<software_hardware> for a specific constituent group.
Takes the consituent group id as argument:

    $obj->getSoftwareHardwareIds( '4' );

Returns an ARRAY of the software/hardware id's. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails. 

=head2 getSoftwareHardware( $constituent_group_id ) 	

Retrieves the software hardware for a specific constituent group.
Takes the consituent group id as argument:

    $obj->getSoftwareHardware( '4' );

Returns all the software/hardware for a specific constituent group. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails. 

=head2 callForHighHighPhoto( $constituent_group_id )

Method for retrieving the setting call for high/high advisory of a specific group.
Takes the constituent group id as mandatory argument.

    $obj->callForHighHighPhoto( 78 );

Returns the value of column C<call_hh> of table C<constituent_group>.

=head2 callForHighHighAny( $constituent_group_id )

Whether the constituent needs to be called on *any* H/H advisory.  This is
usually needed for large organisations which do not (want to) produced a
photo.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Action failed, corresponding id not found in database.> & I<Delete failed, corresponding id not found in database.> & I<Delete failed, no record found in 'table_x'.>

This can be caused when setObject() or deleteType() wants to update/delete a record that does not exist. You should check if argument C<id> has been specified. The method uses this in its WHERE clause. 

=item *

I<No valid id given for routine.>

For setObject() and deleteGroup() the id is a mandatory argument. If the id is undefined this message will be set.

=item *

I<Cannot delete group, because this group still has members.>

Caused by deleteGroup() when the specified group still has entries in table C<membership>.

=item *

I<Cannot delete type. A constituent group with this type still exists in the system.>

Caused by deleteType() when the specified type still has entries in table C<constituent_group>.

=item *

I<Cannot delete from specified table using this method. Please see perldoc for available methods.>

Caused by deleteObject() when the table argument has been set to C<constituent_group> or C<constituent_type>.

=back

=cut

1;
