# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Users;

## Taranis::Users: Taranis user management.
## Contains various users-related functions, plus Taranis::Users::Object, an old style "bag of functions" class that's
## being phased out. New code should use only the new-style functions in the main Taranis::Users package.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Crypt::SaltedHash;
use SQL::Abstract::More;
use Tie::IxHash;
use Digest::Bcrypt;
use String::Compare::ConstantTime;
use MIME::Base64 qw( encode_base64 decode_base64);

use Taranis::Config;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Config Database Sql Users);
use Taranis qw(trim generateToken);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	checkUserPassCombination ensureModernHash generatePasswordHash
	getMenuItems right rightOnParticularization getUserRights getSessionUserSettings combineRights
);


# Proxy "old style" methods through to Taranis::Users::Object for code that still uses them.
*new                  = \&Taranis::Users::Object::new;
*login                = \&Taranis::Users::Object::login;
*checkOldPassword     = \&Taranis::Users::Object::checkOldPassword;
*getUser              = \&Taranis::Users::Object::getUser;
*getUserActions       = \&Taranis::Users::Object::getUserActions;
*getUserActionsCount  = \&Taranis::Users::Object::getUserActionsCount;
*setUser              = \&Taranis::Users::Object::setUser;
*getUsersList         = \&Taranis::Users::Object::getUsersList;
*addUser              = \&Taranis::Users::Object::addUser;
*setRoleToUser        = \&Taranis::Users::Object::setRoleToUser;
*delUserFromRole      = \&Taranis::Users::Object::delUserFromRole;
*logBadLoginAttempt   = \&Taranis::Users::Object::logBadLoginAttempt;
*nextObject           = \&Taranis::Users::Object::nextObject;
*getObject            = \&Taranis::Users::Object::getObject;


sub checkUserPassCombination {
	my ($username, $password) = @_;
	my $hash = eval {getHashByUsername($username)} or return;

	# 'modern' style passwords means salted SHA-512
	if ($hash =~ /^\{SSHA512\}/) {
		return checkNewPassword($hash, $password);
	}

	# Most modern style of passwords is Bcrypt
	if ($hash =~ /^\{BCRYPT\}/) {
		return checkBcryptPassword($hash, $password);
	}

	# old style
	return Users->checkOldPassword(username => $username, password => $password);
}

sub checkBcryptPassword {
	my ($long_hash, $password) = @_;

	my ($indicator, $cost, $salt, $hash) = split(':', $long_hash);
	my $bcrypt = Digest::Bcrypt->new();
	$bcrypt->cost($cost);
	$bcrypt->salt(decode_base64($salt));
	$bcrypt->add($password);

	return String::Compare::ConstantTime::equals($bcrypt->b64digest, $hash);
}

sub getHashByUsername {
	my ($username) = @_;
	return Users->getUser($username)->{password};
}

# Was $hash made using our latest hashing scheme? (We've changed to a different hashing scheme in the past, and may do
# it again in the future.)
sub isModernHash {
	my ($hash) = @_;
	# Old style hashes were md5_base64(passwd), newest style hashes are BCRYPT with a "{BCRYPT}" prefix
	return $hash =~ /^\{BCRYPT\}/;
}

# Ensure user $username's password is hashed with the newest hashing scheme.
sub ensureModernHash {
	my ($username, $password) = @_;

	checkUserPassCombination($username, $password) or croak "user/pass combination not valid";

	if (!isModernHash( getHashByUsername($username) )) {
		# Looks like an old hashing method; replace with new hash.
		Users->setUser(username => $username, password => generatePasswordHash($password));
	}
}

sub generatePasswordHash {
	my ($password) = @_;

	my $cost = 10; # Seems reasonable

	my $salt = pack('H*', generateToken(16));

	my $bcrypt = Digest::Bcrypt->new();
	$bcrypt->cost($cost);
	$bcrypt->salt($salt);
	$bcrypt->add($password);

	return '{BCRYPT}:' . $cost . ':' . encode_base64($salt, '') . ':' . $bcrypt->b64digest;
}

# Is $hash a hash of $password?
sub checkNewPassword {
	my ($hash, $password) = @_;
	my $crypt = Crypt::SaltedHash->new(algorithm => 'SHA-512');
	return $crypt->validate($hash, $password);
}

