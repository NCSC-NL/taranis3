/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view wordlist details
	$('#content').on( 'click', '.btn-edit-wordlist, .btn-view-wordlist', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'wordlist',
			action: 'openDialogWordlistDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: openDialogWordlistDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Wordlist details');
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
	
	// delete a wordlist
	$('#content').on( 'click', '.btn-delete-wordlist', function () {
		if ( confirm('Are you sure you want to delete the wordlist?') ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'wordlist',
				action: 'deleteWordlist',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});
		}
	});
	
	// add a new wordlist
	$('#filters').on( 'click', '#btn-add-wordlist', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'wordlist',
			action: 'openDialogNewWordlist',
			success: openDialogNewWordlistCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new wordlist');
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
	
	$('#filters').on('click', '#btn-wordlist-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'wordlist',
			action: 'searchWordlist',
			queryString: $('#form-wordlist-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do wordlist search on ENTER
	$('#filters').on('keypress', '#wordlist-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-wordlist-search').trigger('click');
		}
	});
});


function openDialogNewWordlistCallback ( params ) {
	if ( params.writeRight == 1 ) {
		var context = $('#form-wordlist[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#wordlist-details-description', context).val() == '' ) {
						alert("Please specify a description.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'wordlist',
							action: 'saveNewWordlist',
							queryString: $('#form-wordlist[data-id="NEW"]').serializeWithSpaces(),
							success: saveWordlistCallback
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

function openDialogWordlistDetailsCallback ( params ) {
	var context = $('#form-wordlist[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
	
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#wordlist-details-description', context).val() == '' ) {
						alert("Please specify a description.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'wordlist',
							action: 'saveWordlistDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveWordlistCallback
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

function saveWordlistCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'wordlist',
			action: 'getWordlistItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
