/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view contact log details
	$('#content').on( 'click', '.btn-edit-report-contact-log, .btn-view-report-contact-log', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'contact_log',
			action: 'openDialogContactLogDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: function ( params ) {
				var context = $('#form-report-contact-log[data-id="' + params.id + '"]');
				
				if ( params.writeRight == 1 ) {
				
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								if ( $.trim( $('#report-contact-log-contact-details', context).val() ) == '' ) {
									alert("Please specify contact details.");
								} else if ( $('#report-contact-log-type', context).val() == '' ) {
									alert("Please specify a type.");
								} else {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'contact_log',
										action: 'saveContactLogDetails',
										queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
										success: saveContactLogCallback
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
		
		dialog.dialog('option', 'title', 'Contact log details');
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
	
	// delete a contact log entry
	$('#content').on( 'click', '.btn-delete-report-contact-log', function () {
		if ( confirm('Are you sure you want to delete the contact log entry?') ) {
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'contact_log',
				action: 'deleteContactLog',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteReportItemCallback
			});
		}
	});
	
	// add a new contact log entry
	$(document).on( 'click', '#btn-add-report-contact-log, #add-report-contact-log-link', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'contact_log',
			action: 'openDialogNewContactLog',
			success: function ( params ) {
				if ( params.writeRight == 1 ) {
					var context = $('#form-report-contact-log[data-id="NEW"]');
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
			
								if ( $.trim( $('#report-contact-log-contact-details', context).val() ) == '' ) {
									alert("Please specify contact details.");
								} else if ( $('#report-contact-log-type', context).val() == '' ) {
									alert("Please specify a type.");
								} else {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'contact_log',
										action: 'saveNewContactLog',
										queryString: $('#form-report-contact-log[data-id="NEW"]').serializeWithSpaces(),
										success: saveContactLogCallback
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
		
		dialog.dialog('option', 'title', 'Add new contact log entry');
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
	$('#filters').on('click', '#btn-report-contact-log-search', function () {
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'contact_log',
			action: 'searchContactLog',
			queryString: $('#form-report-contact-log-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do log entries search on ENTER
	$('#filters').on('keypress', '#report-contact-log-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-report-contact-log-search').trigger('click');
		}
	});
});

function saveContactLogCallback ( params ) {
	if ( params.saveOk ) {
		if ( $('#report-contact-log-content-heading').length > 0 ) {
			var queryString = 'id=' + params.id;
			
			if ( params.insertNew == 1 ) {
				queryString += '&insertNew=1';
			}		
			
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'contact_log',
				action: 'getContactLogItemHtml',
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
		alert(params.message);
	}
}
