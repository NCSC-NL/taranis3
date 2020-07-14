/*
 * This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

var page = require('webpage').create(),
	system = require('system');

if ( system.args.length > 1 ) {
	var content = system.args[1],
		settings = system.args[2],
		headerText = system.args[3],
		errorLogging = '';

	if ( typeof settings !== 'undefined' ) {
		page.settings = JSON.parse( settings );
	}

	page.paperSize = { 
			format: 'A4', 
			orientation: 'portrait', 
			border: '0cm',
			header: {
				height: "1.2cm",
				contents: phantom.callback(function(pageNum, numPages) {
//					if (pageNum == 1) {
//						return '';
//					}
					return '<div style="width:100%; text-align: center;"><div style="height:1cm; width:44px; background-color:#094D96;display: inline-block"></div><div style="display:inline-block; float:right; width:20px">&nbsp;</div></div>';
				})
			},
			footer: {
				height: "1cm",
				contents: phantom.callback(function(pageNum, numPages) {
					return '<div style="width:100%; text-align: center;"><div style="height:1cm; width:44px; background-color:#094D96;display: inline-block"></div><div style="display:inline-block; float:right; width:20px">' + pageNum + '</div></div>';
				})
			}
	};
	
	page.content = content;

	window.setTimeout(function () {
		console.log( page.render("/dev/stdout", { format: "pdf" }) );
		phantom.exit();
	}, 2000);

} else {
	console.log('OUCH!');
	phantom.exit();
}
