/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view user details
	$('#content').on( 'click', '.btn-edit-user, .btn-view-user', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'users',
			action: 'openDialogUserDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogUserDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'User details');
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
	
	// delete a user
	$('#content').on( 'click', '.btn-delete-user', function () {
		if ( confirm('Are you sure you want to delete the user?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'users',
				action: 'deleteUser',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new user
	$('#filters').on( 'click', '#btn-add-user', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'users',
			action: 'openDialogNewUser',
			success: openDialogNewUserCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new user');
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

	// search user
	$('#filters').on('click', '#btn-users-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'users',
			action: 'searchUsers',
			queryString: $('#form-users-search').serializeWithSpaces(),
			success: null
		});
	});

	// do constituent individual search on ENTER
	$('#filters').on('keypress', '#users-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-users-search').trigger('click');
		}
	});
});

function _setup_password_again() {
	$('.double-password-first, .double-password-second').keyup( function (){
		var first  = $('.double-password-first').val();
		var second = $('.double-password-second').val();
		if(first == second) {
			$('#double-passwords-differ').hide();
			$('#btn-user-details-change-password').prop('disabled', false);
		} else {
			$('#double-passwords-differ').show();
			$('#btn-user-details-change-password').prop('disabled', true);
		}
	});
};

function openDialogNewUserCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#users-details-form[data-id="NEW"]');

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#users-details-username").val() == "" ) {
						alert("Please specify a username.");	
					} else if ( $("#users-details-password").val() == "") {
						alert("Password is required.");
					} else if ( $("#users-details-password").val() !=
					            $("#users-details-password2").val()) {
						alert("The password fields do not match.");
					} else if ( $("#uses-details-fullname").val() == "") {
						alert("Please specify a full name.");
					} else if ( $("#users-details-mail-from-email").val() == "") {
						alert("Please specify an email address.");
					} else if ( $("#users-details-mail-from-sender").val() == "") {
						alert("Please specify an email name.");
					}  else {
						$('#users-details-membership-roles option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'users',
							action: 'saveNewUser',
							queryString: $(context).serializeWithSpaces(),
							success: saveUserCallback
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
		
		$('#users-details-tabs', context).newTabs();
		
		_setup_password_again();
	}
}

function openDialogUserDetailsCallback ( params ) {
	var context = $('#users-details-form[data-id="' + params.id + '"]');
	$('#users-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) { 

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("uses-details-fullname").val() == "") {
						alert("Please specify a Full Name.");
					} else if ( $("users-details-mail-from-email").val() == "") {
						alert("Please specify an Email address.");
					} else if ( $("users-details-mail-from-sender").val() == "") {
						alert("Please specify an Email Name.");
					} else {
					
						$('#users-details-membership-roles option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'users',
							action: 'saveUserDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveUserCallback
						});					
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}			
		]);
		
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});

		_setup_password_again();

		$('#btn-user-details-change-password', context).click( function () {
			var passwd = $.trim( $('#users-details-change-password', context).val() );
			if ( passwd != '' ) {
				var enc_passwd = encodeURIComponent(passwd);
				$.main.ajaxRequest({
					modName: 'configuration',
					pageName: 'users',
					action: 'changeUserPassword',
					queryString: 'id=' + params.id + '&new_password=' + enc_passwd,
					success: changeUserPasswordCallback
				});
			}
		})
		
		// show/hide 'validate template' button
		$('a[href^="#users-details-tabs-"]', context).click( function () {
			if ( $(this).attr('href') == '#users-details-tabs-change-password' ) {
				$(":button:contains('Close')").show();
				$(":button:contains('Cancel')").hide();
				$(":button:contains('Save')").hide();
			} else {
				$(":button:contains('Close')").hide();
				$(":button:contains('Cancel')").show();
				$(":button:contains('Save')").show();
			}
		});
		
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveUserCallback ( params ) {
	
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'users',
			action: 'getUserItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function changeUserPasswordCallback ( params ) {
	if ( params.changeOk == 1 ) {
		alert( 'Password successfully changed!' );
	} else {
		alert( params.message );
	}
}
