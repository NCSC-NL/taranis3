/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function() {
	
	$('#user-panel-link').click( function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'user_panel',
			action: 'openDialogUserSettings',
			success: openDialogUserSettingsCallback
		});
		
		dialog.dialog('option', 'title', 'User settings and preset searches');
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
	
});

function openDialogUserSettingsCallback ( params ) {
	$('#user-panel-tabs').newTabs();
	
	$('.select-right').each( function () {
		var searchId = $(this).attr('data-id'),
			setting = $(this).attr('data-setting');
		
		checkRightColumnOptions( $('#' + setting + '_left_column_' + searchId), $(this) );
	});
	
	// click on button Change Password
	$('#btn-user-panel-change-password').click( function() {
		if ( $.trim( $('#user-panel-new-password').val() ) == '' ) {
			alert('New password cannot be blank.');
		} else if ( $('#user-panel-new-password').val() != $('#user-panel-confirm-password').val() ) {
			alert( 'Confirmation password does not match new password' );
		} else {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'user_panel',
				action: 'changePassword',
				queryString: $('#user-panel-change-password-form').serializeWithSpaces(),
				success: changePasswordCallback
			});
		}
	});	
	
	// remove password change OK message when typing in one of the password input fields
	$('input[type="password"]').keypress( function() {
		if ( !$('#user-panel-change-password-ok').hasClass('hidden') ) {
			$('#user-panel-change-password-ok').addClass('hidden');
		}
	});

	// show/hide settings
	$('.user-panel-search-settings-summary .span-link, .span-link[data-setting="description"]').click( function () {
		var settingsBlock = $('.user-panel-search-settings-' + $(this).attr('data-setting') + '[data-id="' + $(this).attr('data-id') + '"]');
		if ( settingsBlock.is(':visible') ) {
			settingsBlock.hide();
		} else {
			settingsBlock.show();
		}
	});	
	
	// save search settings
	$('.btn-save-custom-search').click( function () {
		var searchObj = new Object(),
			searchId = $(this).attr('data-id'); 
		
		if ( $.trim( $('#description_' + searchId ).val() ) != '' ) {
		
			searchObj.id = searchId;
			searchObj.description = $('#description_' + searchId ).val();
			searchObj.keywords = $('#keywords_' + searchId ).val();
	
			searchObj.uriw = ( $('#unread_' + searchId ).is(':checked') ) ? '1' : '0';
			searchObj.uriw += ( $('#read_' + searchId ).is(':checked') ) ? '1' : '0';
			searchObj.uriw += ( $('#important_' + searchId ).is(':checked') ) ? '1' : '0';
			searchObj.uriw += ( $('#waitingroom_' + searchId ).is(':checked') ) ? '1' : '0';
	
			searchObj.startdate = $('#startdate_' + searchId ).val();
			searchObj.enddate = $('#enddate_' + searchId ).val();
			searchObj.hitsperpage = $('#hitsperpage_' + searchId ).val();
			searchObj.sortby = $('#sorting_' + searchId + ' option:selected').val()
	
			searchObj.sources = new Array();
			$('#sources_left_column_' + searchId + ' > option' ).each( function () {
				searchObj.sources.push( $(this).val() );
			});		
			
			searchObj.categories = new Array();
			$('#categories_left_column_' + searchId + ' > option' ).each( function () {
				searchObj.categories.push( $(this).val() );
			});
	
			searchObj.is_public = ( $('#is_public_yes_' + searchId ).is(':checked') ) ? '1' : '0'; 
	
			if ( $('#user-panel-search-settings-error[data-id="' + searchId +'"]' ).is(':visible') ) {
				$('#user-panel-search-settings-error[data-id="' + searchId +'"]' ).hide();
			}
			if ( searchObj.uriw == '0000' ) {
				alert( 'At least one status option must be chosen');
			} else if ( validateForm(['startdate_' + searchId, 'enddate_' + searchId]) ) {
				$.main.ajaxRequest({
					modName: 'configuration',
					pageName: 'user_panel',
					action: 'saveSearch',
					queryString: 'customSearch=' + encodeURIComponent( JSON.stringify( searchObj ) ),
					success: saveSearchCallback
				});
			}
		} else {
			alert('Please specify a description.');
		}
	});

	// delete a custom search
	$('.btn-delete-custom-search').click( function () {
		var searchId = $(this).attr('data-id');
		
		if ( confirm("Are you sure you want to permenantly delete the search '" + $('span[data-setting="description"][data-id="' + searchId + '"]').text() + "'?") ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'user_panel',
				action: 'deleteSearch',
				queryString: 'searchId=' + searchId,
				success: deleteSearchCallback
			});			
		}
	});
	
	// save Assess autorefresh setting
	$('#btn-user-panel-save-assess-setting').click( function () {
		var refreshSetting = $('input[name="assess_autorefresh"]:checked').val();
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'user_panel',
			action: 'saveAssessRefreshSetting',
			queryString: 'assess_autorefresh=' + $('input[name="assess_autorefresh"]:checked').val(),
			success: saveAssessRefreshSettingCallback
		});		
	});

	// remove save OK message when changing refresh setting
	$('input[name="assess_autorefresh"]').change( function() {
		if ( !$('#user-panel-save-assess-setting-ok').hasClass('hidden') ) {
			$('#user-panel-save-assess-setting-ok').addClass('hidden');
		}
	});
}

