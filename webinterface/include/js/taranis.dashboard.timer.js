/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// timer for refreshing dashboard data
	$.main.dashboardTimer = $.timer( function () {
		$.main.ajaxRequest({
				modName: 'dashboard',
				pageName: 'dashboard',
				action: 'getMinifiedDashboardData',
				success: function () {
					if ( $('mousetrap').length > 0 ) {
						$('#icon-keyboard-shortcuts').show();
					}
				},
				isAutoRefresh: true
		}, true);
		
		if ( $('.dashboard-block:visible').length > 0 ) {
			$.main.ajaxRequest({
				modName: 'dashboard',
				pageName: 'dashboard',
				action: 'getDashboardData',
				success: 'getDashboardDataCallback',
				isAutoRefresh: true
			}, true);
		}
	}, 60000 ); // 60000 ms = 1 minute
	
	$.main.dashboardTimer.play(true);
});
