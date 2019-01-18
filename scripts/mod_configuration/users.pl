#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:all); 
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Users qw(generatePasswordHash);
use Taranis::Template;
use Taranis::Role;
use POSIX;

my @EXPORT_OK = qw( 
	displayUsers openDialogNewUser openDialogUserDetails
	saveNewUser saveUserDetails deleteUser
	searchUsers getUserItemHtml changeUserPassword
);

sub users_export {
	return @EXPORT_OK;
}

sub displayUsers {
	my ( %kvArgs) = @_;
	my ( $vars, @users, @roles );

	my $tt = Taranis::Template->new;
	my $usr = Taranis::Users->new( Config );
	my $ro = Taranis::Role->new( Config );
	
	my %usersHash;
	$ro->getUsersWithRole();
    while ( $ro->nextObject() ) {
    	my $user = $ro->getObject();
    	
    	if ( exists( $usersHash{ $user->{username} } ) ) {
    		$usersHash{ $user->{username} }->{role_name} .= ', ' . $user->{role_name} 
    	} else {
    		$usersHash{ $user->{username} } = $user;
    	}
    }

	foreach my $userId ( keys %usersHash ) {
		push @users, $usersHash{$userId};
	}
    
    $vars->{users} = \@users;

    $ro->getRole();
    while ( $ro->nextObject ) {
        push @roles, $ro->getObject();
    }

    $vars->{roles} = \@roles;
	$vars->{numberOfResults} = scalar @users;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('users.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('users_filters.tt', $vars, 1);
	
	my @js = ('js/users.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewUser {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 
	
	if ( $writeRight ) {
		my $ro = Taranis::Role->new( Config );
	    my @roles;
	    $ro->getRole();
	    while ( $ro->nextObject ) {
	        push @roles, $ro->getObject();
	    }
		
		$vars->{roles} = \@roles;
		
		$tpl = 'user_details.tt';
		
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { 
		dialog => $dialogContent,
		params => { writeRight => $writeRight }  
	};	
}

sub openDialogUserDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write"); 

	if ( exists( $kvArgs{id} ) && $kvArgs{id} ) {
		$id = $kvArgs{id};
		my $usr = Taranis::Users->new( Config );
		my $ro = Taranis::Role->new( Config );
		
		$vars->{user} = $usr->getUser( $id );

		my $userRoles = $ro->getRolesFromUser( username => $id );

		# get roles this user has.
		$vars->{membershipRoles} = $userRoles;

		my $allRoles = $ro->getRoles();
		my @allRolesList;

		# match membership roles with allroles
		# if a role from allroles is not present in user_role
		# add it to available roles
		foreach ( @$allRoles ) {
			if ( !defined( $userRoles->{ $_->{id} } ) ) {
				push @allRolesList, { name => $_->{name}, id => $_->{id} }; 
			}
		}

		$vars->{roles} = \@allRolesList;
		$vars->{description} = $id;

		$usr->getUserActions( 'ua.username' => $id, startDate => nowstring(0, 31), endDate => nowstring(9) );
		
		my @userActions;
		while ($usr->nextObject) {
			push @userActions, $usr->getObject();
		}
		$vars->{userActions} = \@userActions;

		$vars->{write_right} = $writeRight;
        
		$tpl = 'user_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};	
}

sub saveNewUser {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $usr = Taranis::Users->new( Config );
		$id = $kvArgs{username};
		my @membershipRoles = flat $kvArgs{membership_roles};

		my $saltedHash = Taranis::Users::generatePasswordHash($kvArgs{password});

		withTransaction {
			if ( 
				$usr->addUser(
					username => $kvArgs{username},
					fullname => $kvArgs{fullname},
					mailfrom_sender => $kvArgs{mailfrom_sender},
					mailfrom_email => $kvArgs{mailfrom_email},
					password => $saltedHash
				) 
			) {
				if ( scalar( @membershipRoles > 0 ) ) {
					foreach my $role (@membershipRoles) {
						if ( !$usr->setRoleToUser( username => $kvArgs{username}, role_id => $role ) ) {
							$message = $usr->{errmsg};
						}
					}
				}
			} else {
				$message = $usr->{errmsg};
			}
		};
	} else {
		$message = 'No permission';
	}
	
	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'add user', comment => "Added user '$kvArgs{username}'");
	} else {
		setUserAction( action => 'add user', comment => "Got error '$message' while trying to add user '$kvArgs{username}'");
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};
}

