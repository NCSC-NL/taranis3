#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis qw(:all);
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Dashboard;
use Taranis::Template;
use Taranis::Session qw(sessionGet);
use Taranis::Users qw(getUserRights);
use JSON;
use strict;

my @EXPORT_OK = qw( getDashboardData getMinifiedDashboardData );

sub dashboard_export {
	return @EXPORT_OK;
}

sub getMinifiedDashboardData {
	my ( %kvArgs ) = @_;
	
	my $dab = Taranis::Dashboard->new( Config );

	my $dashboardHtml = $dab->getDashboard( $dab->{minified} );
	my $db     = $dab->{dbh}{simple};

	my %unread = $db->query(<<'__COUNT_UNREAD')->map;
 SELECT category, COUNT(category) AS unread
   FROM item
  WHERE status = 0
  GROUP BY category
__COUNT_UNREAD

	$unread{$_} += 0
		for $db->query('SELECT id FROM category')->flat;

	return {
		mini_dashboard => $dashboardHtml,
		unread_counts  => \%unread,
	}
}

sub getDashboardData {
	my ( %kvArgs ) = @_;

	my $dab = Taranis::Dashboard->new( Config );
	my $tt = Taranis::Template->new;

	my $dashboardData = $dab->getDashboard( $dab->{maximized} );

	my $is_admin = getUserRights(
			entitlement => "admin_generic",
			username => sessionGet('userid') 
		)->{admin_generic}->{write_right};

	my $dashboardHtml = $tt->processTemplate( \$dashboardData->{html}, { is_admin => $is_admin }, 1 );
	logErrorToSyslog( $tt->{errmsg} ) if ( $tt->{errmsg} );
	my $htmlFilters = $tt->processTemplate('dashboard_filters.tt', undef, 1);

	return {
		content => $dashboardHtml,
		filters => $htmlFilters,
		params => {
			dashboard => from_json( $dashboardData->{json} || '{}' )
		}
	};
}

1;
