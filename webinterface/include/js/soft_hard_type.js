/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view type details
	$('#content').on( 'click', '.btn-edit-software-hardware-type, .btn-view-software-hardware-type', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'soft_hard_type',
			action: 'openDialogSoftwareHardwareTypeDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogSoftwareHardwareTypeDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Software/Hardware type details');
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
	
	// delete a type
	$('#content').on( 'click', '.btn-delete-software-hardware-type', function () {
		if ( confirm('Are you sure you want to delete the software/hardware type?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'soft_hard_type',
				action: 'deleteSoftwareHardwareType',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new software/hardware type
	$('#filters').on( 'click', '#btn-add-software-hardware-type', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'soft_hard_type',
			action: 'openDialogNewSoftwareHardwareType',
			success: openDialogNewSoftwareHardwareTypeCallback
		});
		
		dialog.dialog('option', 'title', 'Add new Software/Hardware type');
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


function openDialogNewSoftwareHardwareTypeCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-software-hardware-type[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#software-hardware-type-description', context).val() == '' ) {
						alert("Please specify the type description.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'soft_hard_type',
							action: 'saveNewSoftwareHardwareType',
							queryString: $(context).serializeWithSpaces(),
							success: saveSoftwareHardwareTypeCallback
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
		
		$('#software-hardware-type-description',context).focus();
	}
}

function openDialogSoftwareHardwareTypeDetailsCallback ( params ) {
	var context = $('#form-software-hardware-type[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#software-hardware-type-description', context).val() == '' ) {
						alert("Please specify the type description.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'soft_hard_type',
							action: 'saveSoftwareHardwareTypeDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveSoftwareHardwareTypeCallback
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

function saveSoftwareHardwareTypeCallback ( params ) {
	
	if ( params.saveOk ) {
	
		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'soft_hard_type',
			action: 'getSoftwareHardwareTypeItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