sub saveUserDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && exists( $kvArgs{id} ) && $kvArgs{id} ) {
		my $usr = Taranis::Users->new( Config );
		my $ro = Taranis::Role->new( Config );
		$id = $kvArgs{id};
		
		my %userUpdate = (
			username => $kvArgs{id},
			fullname => $kvArgs{fullname},
			mailfrom_sender => $kvArgs{mailfrom_sender},
			mailfrom_email => $kvArgs{mailfrom_email},		
		);
		
		if ( exists( $kvArgs{password} ) && $kvArgs{password} ) {
			$userUpdate{password} = Taranis::Users::generatePasswordHash($kvArgs{password});
		}

		my $currentRoles = $ro->getRolesFromUser( username => $kvArgs{id} );
		my @membershipRoles = flat $kvArgs{membership_roles};

		my %newRoles    = map { $_ => 1 } @membershipRoles;

		my @insertRoles = grep !defined $currentRoles->{$_}, @membershipRoles;
		my @deleteRoles = grep !defined $newRoles{$_}, keys %$currentRoles;
        
		withTransaction {
			if ( $usr->setUser( %userUpdate ) ) {
				foreach my $role ( @deleteRoles ) {
					if ( !$usr->delUserFromRole( username => $kvArgs{id}, role_id  => $role) ) {
						$message = $usr->{errmsg};
					}
				}

				foreach my $role ( @insertRoles ) {
					if ( !$usr->setRoleToUser( username => $kvArgs{id}, role_id  => $role ) ) {
						$message = $usr->{errmsg};
					}
				}
			} else {
				$message = $usr->{errmsg};
			}
        };
		
	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit user', comment => "Edited user '$id'");
	} else {
		setUserAction( action => 'edit user', comment => "Got error '$message' while trying to edit user '$id'");
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
}

sub deleteUser {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $usr = Taranis::Users->new( Config );

	if ( right("write") && exists( $kvArgs{id} ) && $kvArgs{id} ) {
		withTransaction {
			if ( 
				$usr->setUser( disabled => 1, username => $kvArgs{id} )
				&& $usr->delUserFromRole( username => $kvArgs{id} )
			) {
				$deleteOk = 1;
				setUserAction( action => 'delete user', comment => "Deleted user '$kvArgs{id}'");
			} else {
				$message = $usr->{errmsg};
				setUserAction( action => 'delete user', comment => "Got error '$message' while trying to delete user '$kvArgs{id}'");
			}
		};
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $kvArgs{id}
		}
	};	
}

sub searchUsers {
	my ( %kvArgs) = @_;
	my ( $vars, @users, %search );

	my $ro = Taranis::Role->new( Config );
	my $tt = Taranis::Template->new;

	if ( exists( $kvArgs{name} ) && $kvArgs{name} ) {
		$search{'username'} = ( { -ilike => [ '%' .  trim($kvArgs{name}) . '%' ] } );
		$search{'fullname'} = ( { -ilike => [ '%' .  trim($kvArgs{name}). '%' ] } );
    }

	if ( exists( $kvArgs{role_id} ) && $kvArgs{role_id} ) {
		$search{'role_id'} = $kvArgs{role_id};
	}

	my %usersHash;
	$ro->getUsersWithRole( %search );
	while ( $ro->nextObject() ) {
    	my $user = $ro->getObject();
    	
    	if ( exists( $usersHash{ $user->{username} } ) ) {
    		$usersHash{ $user->{username} }->{role_name} .= ', ' . $user->{role_name} 
    	} else {
    		$usersHash{ $user->{username} } = $user;
    	}
    }

	foreach my $userId ( keys %usersHash ) {
		push @users, $usersHash{$userId};
	}
	
	$vars->{users} = \@users;
	$vars->{numberOfResults} = scalar @users;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('users.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub getUserItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $ro = Taranis::Role->new( Config );
	my $usr = Taranis::Users->new( Config );
	
	my $insertNew = $kvArgs{insertNew};
	my $id = $kvArgs{id};
	
	my $user = $usr->getUser( $id );

	if ( $user ) {
		my $roles = $ro->getRolesFromUser( username => $id );
		$user->{role_name} = '';
		foreach my $roleID ( keys %$roles ) {
			$user->{role_name} .= $roles->{$roleID}->{name} . ', ';
		}
		
		$user->{role_name} =~ s/(.*?), $/$1/;
		$vars->{user} = $user;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'users_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Error: Could not find the new constituent individual...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}

sub changeUserPassword {
	my ( %kvArgs) = @_;
	my ( $message );
	my $changeOk = 0;
	
	my $usr = Taranis::Users->new( Config );

	my $saltedHash = Taranis::Users::generatePasswordHash($kvArgs{new_password});

	if (
		$kvArgs{new_password} && $kvArgs{id} 
		&& $usr->setUser( username => $kvArgs{id}, password => $saltedHash )
	) {
		$changeOk = 1;
		setUserAction( action => 'change password', comment => "Changed password for user '$kvArgs{id}'");
	} else {
		$message = $usr->{errmsg};
		setUserAction( action => 'change password', comment => "Got error '$message' while trying to change password for user '$kvArgs{id}'");
	}

	return { 
		params => {
			changeOk => $changeOk,
			message => $message
		} 
	};	
}
1;
