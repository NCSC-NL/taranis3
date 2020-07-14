/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view damage description details
	$('#content').on( 'click', '.btn-edit-damage-description, .btn-view-damage-description', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'damage_description',
			action: 'openDialogDamageDescriptionDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogDamageDescriptionDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Damage description details');
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
	
	// delete a damage description
	$('#content').on( 'click', '.btn-delete-damage-description', function () {
		if ( confirm('Are you sure you want to delete the damage description?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'damage_description',
				action: 'deleteDamageDescription',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new damage desciption
	$('#filters').on( 'click', '#btn-add-damage-description', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'damage_description',
			action: 'openDialogNewDamageDescription',
			success: openDialogNewDamageDescriptionCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new damage description');
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


function openDialogNewDamageDescriptionCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-damage-description[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#damage-description-description', context).val() == '' ) {
						alert("Please specify the damage description.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'damage_description',
							action: 'saveNewDamageDescription',
							queryString: $('#form-damage-description[data-id="NEW"]').serializeWithSpaces(),
							success: saveDamageDescriptionCallback
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

function openDialogDamageDescriptionDetailsCallback ( params ) {
	var context = $('#form-damage-description[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#damage-description-description', context).val() == '' ) {
						alert("Please specify the damage description.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'damage_description',
							action: 'saveDamageDescriptionDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveDamageDescriptionCallback
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

function saveDamageDescriptionCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'damage_description',
			action: 'getDamageDescriptionItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
