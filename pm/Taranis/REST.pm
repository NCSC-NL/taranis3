# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::REST;

use strict;
use warnings;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use File::Basename;
use List::Util qw(first);

my $plugins = scan_for_plugins 'Taranis::REST', load => 1;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		dbh => Database,
		errmsg => undef,
		accessToken => undef
	};
	return( bless( $self, $class ) );
}

my @routes;
sub addRoute(%) {
	my ($class, %config) = @_;
	$config{method} ||= 'GET';
	push @routes, \%config;
}

sub _find_route($$) {
	my ($url, $request) = @_;
	my $method = $request->request_method;
    first { $url =~ $_->{route} && $method eq $_->{method} } @routes;
}

sub cleanURI {
	my ( $self, $uri ) = @_;
	
	# strip standard REST path from uri
	$uri =~ s!^/taranis/REST/!!;

	#XXX This is not the way to do it!  may leave '&' at beginning or end
	$self->{accessToken} = $uri =~ s/\baccess_token=(\w+)// ? $1 : undef;

	# strip ending ? if there are no parameters
	$uri =~ s/\?$//;
	$uri =~ s/\+/ /g; #XXX very bad idea
	return $uri;
}

sub route {
	my ($self, $uri, $request) = @_;

	my $route  = _find_route $uri, $request;
	unless($route) {
		$self->{errmsg} = '405 method not allowed';
		return;
	}

	#XXX It is really a bad idea to decode the request parameters yourself,
	#XXX where this is also provided by the CGI module!
	my ($requestPath, $queryString) = split m[\?], $uri, 2;
	my @path = split '/', $requestPath;

	# split querystring (?key1=value1&key2=value2) in HASH
	my %queryParams;
	foreach my $param (split /\&/, $queryString || '') {
		length $param or next;  # leading or trailing resedu of token param
		my ( $key, $value ) = $param =~ /^(.*?)(?:=(.*?))?$/;
		
		if( !exists $queryParams{$key} ) {
			$queryParams{$key} = $value;
		} elsif(ref $queryParams{$key} eq 'ARRAY') {
			push @{$queryParams{$key}}, $value;
		} else {
			$queryParams{$key} = [ $queryParams{$key}, $value ];
		}
	}

	my $subReturn = eval {
		$route->{handler}->(
			dbh  => $self->{dbh},
			path => \@path,
			queryParams => \%queryParams,
			request => $request,
		);
	} // 0;

	if ( $@ ) {
		my $exception = $@;
		logErrorToSyslog($exception);

		$self->{errmsg}
		  = $exception =~ /^400/ ? '400 Bad Request'
		  : $exception =~ /^404/ ? '404 Not Found'
		  :                        '500 Server Error';

		return 0;
	}

	# collected as side effect during routeIsAllowed()
	$self->{doubleCheckParticularization}
		or return $subReturn;

	return $subReturn
	    if $self->hasParticularizationForResults($subReturn, $route->{entitlement});

	$self->{errmsg} = '403 Forbidden 1';
	return 0;
}

sub isRouteAllowed {
	my ($self, $uri, $accessToken, $request) = @_;
	undef $self->{errmsg};

	my $route  = _find_route $uri, $request
		or return 0;

	return 1
		if $route->{without_token};

	my $entitlement = $route->{entitlement};
	my $need_parts;
	if(ref $route && (my $p = $route->{particularizations})) {
		my $parts   = ref $p eq 'HASH' ? $p->{particularization} : [];
		$need_parts = ref $parts eq 'ARRAY' ? $parts : [ $parts ];
	}

	my $db = Database->{simple};
	my $roleRights = $db->query(<<'__RIGHTS', $accessToken, $entitlement)->hash;
 SELECT rr.*
   FROM access_token AS acct
        JOIN user_role   AS ur ON ur.username = acct.username
        JOIN role_right  AS rr ON rr.role_id  = ur.role_id
        JOIN entitlement AS e  ON e.id = rr.entitlement_id
  WHERE acct.token = ? AND e.name = ?
__RIGHTS

	my $rights = $self->{doubleCheckParticularization} =
		$roleRights->{read_right} ? $roleRights->{particularization} : undef;
	
	if($rights && $need_parts) {
		my %has_part = map +($_ => 1), split /\,/, $rights;

		my $isAllowed = grep $has_part{$_}, @$need_parts;
		return $isAllowed;
	}

	if($roleRights->{read_right}) {
		return 1;
	}

	$self->{errmsg} = '403 Forbidden 2';
	return 0;
}

