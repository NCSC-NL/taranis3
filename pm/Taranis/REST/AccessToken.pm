# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST::AccessToken;

use strict;
use warnings;

use Taranis qw(generateToken scalarParam val_int);
use Taranis::Database;
use Taranis::Users qw(checkUserPassCombination ensureModernHash);
use Taranis::FunctionalWrapper qw(Database Sql);

use JSON;
use SQL::Abstract::More;
use CGI;
use Taranis::REST;

Taranis::REST->addRoute(
	route    => qr[^auth/?$],
	method   => 'POST',
	handler  => \&_create_access_token,
	without_token => 1,
);

sub new {
	my ( $class, $config ) = @_;

	my $expiryTime = val_int $config->{access_token_default_expiry} || 60;

	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		expiry => $expiryTime
	};
	return( bless( $self, $class ) );
}

sub _create_access_token($) {
	my %args     = @_;
	my $config   = Taranis::Config->new;
	my $self     = __PACKAGE__->new($config);

	my $request  = $args{request};
	my $postdata = $request->param('POSTDATA');
	unless($postdata) {
		print CGI->header( -status => '406 Not acceptable');
		return;
	}

	my $login    = from_json $postdata;
	my $username = $login->{username};
	my $password = $login->{password};
	my $is_valid_user = 0;

	my $users       = Taranis::Users->new($config);
	if($username eq 'guest') {
		$is_valid_user = 1;
	} elsif(my $user = $users->getUser($username)) {
		if(checkUserPassCombination($username, $password)) {
			ensureModernHash($username, $password);
			$is_valid_user = 1;
		}
	}

	unless($is_valid_user) {
		print CGI->header( -status => '401 Unauthorized');
		return;
	}

	my $token = $self->generateAccessToken;
	$self->registerToken($username, $token);
	+{ access_token => $token };
}

sub addAccessToken {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	$self->{dbh}->addObject('access_token', \%inserts);
}

sub deleteAccessToken {
	my ( $self, $token ) = @_;
	undef $self->{errmsg};
	$self->{dbh}->deleteObject( 'access_token', {token => $token });
}

sub getAccessToken {
	my ( $self, %where ) = @_;

	my $select = "access_token.*, to_char(created, 'DD-MM-YYYY HH24:MI') AS created_str, to_char(last_access, 'DD-MM-YYYY HH24:MI') AS last_access_str, users.fullname";

	my ( $stmnt, @binds ) = $self->{sql}->select( 'access_token', $select, \%where, 'last_access DESC' );

	my %join = ( 'JOIN users' => { 'users.username' => 'access_token.username' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );

	my @tokens;
	while ( $self->{dbh}->nextRecord() ) {
		my $token = $self->{dbh}->getRecord();
		push @tokens, $token;
	}

	return \@tokens;
}

sub setAccessToken {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  

	if ( !exists( $settings{token} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}

	my $token = delete( $settings{token} );

	if ( $self->{dbh}->setObject( 'access_token', { token => $token }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub generateAccessToken {
	my ( $self ) = @_;

	my $token;

	do {
		$token = generateToken(32);
	} until !$self->{dbh}->checkIfExists({ token => $token },  'access_token');

	return $token;
}

sub registerToken {
	my ( $self, $username, $token ) = @_;
	return $self->addAccessToken( username => $username, token => $token, expiry_time => $self->{expiry} );
}

sub isValidToken {
	my ( $self, $token ) = @_;
	my $where = {
		token => $token,
		-or => [
			{
				expiry_time => \'IS NOT NULL',
				last_access => { '>' => \"NOW() - (expiry_time::text ||' minutes')::INTERVAL" }
			},
			{ expiry_time => \'IS NULL', }
		]

	};
	return $self->{dbh}->checkIfExists( $where,  'access_token' );
}
1;

=head1 NAME

Taranis::REST::AccessToken

=head1 SYNOPSIS

  use Taranis::REST::AccessToken;

  my $obj = Taranis::REST::AccessToken->new( $oTaranisConfig );

  $obj->getAccessToken( %where );

  $obj->addAccessToken( %accessToken );

  $obj->setAccessToken( %accessToken );

  $obj->deleteAccessToken( $token );

  $obj->generateAccessToken();

  $obj->isValidToken( $token );

  $obj->registerToken( $username, $token );

=head1 DESCRIPTION

CRUD, validation and registration functionality for access tokens.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::REST::AccessToken> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::REST::AccessToken->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the expiry time in minutes, defaults to 60 minutes:

    $obj->{expiry};

Returns the blessed object.

=head2 getAccessToken( %where )

Retrieves a list of access tokens. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

username: string

=item *

token: string

=item *

created: date

=item *

last_access: date

=item *

expiry_time: number

=back

    $obj->getAccessToken( id => 23 );

Returns an ARRAY reference.

=head2 addAccessToken( %accessToken )

Adds an access token log.

    $obj->addAccessToken( username => 'some_taranis_user', token => 'some_generated_token', expiry_time => 10 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setAccessToken( %accessToken )

Updates an access token. Key C<id> is mandatory.

    $obj->setAccessToken( username => 'some_taranis_user', expiry_time => 30 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteAccessToken( $token )

Deletes an access token.

    $obj->deleteAccessToken( 'some_generated_token' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 generateAccessToken()

Generates a token and returns it.

=head2 isValidToken( $token )

Checks whether the given token exists and if it's not expired.

Return TRUE or FALSE.

=head2 registerToken( $username, $token )

Shorthand for adding a token ( addAccessToken() )

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setAccessToken() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
