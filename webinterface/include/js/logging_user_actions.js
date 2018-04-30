/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// search collector logs
	$('#filters').on('click', '#btn-user-actions-search', function (event, origin) {

		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		if ( validateForm(['user-actions-filters-start-date', 'user-actions-filters-end-date']) ) {
			$.main.ajaxRequest({
				modName: 'logging',
				pageName: 'user_actions',
				action: 'searchUserActions',
				queryString: $('#form-user-actions-search').serializeWithSpaces(),
				success: null
			});
		}
	});
	
	// do user actions search on ENTER
	$('#filters').on('keypress', '#user-actions-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-user-actions-search').trigger('click');
		}
	});
});
