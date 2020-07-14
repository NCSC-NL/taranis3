# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Role;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Tie::IxHash;

#TODO: make input/output of subs of module Taranis::Role consistent with other modules

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		dbh          => Database,
		sql          => Sql,
		errmsg       => '',
		userrole     => {}, # ?
		entitlements => {}, # ?
		roles        => {}, # ?
		role_users   => {}  # ?
	};
	return( bless( $self, $class ) );
}

sub addRoleRight {
	my ( $self, %insert ) = @_;
	undef $self->{errmsg};

	if ( !defined( $insert{entitlement_id} ) ) {
		$self->{errmsg} = "Invalid input!";
		return 0;
	}

	# check if the entitlement exists
	if ( !$self->{dbh}->checkIfExists( { id => $insert{entitlement_id} }, 'entitlement' ) ) {
		$self->{errmsg} = "Unknown entitlement '" . $insert{entitlement_id} . "'";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'role_right', \%insert );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		return 1;
	}
}

#TODO: split sub into 'add' and 'set'
sub setRoleRight {
	my ( $self, %roleRightSettings ) = @_;
	undef $self->{errmsg};

	if ( !defined( $roleRightSettings{entitlement_id} ) ) {
		$self->{errmsg} = "Invalid input!";
		return 0;
	}

	my %where = ( 
		role_id => $roleRightSettings{role_id}, 
		entitlement_id => $roleRightSettings{entitlement_id} 
	);

	if ( $self->{dbh}->checkIfExists( {%where}, 'role_right' ) ) {
		# this record exists, so this must be an update.
		my %update;

		$update{read_right} = $roleRightSettings{read_right} if ( defined $roleRightSettings{read_right} );

		$update{write_right} = $roleRightSettings{write_right} if ( defined $roleRightSettings{write_right} );

		$update{execute_right} = $roleRightSettings{execute_right} if ( defined $roleRightSettings{execute_right} );

		$update{particularization} = ( defined $roleRightSettings{particularization} ) ? $roleRightSettings{particularization} : undef;

		my ( $stmnt, @bind ) = $self->{sql}->update( 'role_right', \%update, \%where );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}

	} else {
		# it's an insert
		my %insert;
	
		$insert{read_right} = $roleRightSettings{read_right} if ( defined $roleRightSettings{read_right} );

		$insert{write_right} = $roleRightSettings{write_right} if ( defined $roleRightSettings{write_right} );

		$insert{execute_right} = $roleRightSettings{execute_right} if ( defined $roleRightSettings{execute_right} );

		$insert{particularization} = $roleRightSettings{particularization} if ( defined $roleRightSettings{particularization} );

		$insert{entitlement_id} = $roleRightSettings{entitlement_id};
		$insert{role_id}        = $roleRightSettings{role_id};

		my ( $stmnt, @bind ) = $self->{sql}->insert( 'role_right', \%insert );
        
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );

		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	}

	return 1;
}

#TODO: replace this sub with getRoles()
sub getRole {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
		
	my ( $stmnt, @bind ) = $self->{sql}->select( 'role', "*", \%where, 'name' );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	
	return 1;
}

sub getRoles {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
		
	my ( $stmnt, @bind ) = $self->{sql}->select( 'role', '*', \%where, 'name' );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	
	my @roles;
	while ( $self->{dbh}->nextRecord() ) {
		push @roles, $self->{dbh}->getRecord();
	}
	return \@roles;
}

