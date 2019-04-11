/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view constituent role details
	$('#content').on( 'click', '.btn-edit-constituent-role, .btn-view-constituent-role', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_roles',
			action: 'openDialogConstituentRoleDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogConstituentRoleDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Constituent role details');
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
	
	// delete a constituent role
	$('#content').on( 'click', '.btn-delete-constituent-role', function () {
		if ( confirm('Are you sure you want to delete the constituent role?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_roles',
				action: 'deleteConstituentRole',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new constituent role
	$('#filters').on( 'click', '#btn-add-constituent-role', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_roles',
			action: 'openDialogNewConstituentRole',
			success: openDialogNewConstituentRoleCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new constituent role');
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


function openDialogNewConstituentRoleCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-constituent-roles[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#constituent-roles-description', context).val() == '' ) {
						alert("Please specify the role description.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_roles',
							action: 'saveNewConstituentRole',
							queryString: $('#form-constituent-roles[data-id="NEW"]').serializeWithSpaces(),
							success: saveConstituentRoleCallback
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
		
		$('#constituent-roles-description',context).focus();
	}
}

function openDialogConstituentRoleDetailsCallback ( params ) {
	var context = $('#form-constituent-roles[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#constituent-roles-description', context).val() == '' ) {
						alert("Please specify the role description.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_roles',
							action: 'saveConstituentRoleDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveConstituentRoleCallback
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

function saveConstituentRoleCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_roles',
			action: 'getConstituentRoleItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
