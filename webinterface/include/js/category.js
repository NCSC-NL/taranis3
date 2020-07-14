/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view category details
	$('#content').on( 'click', '.btn-edit-category, .btn-view-category', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'category',
			action: 'openDialogCategoryDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogCategoryDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Category details');
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
	
	// delete a category
	$('#content').on( 'click', '.btn-delete-category', function () {
		if ( confirm('Are you sure you want to delete the category?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'category',
				action: 'deleteCategory',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new category
	$('#filters').on( 'click', '#btn-add-category', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'category',
			action: 'openDialogNewCategory',
			success: openDialogNewCategoryCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new category');
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


function openDialogNewCategoryCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-category[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#category-details-name', context).val() == '' ) {
						alert("Please specify a category name.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'category',
							action: 'saveNewCategory',
							queryString: $('#form-category[data-id="NEW"]').serializeWithSpaces(),
							success: saveCategoryCallback
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

function openDialogCategoryDetailsCallback ( params ) {
	var context = $('#form-category[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#category-details-name', context).val() == '' ) {
						alert("Please specify a category name.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'category',
							action: 'saveCategoryDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveCategoryCallback
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

function saveCategoryCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'category',
			action: 'getCategoryItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
