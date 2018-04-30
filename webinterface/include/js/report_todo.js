/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view todo details
	$('#content').on( 'click', '.btn-edit-report-todo, .btn-view-report-todo', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'todo',
			action: 'openDialogToDoDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: function ( params ) {
				var context = $('#form-report-todo[data-id="' + params.id + '"]');
				
				if ( params.writeRight == 1 ) {
				
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
			
								if ( $.trim( $('#report-todo-description', context).val() ) == '' ) {
									alert("Please specify a description.");
								} else if ( validateForm(['report-todo-due-date']) ) {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'todo',
										action: 'saveToDoDetails',
										queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
										success: saveToDoCallback
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
		
		dialog.dialog('option', 'title', 'To-do details');
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
	
	// delete a to-do
	$('#content').on( 'click', '.btn-delete-report-todo', function () {
		if ( confirm('Are you sure you want to delete the to-do?') ) { 
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'todo',
				action: 'deleteToDo',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteReportItemCallback
			});
		}
	});
	
	// add a new to-do
	$(document).on( 'click', '#btn-add-report-todo, #add-report-todo-link', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'todo',
			action: 'openDialogNewToDo',
			success: function ( params ) {
				if ( params.writeRight == 1 ) { 
					var context = $('#form-report-todo[data-id="NEW"]');
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
			
								if ( $.trim( $('#report-todo-description', context).val() ) == '' ) {
									alert("Please specify a description.");
								} else if ( validateForm(['report-todo-due-date']) ) {
									$.main.ajaxRequest({
										modName: 'report',
										pageName: 'todo',
										action: 'saveNewToDo',
										queryString: $('#form-report-todo[data-id="NEW"]').serializeWithSpaces(),
										success: saveToDoCallback
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
		
		dialog.dialog('option', 'title', 'Add new to-do');
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
	
	// search to-dos
	$('#filters').on('click', '#btn-report-todo-search', function () {
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'todo',
			action: 'searchToDo',
			queryString: $('#form-report-todo-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do to-do search on ENTER
	$('#filters').on('keypress', '#report-todo-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-report-todo-search').trigger('click');
		}
	});
});

function saveToDoCallback ( params ) {
	if ( params.saveOk ) {
		if ( $('#report-todo-content-heading').length > 0 ) {
			var queryString = 'id=' + params.id;
			
			if ( params.insertNew == 1 ) {
				queryString += '&insertNew=1';
			}		
			
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'todo',
				action: 'getToDoItemHtml',
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