# getMenuItems($username): retrieve all menuitems which user $username has read rights to.
# The 'main', 'menu' and 'configuration' templates use this data to render the menus.
#
# Returns a reference to a hash whose keys are entitlements, and whose values are either the same entitlement (if no
# particularizations apply) or an arrayref of particularizations:
# {
#     constituent_individuals => 'constituent_individuals',
#     assess => [
#         'security-news'
#     ],
#     publish_forward => 'publication',
#     publish_eod_public => 'publication',
#     ...
# }
sub getMenuItems {
	my ($username) = @_;

	my $menuitems;
	my $entitlementsConfig = Taranis::Config->new(Config->{entitlements});

	foreach my $program (keys %{ $entitlementsConfig->{entitlement} }) {

		if ($entitlementsConfig->{entitlement}->{$program}->{menuitem}) {

			# Entitlements that give access to script $program.
			my $scriptEntitlements = $entitlementsConfig->{entitlement}->{$program}->{use_entitlement};
			# Can be either a string or a ref to an array of strings; force into arrayref.
			$scriptEntitlements = [$scriptEntitlements] unless ref $scriptEntitlements;

			# Rights that our user has for the $scriptEntitlements.
			my $rights = getUserRights(username => $username, entitlement => $scriptEntitlements);

			foreach my $entitlement (keys %$rights) {

				if ($rights->{$entitlement}->{read_right}) {

					if ($rights->{$entitlement}->{particularization} ne '') {
						# Arrayref, e.g. ['news'] or ['news', 'tweets'].
						$menuitems->{$program} = $rights->{$entitlement}->{particularization};
					} else {
						# String (entitlement name), e.g. 'generic'.
						$menuitems->{$program} = $entitlement;
					}
				}
			}
		}
	}

	return $menuitems;
}

# getUserRights(username => 'someuser', entitlement => ['consituent_individuals', 'analysis']);
# Retrieves the rights of user with username $username for entitlement(s) $entitlements.
# $entitlements may be either a string or a ref to an array of strings.
#
# Return a hash reference, e.g.:
#     {
#         # Hash keys are entitlement names.
#         constituent_individuals => {
#             # Particularization: always either an array ref or an empty string (meaning 'no particularizations').
#             particularization => ['foo', 'bar'],
#             # (read|write|execute)_right: always 1 or 0.
#             read_right => 1,
#             execute_right => 1,
#             write_right => 0
#         },
#         analysis => {
#             particularization' => '',
#             read_right => 1,
#             execute_right => 0,
#             write_right => 1
#         }
#     }
sub getUserRights {
	my (%args) = @_;
	my $username = $args{username};
	my $entitlements = ref $args{entitlement} eq 'ARRAY' ? $args{entitlement} : [$args{entitlement}];


	# Construct and run query.
	my ($stmnt, @bind) = Sql->select(
		'role_right rr',
		'ent.name as ent_name, rr.read_right, rr.write_right, rr.execute_right, rr.particularization',
		{
			'ur.username' => $username,
			'ent.name' => $entitlements
		}
	);

	tie my %join, "Tie::IxHash";
	%join = (
		'JOIN user_role AS ur' => { 'ur.role_id' => 'rr.role_id' },
		'JOIN entitlement AS ent' => { 'rr.entitlement_id' => 'ent.id' },
	);
	$stmnt = Database->sqlJoin(\%join, $stmnt);
	Database->prepare($stmnt);
	Database->executeWithBinds(@bind);


	# Gather query results into @role_right_rows.
	my @role_right_rows;
	while ( Database->nextRecord ) {
		my $record = Database->getRecord;
		if ($record->{'particularization'} ne '') {
			$record->{'particularization'} = [ split(/,/, $record->{'particularization'}) ];
		}
		push @role_right_rows, $record;
	}


	# Process @role_right_rows into %result.
	my %result;

	for my $entitlement (@$entitlements) {
		my @role_right_for_ent = grep {
			$_->{ent_name} eq $entitlement
		} @role_right_rows;

		$result{$entitlement} = combineRights(@role_right_for_ent);
	}

	return \%result;
}

