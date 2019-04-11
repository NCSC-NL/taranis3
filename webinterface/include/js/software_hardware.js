/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view software/hardware details
	$('#content').on( 'click', '.btn-edit-software-hardware, .btn-view-software-hardware', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'software_hardware',
			action: 'openDialogSoftwareHardwareDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogSoftwareHardwareDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Software/Hardware details');
		dialog.dialog('option', 'width', '850px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a software/hardware
	$('#content').on( 'click', '.btn-delete-software-hardware', function () {
		
		var confirmText = ( $(this).attr('data-inuse') > 0 ) ? 'This product is in use by one or more constituents, are you sure you want to delete this product?' : 'Are you sure you want to delete software/hardware?'; 
		
		if ( confirm(confirmText) ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'software_hardware',
				action: 'deleteSoftwareHardware',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new software/hardware
	$('#filters').on( 'click', '#btn-add-software-hardware', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'software_hardware',
			action: 'openDialogNewSoftwareHardware',
			success: openDialogNewSoftwareHardwareCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new software/hardware');
		dialog.dialog('option', 'width', '850px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// search software/hardware
	$('#filters').on('click', '#btn-software-hardware-search', function (event, origin) {
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'software_hardware',
			action: 'searchSoftwareHardware',
			queryString: $('#form-software-hardware-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do software/hardware search on ENTER
	$('#filters').on('keypress', '#software-hardware-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-software-hardware-search').trigger('click', 'searchOnEnter');
		}
	});

});

function openDialogNewSoftwareHardwareCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#software-hardware-details-form[data-id="NEW"]');

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#software-hardware-details-producer", context).val() == "") {
						alert("Please specify Producer.");	
					} else if ( $("#software-hardware-details-name", context).val() == "") {
						alert("Please specify Name.");
					} else if (  $('input[name="monitored"]:checked', context).length == 0 ) {
						alert("Please specify monitored.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'software_hardware',
							action: 'saveNewSoftwareHardware',
							queryString: $(context).serializeWithSpaces(),
							success: saveSoftwareHardwareCallback
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
		
		$('#software-hardware-details-tabs', context).newTabs();
	}
}

function openDialogSoftwareHardwareDetailsCallback ( params ) {
	var context = $('#software-hardware-details-form[data-id="' + params.id + '"]');
	$('#software-hardware-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) { 

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#software-hardware-details-producer", context).val() == "") {
						alert("Please specify Producer.");	
					} else if ( $("#software-hardware-details-name", context).val() == "") {
						alert("Please specify Name.");
					} else if (  $('input[name="monitored"]:checked', context).length == 0 ) {
						alert("Please specify monitored.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'software_hardware',
							action: 'saveSoftwareHardwareDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveSoftwareHardwareCallback
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

function saveSoftwareHardwareCallback ( params ) {
	
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'software_hardware',
			action: 'getSoftwareHardwareItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
