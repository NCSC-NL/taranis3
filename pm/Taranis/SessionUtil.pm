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

use Taranis::Database;
use Taranis::Config;
use Taranis::Role;
use Taranis::Category;
use Taranis::Publication;
use Taranis::Config::XMLGeneric;
use Taranis qw(:util);
use Taranis::FunctionalWrapper qw(CGI Config Database Sql);
use Taranis::Session qw(sessionCsrfToken sessionGet sessionIsActive);
use Taranis::Users qw(getMenuItems getUserRights combineRights);
use Taranis::RequestRouting qw(currentRequest);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	right rightOnParticularization validCsrfHeaderSupplied getSessionUserSettings
	setUserAction
);


# getSessionUserSettings(): Retrieve various settings for our current user, returns a hash ref.
sub getSessionUserSettings {
	my $vars;
	my @analysis_status_options;
	
	foreach my $status (split(",", Config->{analyze_status_options})) {
		push @analysis_status_options, trim( $status );
	}

	my $ca = Taranis::Category->new;
	my @assessCategoriesFromDatabase = $ca->getCategory( 'is_enabled' => 1 );
	
	my $pu = Taranis::Publication->new(Config);
	my @publication_options = $pu->getDistinctPublicationTypes();

	$vars->{menuitem} = getMenuItems(sessionGet('userid'));

	my @assessCategoriesFromSession;
	my %uniqueCategory;
	if ( ref( $vars->{menuitem}->{assess} ) eq "ARRAY" ) {
		foreach my $category ( sort @{ $vars->{menuitem}->{assess} } ) {
			$category = lc( $category );
			
			if ( !exists( $uniqueCategory{ $category } ) ) {
				$uniqueCategory{ $category} = 1;
				
				my $categoryId = $ca->getCategoryId( $category );
				
				push @assessCategoriesFromSession, { id => $categoryId, name => $category };
			}
		}
	}

	my @all_categories = ( ref( $vars->{menuitem}->{assess} ) ne "ARRAY" ) ?  @assessCategoriesFromDatabase : @assessCategoriesFromSession;
	
	@{ $vars->{assess_categories} } = @all_categories;

	@{ $vars->{analysis_status_options} } = sort (( ref( $vars->{menuitem}->{analyze} ) ne "ARRAY" ) ? @analysis_status_options : @{ $vars->{menuitem}->{analyze} });

	my @publications = ( ref( $vars->{menuitem}->{publications} ) ne "ARRAY" ) ? @publication_options : @{ $vars->{menuitem}->{publications} };
	my %tmp_publications = map( { lc $_ => 1 } @publications );
	@{ $vars->{publication_options} } = sort keys %tmp_publications;
	
	# get the tools items for tools dropdown menu
	my $tools = Taranis::Config::XMLGeneric->new(Config->{toolsconfig}, "toolname", "tools");
	my $tools_config = $tools->{elements};
	
	my $menuitems = $vars->{menuitem};

	foreach my $tool ( @$tools_config ) {
		
		if ( $tool->{webscript} =~ /^.*?\/(.*?)\//i ) {			
			my $tool_id = $1;
			if ( exists( $menuitems->{ $tool_id } ) ) {
				push @{ $vars->{toolsconfig} }, $tool;
			}
		}
	}

	# Get userinfo for display in window.
	my $userid = sessionGet('userid');
	my $ro = Taranis::Role->new;
	
	my $roles = $ro->getRolesFromUser( username => $userid);
	
	$vars->{info_username} = $userid;
	if ($roles) {
		foreach my $id ( keys %$roles ) {
			push @{ $vars->{info_user_roles} },  $roles->{$id}->{name};
		}
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
		'username' => sessionGet('userid'),
		'entitlement' => _scriptEntitlements()
	);

	# Incoming $right name is one of read/write/execute/particularization, but they're stored as
	# read_right/write_right/execute_right/particularization.
	my $right_fullname = ($right =~ /^(read|write|execute)$/) ? $right . '_right' : $right;

	my $combined = combineRights(values %$userRights);
	return $combined->{$right_fullname} // die "right '$right' not found in user rights";
}

# $obj->rightOnParticularization('advisory (email)');
# Check the rights settings for a particular $particularizationName.
sub rightOnParticularization {
	my ($part_name) = @_;
	
	my $has_part_rights = 0;

	if (right("particularization")) {
		
		foreach my $right ( @{ right("particularization") } ) {
			if ( lc $right eq lc $part_name ) {
				$has_part_rights = 1;
			}
		}
	} else {
		$has_part_rights = 1;
	}
	
	return $has_part_rights;
}

# setUserAction(action => 'add category', comment => "added category with name 'foo'")
# Add a record to the user action log (table `user_action`).
sub setUserAction {
	my %arg = @_;

	$arg{username} ||= sessionGet('userid');

	# When we don't know which of this script's entitlements to log it under, pick a random one.
	$arg{entitlement} ||= _scriptEntitlements()->[0];

	my ( $stmnt, @bind ) = Sql->insert( 'user_action', \%arg );
	my $sth = Database->prepare($stmnt);
	my $res = Database->executeWithBinds(@bind);
}

# From the entitlements config, get the entitlements belonging to the scriptname supplied in the request.
sub _scriptEntitlements {
	my $entitlementsConfig = Taranis::Config->new(Config->{entitlements});

	# Map current request to a scriptname to lookup in entitlements config. If the request doesn't have a 'pageName'
	# parameter, default to the special case 'index' (= the "frontpage", /taranis/).
	my $scriptName = currentRequest->{pageName} // 'index';

	my $scriptEntitlements = $entitlementsConfig->{entitlement}->{$scriptName}->{use_entitlement}
		|| die 404;

	# Value is either a string (one matching <use_entitlement> in the config) or an arrayref (multiple matching
	# <use_entitlement>s in the config). Force to an arrayref for consistency.
	unless (ref $scriptEntitlements eq 'ARRAY') {
		$scriptEntitlements = [$scriptEntitlements];
	}

	return $scriptEntitlements;
}

sub validCsrfHeaderSupplied {
	return sessionIsActive && CGI->http('X-Taranis-CSRF-Token') eq sessionCsrfToken;
}

1;