# combineRights: add multiple 'rights hashes' into one (e.g. to add up a user's rights stemming from multiple roles).
# Takes an arbitrary number (0 <= x <= infinity) of source hashes.
# Format of source and destination hashes is:
#
# {
#     # Particularization must be either an arrayref or an empty string (meaning 'no particularization').
#     particularization => ['foo', 'bar'],
#
#     # (read|write|execute)_right must be either 0 or 1 (not just true or false but exactly 0 or 1).
#     read_right => 0,
#     write_right => 0,
#     execute_right => 0,
# }
sub combineRights {
	my @sourceHashes = @_;

	if (@sourceHashes) {
		my %combinedHash;

		# Combine particularization rights. Particularizations only "count" in combination with read_right, so ignore
		# sourceHashes that don't have read_right.
		if (my @sourceHashesWithReadRight = grep { $_->{read_right} } @sourceHashes) {
			if (grep {$_->{particularization} eq ''} @sourceHashesWithReadRight) {
				# The {particularization} elements of the source hashes are always either an empty string or an
				# arrayref. Empty means 'all rights' (no particularization), so if any of them are '', the combined
				# right is also '' (again meaning "all rights, no particularization").
				$combinedHash{particularization} = '';
			} else {
				# Since none of our values are '', they must all be arrayrefs. Add the arrays together and deduplicate.
				my @particularizations;
				push @particularizations, @{ $_->{particularization} } for @sourceHashesWithReadRight;
				my %uniqueParticularizations = map {$_ => 1} @particularizations;
				$combinedHash{particularization} = [keys %uniqueParticularizations];
			}
		} else {
			# No read_rights in any of the sourceHashes, so no particularization either.
			$combinedHash{particularization} = '';
		}

		# Combine read/write/execute rights.
		for my $right (qw(read_right write_right execute_right)) {
			$combinedHash{$right} = (grep { $_->{$right} } @sourceHashes) ? 1 : 0;
		}

		return \%combinedHash;

	} else {
		# If 0 sourcehashes supplied, return basic 'no rights' hash.
		return {
			particularization => '',
			read_right => 0,
			write_right => 0,
			execute_right => 0,
		};
	}
}



package Taranis::Users::Object;

## Taranis::Users::Object: an old style "bag of functions" class that's being phased out. New code should use only the
## new-style functions in the main Taranis::Users package.


use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Digest::MD5 qw(md5_base64);


sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		user_role => {},
		role => {},
		role_right => {},
		entitlement => {},
		username => '',
		password => ''
	};
	return( bless( $self, $class ) );
}

# Check username and password, old style (for users who haven't logged in since we switched from MD5 to salted SHA512).
# Usage: $usr->login(username => 'username', password => 'password')
sub login {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my %where = ( password => md5_base64( $args{password} ), username => $args{username}, disabled => 0 );

	my ( $stmnt, @bind ) = $self->{sql}->select( 'users', 'COUNT(*)', \%where );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);
	my $cnt = $self->{dbh}->{sth}->fetch;

	if ( $cnt->[0] > 0 ) {
		return 1;
	} else {
		return 0;
	}
}
*checkOldPassword = \&login;

