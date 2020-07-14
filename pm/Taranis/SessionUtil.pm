# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::SessionUtil;

## Taranis::SessionUtil: various functions relating to the currently logged in user.
##
## Not to be confused with Taranis::Session, the session storage interface.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use CGI::Simple;
use SQL::Abstract::More;
use Carp       qw(croak);
use List::Util qw(first);

use Taranis    qw(:util flat);
use Taranis::Database;
use Taranis::Config;
use Taranis::Role;
use Taranis::Category;
use Taranis::Publication;
use Taranis::Config::XMLGeneric;
use Taranis::FunctionalWrapper qw(CGI Config Database Sql);
use Taranis::Session qw(sessionCsrfToken sessionGet sessionIsActive);
use Taranis::Users qw(getMenuItems getUserRights combineRights);

sub currentRequest();

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	right rightOnParticularization validCsrfHeaderSupplied getSessionUserSettings
	setUserAction sessionHasRight currentRequest
);


# getSessionUserSettings(): Retrieve various settings for our current user, returns a hash ref.
#XXX the menuitems list sometimes has a single value, which means "all rights"
#XXX or an ARRAY, which it is 'particularization'.
sub getSessionUserSettings {
	my $pu = Taranis::Publication->new(Config);
	my $ca = Taranis::Category->new;

	my $vars;
	my $menuitems   = $vars->{menuitem} = getMenuItems(sessionGet('userid'));
	my $assess_cats = $menuitems->{assess};
	if(ref $assess_cats eq 'ARRAY') {
		my @categories;
		my %seen;
		foreach my $category (map lc, sort @$assess_cats) {
			next if $seen{$category}++;
			my $categoryId = $ca->getCategoryId($category);
			push @categories, { id => $categoryId, name => $category };
		}
		$vars->{assess_categories} = \@categories;
	} else {
		#XXX MO: $assess_cats eq 'items' from entitlement config.  No idea
		#XXX what that should represent.
		$vars->{assess_categories} = [ $ca->getCategory(is_enabled => 1) ];
	}

	my @status_options;
	if(ref $menuitems->{analyze} eq 'ARRAY') {
		@status_options = flat $menuitems->{analyze};
	} else {
		@status_options  = map trim($_), split /\,\s*/,
			Config->{analyze_status_options};
	}
	$vars->{analysis_status_options} = [ sort @status_options ];

	my @publications;
	if(ref $menuitems->{publications} eq 'ARRAY') {
		@publications = flat $menuitems->{publications};
	} else {
		@publications = $pu->getDistinctPublicationTypes;
	}
	$vars->{publication_options} = [ sort map lc, @publications ];

	# get the tools items for tools dropdown menu
	my $tools = Taranis::Config::XMLGeneric->new(Config->{toolsconfig}, "toolname", "tools");

	my @tools;
	foreach my $tool (flat $tools->{elements}) {
		$tool->{webscript} =~ m!^.*?/(.*?)/!i or next;
		push @tools, $tool if $menuitems->{$1};
	}
	$vars->{toolsconfig} = \@tools;

	# Get userinfo for display in window.
	my $userid = sessionGet('userid');
	my $ro     = Taranis::Role->new;

	$vars->{info_username} = $userid;
	if (my $roles = $ro->getRolesFromUser(username => $userid)) {
		$vars->{info_user_roles} = [ map $_->{name}, values %$roles ];
	}

	# Get organisation info and advisory prefix.
	$vars->{organisation} = Config->{organisation};
	$vars->{advisory_prefix} = Config->{advisory_prefix};
	$vars->{advisory_id_length} = Config->{advisory_id_length};

	return $vars;
}

# right('write');
# Check our user's rights for the entitlements matching the current request.
# Possible values for parameter are 'read', 'write', 'execute', 'particularization'.
# Returns:
# * For read/write/execute: 1 (if user has right) or 0 (if not).
# * For particularization: arrayref (if particularizations apply) or empty string (if not).
sub right {
	my ($right) = @_;

	my $userRights = getUserRights(
		username    => sessionGet('userid'),
		entitlement => _scriptEntitlements(),
	);
	my $combined = combineRights(values %$userRights);

	# Incoming $right name is one of read/write/execute/particularization,
    # but they're stored as
	# read_right/write_right/execute_right/particularization.
	my $right_fullname = $right =~ /^(?:read|write|execute)$/ ? "${right}_right" : $right;

	exists $combined->{$right_fullname}
		or die "right '$right' not found in user rights";

	$combined->{$right_fullname};
}

# $obj->rightOnParticularization('advisory (email)');
# Check the rights settings for a particularized entitlement.
sub rightOnParticularization {
	my $part_name = lc $_[0];

	my $p = right("particularization")
		or return 1;

	!! first { lc($_) eq $part_name } @$p;
}

# setUserAction(action => 'add category', comment => "added category with name 'foo'")
# Add a record to the user action log (table `user_action`).
sub setUserAction {
	my %arg = @_;
	$arg{username} ||= sessionGet('userid');

	# When we don't know which of this script's entitlements to log it
	# under, pick a random one.
	$arg{entitlement} ||= _scriptEntitlements()->[0];

	my ( $stmnt, @bind ) = Sql->insert( 'user_action', \%arg );
	my $sth = Database->prepare($stmnt);
	my $res = Database->executeWithBinds(@bind);
}

# From the entitlements config, get the entitlements belonging to the scriptname supplied in the request.
sub _scriptEntitlements {
	my $entitlementsConfig = Taranis::Config->new(Config->{entitlements});

	# Map current request to a scriptname to lookup in entitlements config. If
	# the request doesn't have a 'pageName' parameter, default to the special
	# case 'index' (= the "frontpage", /taranis/).
	my $scriptName = currentRequest->{pageName} // 'index';

	my $scriptEntitlements = $entitlementsConfig->{entitlement}->{$scriptName}->{use_entitlement}
		|| die 404;

	# Value is either a string (one matching <use_entitlement> in the config)
	# or an arrayref (multiple matching <use_entitlement>s in the config).
	# Force to an arrayref for consistency.
	$scriptEntitlements = [ $scriptEntitlements ]
		unless ref $scriptEntitlements eq 'ARRAY';

	$scriptEntitlements;
}

sub validCsrfHeaderSupplied {
	sessionIsActive && CGI->http('X-Taranis-CSRF-Token') eq sessionCsrfToken;
}

my %right_abbrevs = (r => 'read_right', w => 'write_right', x => 'execute_right');
sub sessionHasRight($$) {
	my ($entitlement, $right) = @_;

	my $rights = getUserRights(
		entitlement => $entitlement,
		username    => sessionGet('userid'),
	) or return 0;

	my $which = $right_abbrevs{$right} || $right;
	$rights->{$entitlement}{$which};
}

sub currentRequest() {
	my $scriptroot = Config->{scriptroot};
	$scriptroot   .= '/' if $scriptroot !~ m!/$!;

	my $path = $ENV{REQUEST_URI} || '';
	$path    =~ s/\?.*//;
	$path    =~ s/^\Q$scriptroot//
		or croak "request '$path' not within scriptroot '$scriptroot'";

	my %route;
	@route{ qw/type modName pageName action/ } = split m!/!, $path;
	\%route;
}

1;
