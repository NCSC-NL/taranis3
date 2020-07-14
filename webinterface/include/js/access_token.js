/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
*/

$( function () {
	
	// edit/view token details
	$('#content').on( 'click', '.btn-edit-token, .btn-view-token', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'access_token',
			action: 'openDialogTokenDetails',
			queryString: 'token=' + $(this).attr('data-token'),
			success: openDialogTokenDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Token details');
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
	
	// delete a token
	$('#content').on( 'click', '.btn-delete-token', function () {
		if ( confirm('Are you sure you want to delete the access token?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'access_token',
				action: 'deleteToken',
				queryString: 'token=' + $(this).attr('data-token'),
				success: deleteConfigurationItemCallback
			});
		}
	});
	
	// add a new token
	$('#filters').on( 'click', '#btn-add-token', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'access_token',
			action: 'openDialogNewToken',
			success: openDialogNewTokenCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new token');
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
	
	// refresh token list
	$('#filters').on( 'click', '#btn-refresh-token-list', function () {
		$('#super-secret-link')
			.attr('href', 'configuration/access_token/displayTokens/')
			.trigger('click');
		$('#super-secret-link').attr('href', '');
	});
	
});


function openDialogNewTokenCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-access-token[data-token="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#access-token-details-user', context).val() == '' ) {
						alert("Please select a username.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'access_token',
							action: 'saveNewToken',
							queryString: $('#form-access-token[data-token="NEW"]').serializeWithSpaces(),
							success: saveTokenCallback
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

function openDialogTokenDetailsCallback ( params ) {
	var context = $('#form-access-token[data-token="' + params.token + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $('#access-token-details-user', context).val() == '' ) {
						alert("Please select a user.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'access_token',
							action: 'saveTokenDetails',
							queryString: $(context).serializeWithSpaces() + '&token=' + params.token,
							success: saveTokenCallback
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

function saveTokenCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'token=' + params.token;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'access_token',
			action: 'getTokenItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
