/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view collector details
	$('#content').on( 'click', '.btn-edit-collector, .btn-view-collector', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'collector',
			action: 'openDialogCollectorDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogCollectorDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Collector details');
		dialog.dialog('option', 'width', '500px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');		
	});
	
	// delete a collector
	$('#content').on( 'click', '.btn-delete-collector', function () {
		if ( confirm('Are you sure you want to delete the collector?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'collector',
				action: 'deleteCollector',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new collector
	$('#filters').on( 'click', '#btn-add-collector', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'collector',
			action: 'openDialogNewCollector',
			success: openDialogNewCollectorCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new collector');
		dialog.dialog('option', 'width', '500px');
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


function openDialogNewCollectorCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-collector[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#collector-description', context).val() == '' ) {
						alert("Please specify the collector.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'collector',
							action: 'saveNewCollector',
							queryString: $('#form-collector[data-id="NEW"]').serializeWithSpaces(),
							success: saveCollectorCallback
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

function openDialogCollectorDetailsCallback ( params ) {
	var context = $('#form-collector[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#collector-description', context).val() == '' ) {
						alert("Please specify the collector description.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'collector',
							action: 'saveCollectorDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveCollectorCallback
						});
					}
				}
			},
			{
				text: 'Reset secret',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'collector',
						action: 'resetCollectorSecret',
						queryString: 'id=' + params.id,
						success: function (resetParams) {
							$('#collector-secret', context).text( resetParams.secret );
						}
					});
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

function saveCollectorCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
			alert('collector secret = ' + params.secret);
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'collector',
			action: 'getCollectorItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