# Retrieve user details of a single user. When parameter $includeDisabled is true, selection will also include disabled
# users. Returns a hash reference (or 0).
sub getUser {
	my ( $self, $username, $includeDisabled ) = @_;
	undef $self->{errmsg};

	my %where = ( username => $username );
	$where{disabled} = 'f' if ( !$includeDisabled );

	my $select = "username, password, uriw, search, anasearch, anastatus, c.name AS category, c.id AS categoryid, "
		. "mailfrom_sender, mailfrom_email, lmh, statstype, hitsperpage, fullname, " 
		. "disabled, to_char(datestart, 'DD-MM-YYYY') AS date_start, "
		. "to_char(datestop, 'DD-MM-YYYY') AS date_stop, assess_orderby, source, assess_autorefresh";

	my ( $stmnt, @bind ) = $self->{sql}->select( "users", $select, \%where );

	my %join = ( 'LEFT JOIN category c' => { 'c.id' => 'category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	if ( $self->nextObject() ) {
		return $self->getObject();
	} else {
		$self->{errmsg} = "User doesn't exist.";
		return 0;
	}
}

# Execute a SELECT statement on table user_action which is joined with users.
# Usage: $usr->getUserActions( username => 'john', limit => 100, offset => 100 );
# The result of the SELECT statement can be retrieved by using getObject() and nextObject().
sub getUserActions {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	my $limit = ( exists( $where{limit} ) && $where{limit} =~ /^\d+$/ ) ? delete( $where{limit} ) : undef;
	my $offset = ( exists( $where{offset} ) && $where{offset} =~ /^\d+$/ ) ? delete( $where{offset} ) : undef;
	
	$where{startDate} .= " 000000" if ( $where{startDate} =~ /^\d{8}$/ );
	$where{endDate} .= " 235959" if ( $where{endDate} =~ /^\d{8}$/ );
	
	if ( exists( $where{startDate} ) && $where{startDate} && exists( $where{endDate} ) && $where{endDate} ) {
		$where{'ua.date'} = {-between => [ delete( $where{startDate} ), delete( $where{endDate} ) ] };
	} elsif ( exists( $where{startDate} ) && $where{startDate} ) {
		$where{'ua.date'} = { '>=' => $where{startDate} };
		delete $where{startDate};
		delete $where{endDate};
	} elsif ( exists( $where{endDate} ) && $where{endDate} ) {
		$where{'ua.date'} = { '<=' => $where{endDate} };
		delete $where{startDate};
		delete $where{endDate};
	} else {
		delete $where{startDate};
		delete $where{endDate};
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'user_action AS ua', "ua.*, u.fullname, to_char(ua.date, 'DD-MM-YYYY HH24:MI') AS logging_timestamp", \%where, 'ua.date DESC' );
	
	my %join = ( 'LEFT JOIN users AS u' => { 'u.username' => 'ua.username' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= " LIMIT $limit OFFSET $offset;" if ( $limit =~ /^\d+$/ && $offset =~ /^\d+$/ );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	return 1;
}

# Counts the records selected with parameter %where.
# Usage: $obj->getUserActionsCount( username => 'john' );
# Returns a number.
sub getUserActionsCount {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	if ( exists( $where{startDate} ) && $where{startDate} && exists( $where{endDate} ) && $where{endDate} ) {
		$where{'ua.date'} = {-between => [ delete( $where{startDate} ) . " 000000", delete( $where{endDate} ) . " 235959"] };
	} elsif ( exists( $where{startDate} ) && $where{startDate} ) {
		$where{'ua.date'} = { '>=' => $where{startDate} . ' 000000'};
		delete $where{startDate};
		delete $where{endDate};
	} elsif ( exists( $where{endDate} ) && $where{endDate} ) {
		$where{'ua.date'} = { '<=' => $where{endDate} . ' 235959'};
		delete $where{startDate};
		delete $where{endDate};
	} else {
		delete $where{startDate};
		delete $where{endDate};
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'user_action AS ua', "count(*) AS cnt", \%where );
	
	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);
	
	my $count = $self->{dbh}->fetchRow();
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	return $count->{cnt};
}

# Update a user's database record. %args must contain at least a 'username' key.
# Usage: $usr->setUser( username => 'john', fullname => 'John Doe 2nd' );
sub setUser {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my %where = ( username => delete $args{username} );

	my ( $stmnt, @bind ) = $self->{sql}->update( 'users', \%args, \%where );
	
	my $sth = $self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	return 1;
}

# Execute a SELECT statement on table `users`.
# Usage: $obj->getUsersList( %where )
# The result of the SELECT statement can be retrieved by using getObject() and nextObject().
sub getUsersList {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	$where{disabled} = 0;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'users', "username, fullname", \%where, "username" );
	$self->{dbh}->prepare($stmnt);

	if ( defined( $self->{dbh}->{sth}->errstr ) ) {
		$self->{errmsg} = $self->{dbh}->{sth}->errstr;
		return 0;
	}

	$self->{dbh}->executeWithBinds(@bind);
	return 1;
}

# Usage: $usr->addUser( username => 'john', fullname => 'John Doe', disabled => 'f', mailfrom_email =>
# 'johndoe@org.org', mailfrom_sender => 'John Doe');
sub addUser {
	my ( $self, %insert ) = @_;
	undef $self->{errmsg};

	$insert{disabled} = 0;

	my %checkdata = ( username => $insert{username} );

	if ( $self->{dbh}->checkIfExists( \%checkdata, 'users' ) ) {
		$self->{errmsg} = "Username exists, perhaps the $insert{username} is disabled?";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'users', \%insert );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}


# Grant a role to a user.
# Usage: $obj->setRoleToUser( username => 'john', role_id  => 789 );
sub setRoleToUser {
	my ( $self, %insert ) = @_;
	undef $self->{errmsg};

	if ( $insert{username} && $insert{role_id} ) {
		my ( $stmnt, @bind ) = $self->{sql}->insert( 'user_role', { username => $insert{username}, role_id => $insert{role_id} } );
	
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	
		if ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	return 1;
}

# Remove a role from a user.
# Usage: delUserFromRole( username => $username, role_id  => $roleID )
sub delUserFromRole {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my %where;

	if ( exists( $args{username} ) && $args{username} ) {
		$where{username} = $args{username};	
	}

	if ( exists( $args{role_id} ) && $args{role_id} ) {
		$where{role_id} = $args{role_id};	
	}
    
	if ( exists( $where{role_id} ) || exists( $where{username} ) ) {
		my ( $stmnt, @bind ) = $self->{sql}->delete( 'user_role', \%where );
		
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
	} else {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}

sub logBadLoginAttempt {
	my ( $self, $username ) = @_;
	
	my %insert = (
		entitlement => "generic",
		action => "login",
		comment => "Bad login attempt with username $username"
	);

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'user_action', \%insert );
	my $sth = $self->{dbh}->prepare( $stmnt );
	my $res = $self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{sth}->errstr ) ) {
		$self->{errmsg} = $self->{dbh}->{sth}->errstr;
		return 0;
	}
	return 1;	
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}

1;
