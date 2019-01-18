/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	$('#filters').on('click', '#btn-whois-search', function () {
		
		if ( $('#whois-host-search').val().match( /^([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])$/ ) ) {

			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'whois',
				action: 'doWhoisLookup',
				queryString: 'tool=whois&whois=' + $('#whois-host-search').val(),
				success: null
			});

		} else {
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'whois',
				action: 'getWhoisHost',
				queryString: 'tool=whois&whois=' + $('#whois-host-search').val(),
				success: null
			});
		}
	});

	$('#filters').on( 'keypress', '#whois-host-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-whois-search').trigger( 'click' );
		}
	});	
	
});
