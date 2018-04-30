/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// view collector logging
	$('#content').on( 'click', '.btn-view-collector-logging', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'logging',
			pageName: 'module_collect',
			action: 'openDialogCollectorLoggingDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: openDialogCollectorLoggingDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Collector logging details');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a collector log
	$('#content').on( 'click', '.btn-delete-collector-logging', function () {
		if ( confirm('Are you sure you want to delete the log entry?') ) { 
			$.main.ajaxRequest({
				modName: 'logging',
				pageName: 'module_collect',
				action: 'deleteCollectorLogging',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});
		}
	});
	
	// delete all logs (where all logs are the ones shown as search results)
	$('#filters').on('click', '#btn-delete-bulk-collector-logging', function () {
		var errorCode = $('#collector-logging-filters-error-code').val(); 
		if ( confirm('Are you sure you want to delete all with the selected errorcode logs?') ) {
			$.main.ajaxRequest({
				modName: 'logging',
				pageName: 'module_collect',
				action: 'bulkDeleteCollectorLogging',
				queryString: 'errorCode=' + errorCode,
				success: bulkDeleteCollectorLoggingCallback
			});
		}
	});
	
	// search collector logs
	$('#filters').on('click', '#btn-collector-logging-search', function (event, origin) {

		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}

		$.main.ajaxRequest({
			modName: 'logging',
			pageName: 'module_collect',
			action: 'searchCollectorLogging',
			queryString: $('#form-collector-logging-search').serializeWithSpaces(),
			success: null
		});
	});
	
});


function openDialogCollectorLoggingDetailsCallback ( params ) {
	var context = $('#collector-logging-details-form[data-id="' + params.id + '"]');
	$('#collector-logging-details-tabs', context).newTabs();
	
	$('input[type="text"]', context).keypress( function (event) {
		return checkEnter(event);
	});	
		
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}
	]);
				
}
function bulkDeleteCollectorLoggingCallback ( params ) {
	if (params.deleteOk == 1) {
		$('#content .item-row').remove();
	} else {
		alert(params.message);
	}
}
