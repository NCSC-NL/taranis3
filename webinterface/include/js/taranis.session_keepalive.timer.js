/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

// taranis.session_keepalive.timer.js: make regular session_keepalive requests to the server iff the user is active
// (typing / clicking / etc).

$(function() {
	"use strict";

	var requestTimeout = 20000; // Not too low; don't want to have the session expire because of a bad connection.
	var requestInterval = 1000; // Not too high, so the user won't be typing for ages without knowing his session died.

	var lastUserActivityTime = Date.now();
	var lastKeepaliveTime = 0;
	var requestIsInProgress = false;


	function maybeSendKeepalive() {
		if (requestIsInProgress) return;
		if (lastUserActivityTime < lastKeepaliveTime) return;

		requestIsInProgress = true;

		var keepaliveStartTime = Date.now();

		$.ajax({
			url: $.main.scriptroot + '/session_keepalive',
			method: 'POST',
			headers: {
				'X-Taranis-CSRF-Token': $.main.csrfToken,
			},
			timeout: requestTimeout
		}).always(function() {
			requestIsInProgress = false;
		}).done(function() {
			lastKeepaliveTime = keepaliveStartTime;
		}).fail(function() {
			$.main.gotoLoginIfSessionDead();
		});
	}

	setInterval(maybeSendKeepalive, requestInterval);

	// Watch for an arbitrary collection of events that should cover "user activity" pretty well.
	$(document).on("mousedown mousemove keydown click dblclick", null, null, function(e) {
		// Ignore fake events triggered by jQuery.trigger() and friends.
		if (e.isTrigger) return;

		lastUserActivityTime = Date.now();

		if (lastKeepaliveTime > lastUserActivityTime) {
			// lastKeepaliveTime is in the future, which means the system clock changed significantly (e.g. because
			// daylight saving time just ended). Reset it.
			lastKeepaliveTime = 0;
		}
	});
});
