# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

var page = require('webpage').create(),
	system = require('system');

if ( system.args.length > 1 ) {
	var address = system.args[1],
		settings = system.args[2],
		errorLogging = '';

	if ( typeof settings !== 'undefined' ) {
		page.settings = JSON.parse( settings );
	}

	page.viewportSize = { width: 1024, height: 768 };

	page.onResourceRequested = function(requestData, networkRequest) {
		errorLogging += 'Request (#' + requestData.id + '): ' + JSON.stringify(requestData) + '\n';
	};

	page.onResourceError = function (resourceError) {
		errorLogging += 'Unable to load resource (URL:' + resourceError.url + ')\n';
		errorLogging += 'Error code: ' + resourceError.errorCode + '. Description: ' + resourceError.errorString + '\n';
	}

	page.onUrlChanged = function(targetUrl) {
		errorLogging += 'New URL: ' + targetUrl + '\n';
	};

	page.onNavigationRequested = function(url, type, willNavigate, main) {
		errorLogging += 'Trying to navigate to: ' + url + '\n';
	};

	page.onError = function(msg, trace) {
		var msgStack = ['ERROR: ' + msg];
		if (trace && trace.length) {
			msgStack.push('TRACE:');
			trace.forEach(function(t) {
				msgStack.push(' -> ' + t.file + ': ' + t.line + (t.function ? ' (in function "' + t.function + '")' : ''));
			});
		}
		errorLogging += msgStack.join('\n') + '\n';
	};

	page.open(address, function () {
		page.evaluate(function() {
  			document.body.bgColor = 'white';
		});

		if ( status == 'fail' ) {
			console.log(errorLogging)
		} else {
			page.render("/dev/stdout", {format: "jpg", quality: 80} );
		}
		phantom.exit();
	});
} else {
	console.log('OUCH!');
	phantom.exit();
}
