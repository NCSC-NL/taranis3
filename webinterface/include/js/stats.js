/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// search statistics
	$('#filters').on('click', '#btn-stats-search', function () {
		$.main.ajaxRequest({
			modName: 'statistics',
			pageName: 'stats',
			action: 'searchStats',
			queryString: $('#form-stats-search').serializeWithSpaces(),
			success: null
		});
		
		var pageTitle = 'All Statistics';
		
		if ( $('#stats-filters-type').val() != '' ) {
			var pattern = /statistics/i;
			pageTitle = ( pattern.test( $('#stats-filters-type').val() ) ) ? $('#stats-filters-type').val() : $('#stats-filters-type').val() + ' Statistics';
		}
		
		$('.page-title').text( pageTitle );
	});
});
