/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view incident log entry details
	$('#content').on( 'click', '.btn-edit-report-incident-log, .btn-view-report-incident-log', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'incident_log',
			action: 'openDialogIncidentLogDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: function ( params ) {
				var context = $('#form-report-incident-log[data-id="' + params.id + '"]');

				if ( params.writeRight == 1 ) {
				
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								if ( $.trim( $('#report-incident-log-description', context).val() ) == '' ) {
									alert("Please specify a description.");
								} else if ( $('#report-incident-log-ticket-number', context).val() == '' ) {
									alert("Please specify a ticket number.");
								} else if ( $('#report-incident-log-status', context).val() == '' ) {
									alert("Please specify a status.");
								} else if ( $('#report-incident-log-owner', context).val() == '' ) {
									alert("Please select an owner.");
								} else {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'incident_log',
										action: 'saveIncidentLogDetails',
										queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
										success: saveIncidentLogCallback
									});
								}
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);
					
					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
					
				} else {
					$('input, select, textarea', context).each( function (index) {
						$(this).prop('disabled', true);
					});
				}				
			}
		});
		
		dialog.dialog('option', 'title', 'Incident log entry details');
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
	
	// delete a incident log entry
	$('#content').on( 'click', '.btn-delete-report-incident-log', function () {
		if ( confirm('Are you sure you want to delete the incident log entry?') ) {
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'incident_log',
				action: 'deleteIncidentLog',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteReportItemCallback
			});
		}
	});
	
	// add a new incident log entry
	$(document).on( 'click', '#btn-add-report-incident-log, #add-report-incident-log-link', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'incident_log',
			action: 'openDialogNewIncidentLog',
			success: function ( params ) {
				if ( params.writeRight == 1 ) { 
					var context = $('#form-report-incident-log[data-id="NEW"]');
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								if ( $.trim( $('#report-incident-log-description', context).val() ) == '' ) {
									alert("Please specify a description.");
								} else if ( $('#report-incident-log-ticket-number', context).val() == '' ) {
									alert("Please specify a ticket number.");
								} else if ( $('#report-incident-log-status', context).val() == '' ) {
									alert("Please specify a status.");
								} else if ( $('#report-incident-log-owner', context).val() == '' ) {
									alert("Please select an owner.");
								} else {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'incident_log',
										action: 'saveNewIncidentLog',
										queryString: $('#form-report-incident-log[data-id="NEW"]').serializeWithSpaces(),
										success: saveIncidentLogCallback
									});
								}
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);
					
					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Add new incident log entry');
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

	// search log entries
	$('#filters').on('click', '#btn-report-incident-log-search', function () {
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'incident_log',
			action: 'searchIncidentLog',
			queryString: $('#form-report-incident-log-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do log entries search on ENTER
	$('#filters').on('keypress', '#report-incident-log-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-report-incident-log-search').trigger('click');
		}
	});
});

function saveIncidentLogCallback ( params ) {
	if ( params.saveOk ) {
		if ( $('#report-todo-content-heading').length > 0 ) {
			var queryString = 'id=' + params.id;
			
			if ( params.insertNew == 1 ) {
				queryString += '&insertNew=1';
			}		
			
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'incident_log',
				action: 'getIncidentLogItemHtml',
				queryString: queryString,
				success: getReportItemHtmlCallback
			});
			
			$.main.activeDialog.dialog('close');
		} else {
			$.main.activeDialog.dialog('close');

			var e = jQuery.Event("keydown");
			e.which = 116;
			$(document).trigger(e);
		}
	} else {
		alert(params.message)
	}
}
