/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view constituent type details
	$('#content').on( 'click', '.btn-edit-constituent-type, .btn-view-constituent-type', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_types',
			action: 'openDialogConstituentTypeDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogConstituentTypeDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Constituent type details');
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
	
	// delete a constituent type
	$('#content').on( 'click', '.btn-delete-constituent-type', function () {
		if ( confirm('Are you sure you want to delete the constituent type?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_types',
				action: 'deleteConstituentType',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new constituent type
	$('#filters').on( 'click', '#btn-add-constituent-type', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_types',
			action: 'openDialogNewConstituentType',
			success: openDialogNewConstituentTypeCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new constituent type');
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
	
});


function openDialogNewConstituentTypeCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-constituent-types[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#constituent-types-description', context).val() == '' ) {
						alert("Please specify the type description.");
					} else {
						$('#constituent-types-selected-types option', context).each( function (i) {
							$(this).prop('selected', true);
						});

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_types',
							action: 'saveNewConstituentType',
							queryString: $('#form-constituent-types[data-id="NEW"]').serializeWithSpaces(),
							success: saveConstituentTypeCallback
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

function openDialogConstituentTypeDetailsCallback ( params ) {
	var context = $('#form-constituent-types[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		var selectedPublicationTypeIDs = new Array();
		$('#constituent-types-selected-types', context).each( function (i) {
			selectedPublicationTypeIDs.push( $(this).val() );
		});
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					// If the publication type selection has changed, a warning should be given
					var publicationTypeSelectionHasChanged = false;
					var newSelectedPublicationTypeIDs = new Array();

					$('#constituent-types-selected-types option', context).each( function (i) {
						if ( $.inArray( $(this).val(), selectedPublicationTypeIDs ) == -1 ) {
							publicationTypeSelectionHasChanged = true;
						}
						newSelectedPublicationTypeIDs.push( $(this).val() );
						$(this).prop('selected', true);
					});
					
					$.each( selectedPublicationTypeIDs, function (i, typeId) {
						if ( $.inArray( typeId, newSelectedPublicationTypeIDs ) == -1 ) {
							publicationTypeSelectionHasChanged = true;
						}
					});
					
					if ( $('#constituent-types-description', context).val() == '' ) {
						alert("Please specify the type description.");
					} else {
						
						if ( 
							!publicationTypeSelectionHasChanged
							|| ( publicationTypeSelectionHasChanged && confirm('Changing the Publication Type will have great impact on Constituent Individual settings. \n\nDo you wish to proceed?') )
						) {
						
							$('#constituent-types-selected-types', context).each( function (i) {
								$(this).prop('selected', true);
							});

							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'constituent_types',
								action: 'saveConstituentTypeDetails',
								queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
								success: saveConstituentTypeCallback
							});
						}						
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

function saveConstituentTypeCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}			
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_types',
			action: 'getConstituentTypeItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
