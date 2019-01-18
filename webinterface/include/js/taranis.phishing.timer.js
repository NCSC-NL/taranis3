/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	$.main.phishingTimer = $.timer( function () {
		if ( $('#phishing-add-url').length > 0 ) {
			$.main.ajaxRequest({
					modName: 'tools',
					pageName: 'phishing_overview',
					action: 'displayPhishingOverview',
					queryString: 'tool=phishing_checker',
					success: function (params) {
						$('#btn-phishing-autorefresh').val('Turn Autorefresh OFF');
					},
					isAutoRefresh: true
			}, true);
		} else {
			stopPhishingTimer();
		}
	}, 5000 ); // 60000 ms = 1 minute
});

function startPhishingTimer () {
	$('#btn-phishing-autorefresh').val('Turn Autorefresh OFF');
	if ( !$.main.phishingTimer.isActive ) {
		$.main.phishingTimer.play(true);
	}
}

function stopPhishingTimer () {
	$('#btn-phishing-autorefresh').val('Turn Autorefresh ON');
	$.main.phishingTimer.stop();
}
