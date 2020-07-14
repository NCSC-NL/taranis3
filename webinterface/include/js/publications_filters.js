/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// search publications
	$('#filters').on('click', '#btn-publications-search', function (event, origin) {
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		
		if ( $("input:checkbox:checked[name='status']").length > 0 ) {

			if ( validateForm(['publications-start-date', 'publications-end-date'])  ) {
				
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'publications',
					action: 'searchPublications',
					queryString: $('#form-publications-search').serializeWithSpaces(),
					success: searchPublicationsCallback
				});
			}
		} else {
			alert("At least one of the status options must be checked to perform search.");
		}
	});
	
	// pressing enter in searchfield of filters section will trigger clicking the search button
	$('#filters').on( 'keypress', '#publications-search', function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-publications-search').trigger('click', 'searchOnEnter');
		}
	});
	
	// open dialog to create a new publication
	$('#filters').on('click', '.btn-publications-new', function () {
		var pubType = $(this).attr('data-pubtype');
		var action = 'openDialogNew' + pubType.charAt(0).toUpperCase() + pubType.slice(1);
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'write',
			pageName: pubType,
			action: action,
			success: action + 'Callback'
		});		
		
		dialog.dialog('option', 'title', 'Create new publication');
		dialog.dialog('option', 'width', '840px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
});

function searchPublicationsCallback ( params ) {
	switch ( params.publicationType ) {
		case 'advisory':
			getTagsForAdvisoryPage();
			break;
		case 'forward':
			getTagsForForwardPage();
			break;
		case 'eod':
			getTagsForEndOfDayPage();
			break;
		case 'eos':
			getTagsForEndOfShiftPage();
			break;
		case 'eow':
			getTagsForEndOfWeekPage();
			break;
	}
}
