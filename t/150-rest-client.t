#!/usr/bin/env perl

use warnings;
use strict;

use Test::More;
use CGI;
use JSON  qw(to_json);
use Data::Dumper;

require_ok 'Taranis::REST';

#
### Test route lookup
#

my $req1 = CGI->new;

$ENV{REQUEST_METHOD} = 'GET';
ok(! Taranis::REST::_find_route('auth', $req1), 'check method filter');

$ENV{REQUEST_METHOD} = 'POST';
my $route = Taranis::REST::_find_route('auth', $req1);
ok(defined $route, 'found authorization call');

#
### Test autorization: test token
#

$req1->add_parameter('POSTDATA');
$req1->{param}{POSTDATA} =
   [ to_json +{username => 'admin', password => 'admin'} ];

#warn Dumper $req1;

my $rest1 = Taranis::REST->new;
my $resp1 = $rest1->route('auth', $req1);
cmp_ok($rest1->{errmsg} || '', 'eq', '', 'no error for auth');

ok(defined $resp1, 'got auth answer');
ok(exists $resp1->{access_token}, 'got access_token');
my $token = $resp1->{access_token};
cmp_ok(length $token, '>', 20, 'token has length');
cmp_ok(scalar keys %$resp1, '==', 1);


#
### Get an advisory
#

my $req2 = CGI->new;
$ENV{REQUEST_METHOD} = 'GET';

# paramaters are passed via this object: we do not want to have the
# previous test interfere with this one.  Be aware: this is an object
# which administers the session info for a single request.
my $rest2 = Taranis::REST->new;
isa_ok($rest2, 'Taranis::REST', 'test get advisories');
my $uri2  = $rest2->cleanURI("advisories?access_token=$token");
my $resp2 = $rest2->route($uri2, $req2);
#warn Dumper $resp2;

cmp_ok($rest2->{errmsg} || '', 'eq', '', 'no error for advisories');

#
### Get an advisory
#

if(ref $resp2 eq 'ARRAY' && @$resp2) {
	my $adv_id = $resp2->[0]{id};
	my $req3 = CGI->new;
	$ENV{REQUEST_METHOD} = 'GET';

	# paramaters are passed via this object: we do not want to have the
	# previous test interfere with this one.  Be aware: this is an object
	# which administers the session info for a single request.

	my $rest3 = Taranis::REST->new;
	isa_ok($rest3, 'Taranis::REST', 'test get advisory');
	my $uri3  = $rest3->cleanURI("advisories/$adv_id?access_token=$token");
	my $resp3 = $rest3->route($uri3, $req3);
	#warn Dumper $resp3;

	cmp_ok($rest3->{errmsg} || '', 'eq', '', 'no error for advisory(1)');

} else {
	diag "there are no advisories to run test with";
}

#
### Test advisories/total?status=???
#

my $req4 = CGI->new;
$ENV{REQUEST_METHOD} = 'GET';

my $rest4 = Taranis::REST->new;
isa_ok($rest4, 'Taranis::REST', 'test get nr advisories');
my $uri4  = $rest4->cleanURI("advisories/total?status=pending&access_token=$token");
my $resp4 = $rest4->route($uri4, $req4);
#warn Dumper $resp4;

cmp_ok($rest4->{errmsg} || '', 'eq', '', 'no error for adv total');
ok(exists $resp4->{total}, 'got reply');
like($resp4->{total}, qr/^[0-9]+$/, 'valid reply');
cmp_ok(join(',', keys %$resp4), 'eq', 'total', 'no unexpected keys');

#
### Try via de webserver
#

use Taranis::Install::Config qw(config_release config_generic);
$ENV{TARANIS_HOME} = $ENV{HOME}; #XXX why
my $config  = config_generic;
my $release = config_release;
my $apache  = $release->{apache} || die;
$apache->{vhost_port} = 80;
my $uri     = ($apache->{use_https} ? 'https' : 'http') .
	"://$apache->{vhost_name}:$apache->{vhost_port}/taranis/REST/advisories?access_token=$token";
#print $uri;

use LWP::UserAgent ();
my $ua = LWP::UserAgent->new;
my $resp5 = $ua->get($uri);
#print $resp5->as_string;
cmp_ok $resp5->code, '==', 200, 'call webserver';
is $resp5->content_type, 'application/json';

done_testing;