sub hasParticularizationForResults {
	my ( $self, $results, $entitlement ) = @_;
	
	my %entitlementSetting = (
		analysis => 'status',
		items => 'category'
	);
	
	my $hasParticularization = 1;
	
	my %allowedParticularization = map { $_ => 1 } split(',', $self->{doubleCheckParticularization} );
	
	if(ref $results eq 'ARRAY') {
		foreach my $result ( @$results ) {
			if ( !exists( $allowedParticularization{ $result->{ $entitlementSetting{ $entitlement } } } ) ) {
				$hasParticularization = 0;
				last;
			}
		}
	} elsif (ref $results eq 'HASH') {
		if ( !exists( $allowedParticularization{ $results->{ $entitlementSetting{ $entitlement } } } ) ) {
			$hasParticularization = 0;
		}
	}
	
	return $hasParticularization;
}

sub getSuppliedToken {
	my ( $self ) = @_;
	return $self->{accessToken};
}
1;

=head1 NAME

Taranis::REST

=head1 SYNOPSIS

  use Taranis::REST;

  my $obj = Taranis::REST->new( $oTaranisConfig );

  $obj->cleanURI( $uri );

  $obj->getSuppliedToken();

  $obj->hasParticularizationForResults( $results, $entitlement );

  $obj->isRouteAllowed($uri, $accessToken, $request);

  $obj->route( $uri );

=head1 DESCRIPTION

Taranis is able to provide some information via a REST interface.
Authentication is based on the normal usernames and related access
restrictions.

Do not be confused by the name of this module: it is like a session
object: internally it stores information about the request, to get
it shared between components of the implementation.  For instance,
the provided access_token.

[3.4] It is a pluggable infrastructure, where each plugin defines its
own routes and handlers.  Before release 3.3, there was a configuration
file which mapped route to handlers.

=head1 METHODS

=head2 $class->new( [$config] )

Constructor of the C<Taranis::REST> module. An object instance of
Taranis::Config, which is optional, will be used for creating a database
handler.

    my $obj = Taranis::REST->new($config);

=head2 $obj->cleanURI($uri)

Strips standard REST path ('/taranis/REST/') from uri.
Retrieves the access token from uri and sets it to $self->{accessToken}. Also removes access token from uri.
Strip ending ? if there are no parameters.

Returns whats left of the uri.

=head2 getSuppliedToken()

Returns the access token from $self->{accessToken}.

=head2 hasParticularizationForResults( $results, $entitlement )

Checks if the user has particularization rights for the results.

Returns TRUE or FALSE.

=head2 isRouteAllowed( $uri, $accessToken, $request)

Checks if the REST route is allowed by any plugin.  Also checks if user
has read rights for the entitlement which is set for the route.

If FALSE, the $self->{errmsg} is set.

=head2 route($uri, $request)

Handles routing. Checks if uri has a route configured by any plugin.
The C<$uri> parameter is a stripped-down version string based on the
request URI: only the path relative to the rest root, and query parameters.
The access_token has been removed from the query parameters.

Returned is a Perl data-structure which has to be sent back to the
requestor in JSON format.  When a false value is returned (0 in case of
some legacy code, or C<undef>), then $self->{errmsg} is set.  All errors
are logged to syslog as well.

=cut