function changePasswordCallback ( params ) {
	if ( params.changeOk ) {
		$('#user-panel-change-password-ok').removeClass('hidden');
	} else {
		alert( params.message );
	}
}

function saveSearchCallback ( params ) {
	
	if ( params.saveOk ) {
		var searchId = params.searchSettings.id;
		
		$('span[data-setting="description"][data-id="' + searchId + '"]').text(  params.searchSettings.description );
		if ( params.searchSettings.keywords ) {
			$('span[data-setting="keywords"][data-id="' + searchId + '"]').text(  params.searchSettings.keywords );
		} else {
			$('span[data-setting="keywords"][data-id="' + searchId + '"]').text( '[no keywords]' );
		}

		var span_uriw_text = ( $('#unread_' + searchId ).is(':checked') ) ? 'Unread, ' : '';
		span_uriw_text += ( $('#read_' + searchId ).is(':checked') ) ? 'Read, ' : '';
		span_uriw_text += ( $('#important_' + searchId ).is(':checked') ) ? 'Important, ' : '';
		span_uriw_text += ( $('#waitingroom_' + searchId ).is(':checked') ) ? 'Waitingroom, ' : '';

		span_uriw_text = span_uriw_text.replace( /, $/, "" );
		$('span[data-setting="uriw"][data-id="' + searchId + '"]').text( span_uriw_text );
		
		$('span[data-setting="startenddate"][data-id="' + searchId + '"]').text( $('#startdate_' + searchId ).val() || 'None' + ' / ' +  $('#enddate_' + searchId ).val() || None );
		
		$('span[data-setting="hitsperpage"][data-id="' + searchId + '"]').text(  params.searchSettings.hitsperpage );
		
		$('span[data-setting="sorting"][data-id="' + searchId + '"]').text( $('#sorting_' + searchId + ' option:selected').text() );

		var sourceCount = 0,
			sourceText = '';
		
		$.each( params.searchSettings.sources, function(index) {
			if ( sourceCount < 3 ) {
				sourceText +=  params.searchSettings.sources[index] + ', ';
			}
			sourceCount++;					 
		});

		sourceText = sourceText.replace( /, $/, "" );
		
		if ( sourceCount > 3 ) {
			var extraSources = sourceCount - 3;
			sourceText += ' +' + extraSources;
		}

		if ( sourceText == '' ) {
			sourceText = 'ALL';
		}				
		
		$('span[data-setting="sources"][data-id="' + searchId + '"]').text( sourceText );

		var categoryText = '';
		$('#categories_left_column_' + searchId + ' > option' ).each( function () {
			categoryText += $(this).text() + ', ';
		});

		categoryText = categoryText.replace( /, $/, "" );

		if ( categoryText == '' ) {
			categoryText = 'ALL';
		}
		$('span[data-setting="categories"][data-id="' + searchId + '"]').text( categoryText );

		if (  params.searchSettings.is_public == '1' ) { 
			$('span[data-setting="public"][data-id="' + searchId + '"]').text( 'yes' );
		} else {
			$('span[data-setting="public"][data-id="' + searchId + '"]').text( 'no' );
		}
		
	} else {
		alert( params.message );
	}
}

function deleteSearchCallback ( params ) {
	if ( params.deleteOk ) {
		$('.user-panel-search-block[data-id="' + params.searchId + '"]').remove();
	} else {
		alert( params.message );
	}
}

function saveAssessRefreshSettingCallback ( params ) {
	if ( params.saveOk ) {
		$('#user-panel-save-assess-setting-ok').removeClass('hidden');
	} else {
		alert( params.message );
	}
}
