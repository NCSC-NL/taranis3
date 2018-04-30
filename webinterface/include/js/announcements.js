/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// add announcement
	$('#filters').on('click', '#btn-add-announcement', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'announcements',
			action: 'openDialogNewAnnouncement',
			queryString: 'tool=announcements',
			success: openDialogNewAnnouncementCallback
		});			
		
		dialog.dialog('option', 'title', 'New Announcement');
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
	
	// edit announcement
	$('#content').on('click', '.btn-edit-announcement, .btn-view-announcement', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'announcements',
			action: 'openDialogAnnouncementDetails',
			queryString: 'tool=announcements&id=' + $(this).attr('data-itemid'),
			success: openDialogAnnouncementCallback
		});			
		
		dialog.dialog('option', 'title', 'Edit Announcement');
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

	// delete announcement
	$('#content').on('click', '.btn-delete-announcement', function () {
		
		if ( confirm('Are you sure you want to delete the announcement?') ) {
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'announcements',
				action: 'deleteAnnouncement',
				queryString: 'tool=announcements&id=' + $(this).attr('data-itemid'),
				success: deleteAnnouncementCallback
			});
		}
	});
	
});

function openDialogNewAnnouncementCallback ( params ) {
	
	var context =  $('#form-announcement[data-announcementid="NEW"]');

	if ( params.writeRight == 1 ) {
	
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {
					var todoList = new Array(),
						queryString = $(context).serializeWithSpaces() + '&tool=announcements';
					
					if ( $('#announcement-type', context).val() == 'todo-list' ) {
						$('.announcement-todo-list-item', context).each( function (i) {
							if ( $(this).parent().hasClass('hidden') == false ) {
								var todo = new Object();
								todo.description = $(this).children(' .announcement-todo-list-item-description').val();
								todo.donestatus = $(this).children(' .announcement-todo-list-item-done-status').val();
								todo.comment = $(this).children(' .announcement-todo-list-item-comment').val();
								todoList.push( todo );
							}
							
						});
						if ( todoList.length > 0 ) {
							queryString += '&todolist=' + encodeURIComponent( JSON.stringify( todoList ) );
						}
					}

					$.main.ajaxRequest({
						modName: 'tools',
						pageName: 'announcements',
						action: 'saveNewAnnouncement',
						queryString: queryString,
						success: updateAnnouncementList
					});
				}
			},
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		setAnnouncementUIBehavior( context );
		$('#announcement-type', context).triggerHandler('change');
	} else {
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
	}
}

function openDialogAnnouncementCallback ( params ) {

	var context =  $('#form-announcement[data-announcementid="' + params.id + '"]');

	if ( params.writeRight == 1 ) {
	
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					var todoList = new Array(),
						queryString = $(context).serializeWithSpaces() + '&tool=announcements&id=' + params.id;
					
					if ( $('#announcement-type', context).val() == 'todo-list' ) {
						$('.announcement-todo-list-item', context).each( function (i) {
							if ( $(this).parent().hasClass('hidden') == false ) {
								var todo = new Object();
								todo.description = $(this).children(' .announcement-todo-list-item-description').val();
								todo.donestatus = $(this).children(' .announcement-todo-list-item-done-status').val();
								todo.comment = $(this).children(' .announcement-todo-list-item-comment').val();
								todoList.push( todo );
							}
						});
						if ( todoList.length > 0 ) {
							queryString += '&todolist=' + encodeURIComponent( JSON.stringify( todoList ) );
						}
					}

					$.main.ajaxRequest({
						modName: 'tools',
						pageName: 'announcements',
						action: 'saveAnnouncementDetails',
						queryString: queryString,
						success: updateAnnouncementList
					});
				}
			},
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		setAnnouncementUIBehavior( context );
		$('#announcement-type', context).triggerHandler('change');
	} else {
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
	}
}

function updateAnnouncementList ( params ) {
	
	if ( params.saveOk == 1 ) {
		if ( params.insertNew == 1 ) {
			$('#announcements-content-heading').after( params.itemHtml );
			$('#empty-row').remove();
			
		} else {
			$('#' + params.id).html( params.itemHtml )
		}
		$.main.activeDialog.dialog('close');
		
	} else {
		alert( params.message );
	}
}

function deleteAnnouncementCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		$('#' + params.id).remove();
	} else {
		alert( params.message );
	}
}

function setAnnouncementUIBehavior (context ) {
	
	// add new bullet-list item when pressing enter in input field
	$('input[name="announcement-bullet-list-item"]', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#announcement-bullet-list-add-item').trigger('click');
		}
	});
	
	// toggle input fields for different announcement types
	$('#announcement-type', context).change( function () {
		$('div[data-announcementtype]', context).hide();
		$('div[data-announcementtype="' + $(this).val() + '"]', context).show();
	});
	
	// remove bullet-list item
	$('.btn-delete-bullet-list-item, .btn-delete-todo-list-item', context).click( function () {
		$(this).parent().remove();
	});
	
	// add bullet list input elements
	$('#announcement-bullet-list-add-item, #announcement-todo-list-add-item', context).click( function () {
		var cloneBlock = $(this).siblings('.hidden'); 
		var clonedBlock = cloneBlock
			.clone(true,true)
			.insertBefore(cloneBlock)
			.removeClass('hidden');
		
		clonedBlock.children('input:first').focus();
	});

}