sub setRole {
	my ( $self, %updates ) = @_;
	undef $self->{errmsg};

	if ( !defined( $updates{id} ) ) {
		$self->{errmsg} = "Invalid input!";
		return 0;
	}

	my %where = ( id => delete $updates{id} );

	if ( !$self->{dbh}->checkIfExists( \%where, 'role' ) ) {
		$self->{errmsg} = "Unknown role.";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( 'role', \%updates, \%where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}

sub addRole {
	my ( $self, %roleSettings ) = @_;
	undef $self->{errmsg};

	my %insert = (
		name => $roleSettings{'name'},
		description => $roleSettings{'description'}
	);

	my %checkdata = ( name => $insert{name} );

	if ( $self->{dbh}->checkIfExists( \%checkdata, 'role' ) ) {
		$self->{errmsg} = "Name exists";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'role', \%insert );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		return 1;
	}
}

sub deleteRole {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	if ( !defined( $where{id} ) ) {
		$self->{errmsg} = "Invalid input!";
		return 0;
	}

	my $user_role_id = $where{id};
	
	# check if there are any user_role records referenced
	my ( $stmnt, @bind ) = $self->{sql}->select( 'user_role', 'count(*)', { role_id => $user_role_id } );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	while ( $self->nextObject ) {
		my $record = $self->getObject();
		
		if ( $record->{count} > 0 ) {
			$self->{errmsg} = 'There are ' . $record->{count} . ' users connected to this role';
			return 0;
		}
	}

	# delete all role_right records from this role
	( $stmnt, @bind ) = $self->{sql}->delete( 'role_right', { role_id => $user_role_id } );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	# delete the role record
	( $stmnt, @bind ) = $self->{sql}->delete( 'role', { id => $user_role_id } );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}

sub getRolesFromUser {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	if ( !defined( $where{username} ) ) {
		$self->{errmsg} = "Invalid input!";
		return 0;
	}

	$where{'ur.username'} = delete $where{'username'};

	my $select = 'rol.name, rol.description, ur.role_id';
	my ( $stmnt, @bind ) = $self->{sql}->select( 'user_role AS ur', $select, \%where, "rol.name" );

	my %join = ( "JOIN role AS rol" => { "ur.role_id" => "rol.id" } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	my $dbkey    = 'role_id';
	my $hash_ref = $self->{dbh}->{sth}->fetchall_hashref($dbkey);
	my $roles;
	
	while ( my ( $uKey, $uVal ) = ( each %$hash_ref ) ) {
		while ( my ( $key, $val ) = ( each %$uVal ) ) {
			next if ( $key eq $dbkey );
			$roles->{$uKey}{$key} = $val;
		}
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return $roles;
}

sub getUsersWithRole {
	my ( $self, %search ) = @_;
	undef $self->{errmsg};

	my %where;
	
	$where{'u.disabled'} = 'f';

	if ( defined( $search{role_id} ) ) {
		$where{'ur.role_id'} = $search{role_id};
	}

	if ( defined( $search{username} ) ) {
		if ( defined( $search{fullname} ) ) {
			$where{-or} = { 'u.fullname' => $search{fullname}, 'u.username' => $search{username}  };
		} else {
			$where{'u.username'} = $search{username};
		}
	}

	tie my %join, "Tie::IxHash";
	%join = (
		'LEFT JOIN user_role as ur' => { 'ur.username' => 'u.username' },
		'LEFT JOIN role as r' => { 'r.id' => 'ur.role_id' }
	);

	my $select = 'u.username , u.fullname, r.name as role_name';
	my ( $stmnt, @bind ) = $self->{sql}->select( 'users u', $select, \%where, 'u.username' );

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}

sub getRolesWithEntitlement {
	my ( $self, %arg ) = @_;
	undef $self->{errmsg};
	
	my $entitlement_id = ( defined $arg{entitlement_id} ) ? $arg{entitlement_id} : '';
	
	my $select   = "rol.name , rol.description,rol.id as id";
	my $from     = "role rol";
	my $group_by = ' GROUP BY rol.name, rol.description,rol.id';
	my %where = (
		-nest => [
			'rr.read_right' => 'true',
			'rr.write_right' => 'true',
			'rr.execute_right' => 'true'
		]
	);

	$where{'rr.entitlement_id'} = $entitlement_id if ( $entitlement_id );
	$where{'rol.name'} = { -ilike => "%$arg{name}%" } if ( $arg{name} );

	my %join = ( "JOIN role_right as rr" => { "rol.id" => "rr.role_id" } );

	my ( $stmnt, @bind ) = $self->{sql}->select( $from, $select, \%where );

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	$stmnt .= $group_by;
    
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
    
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		return 1;
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

sub getRoleRightsFromRole {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->select( 'role_right', '*', \%where );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	
	return 1;
}

1;

=head1 NAME

Taranis::Role

=head1 SYNOPSIS

  use Taranis::Role;

  my $obj = Taranis::Role->new( $oTaranisConfig );

  $obj->addRole( name => $name, description => $description );

  $obj->addRoleRight( %roleRight );

  $obj->deleteRole( id => $roleID );

  $obj->getRole( %where );

  $obj->getRoleRightsFromRole( %where );

  $obj->getRoles( %where );

  $obj->getRolesFromUser( username => $username );

  $obj->getRolesWithEntitlement( entitlement_id => $entitlementID, name => $entitlementName );

  $obj->getUsersWithRole( role_id => $roleID, username => $username, fullname => $fullname );

  $obj->setRole( id => $roleID, %update );

  $obj->setRoleRight( entitlement_id => $entitlement_id, %update );

=head1 DESCRIPTION

CRUD functionality for Roles and RoleRights.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Role> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Role->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addRole( name => $name, description => $description );

Adds a role.

    $obj->addRole( 'myrole', 'my new role' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 addRoleRight( %roleRight )

Adds an entitlement right to a role.

    $obj->addRoleRight( entitlement_id => 23, role_id => 34 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteRole( id => $roleID )

Deletes a role and all entries in table C<role_right> for the selected role.

    $obj->deleteRole( id => 354 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRole( %where )

Executes a SELECT statement on table C<role>.

    $obj->getRole( name => 'myrole' );

OR

    $obj->getRole();

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRoleRightsFromRole( %where ) 

Executes a SELECT statement on table C<role_right>.

    $obj->getRoleRightsFromRole( role_id => 23 );

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRoles( %where )

Retrieves roles.

    $obj->getRoles();

OR

    $obj->getRoles( name => 'myrole' );

Returns an ARRAY reference if successful. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getRolesFromUser( username => $username )

Retrieves all roles for a particular user.

    $obj->getRolesFromUser( username => 'someuser' );

Returns an HASH reference.

=head2 getRolesWithEntitlement( entitlement_id => $entitlementID, name => $entitlementName )

Executes a SELECT statement on table C<role> joined by table C<role_right>.

    $obj->getRolesWithEntitlement( entitlement_id => 34, name => 'admin' );

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getUsersWithRole( role_id => $roleID, username => $username, fullname => $fullname )

Executes a SELECT statement on table C<users> joined by tables C<user_role> and C<role>.

    $obj->getUsersWithRole( role_id => 98 );

OR

    $obj->getUsersWithRole( username => 'someuser', fullname => 'Some User' );

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setRole( id => $roleID, %update )

Updates a role. Parameter C<id> is mandatory.

    $obj->setRole( id => 23, name => 'somerolename', description => 'Some new role name' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setRoleRight( entitlement_id => $entitlement_id, %update )

Updates role rights. Paramater C<entitlement_id> is mandatory.

    $obj->setRoleRight(
        entitlement_id => 23 ,
        read_right => 1,
        role_id => 34,
        execute_right => 0,
        write_right => 1,
        particularization => 'parti1, parti2, parti3'
    );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid input!>

Caused by addRoleRight(), setRoleRight(), setRole(), deleteRole() or getRolesFromUser() when mandatory parameter is undefined.
You should check the input parameters.

=item *

I<Unknown entitlement '<entitlement_id>'.>

Caused by addRoleRight() when no entitlement can be found that corresponds with the parameter C<entitlement_id>.
You should parameter C<entitlement_id>.

=item *

I<Unknown role.>

Caused by setRole() when no role can be found that corresponds with the parameter C<id>.
You should parameter C<id>.

=item *

I<Name exists>

Caused by addRole() when trying to a role with a name which already exists.
You should change the new role name.

=item *

I<'There are ... users connected to this role'>

Caused by deleteRole() when trying to delete a role which is still set for one or more users.
You should first remove the role from users configuration.

=back

=cut
