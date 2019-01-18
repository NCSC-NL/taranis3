/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// view publishing details and calling list
	$('#content').on( 'click', '.img-publications-sentto', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'publish_details',
			action: 'openDialogPublishingDetails',
			queryString: 'id=' + $(this).attr('data-publicationid') + '&pt=' + $(this).attr('data-pubtype'),				
			success: openDialogPublishingDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Publishing details');
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

function openDialogPublishingDetailsCallback ( params ) {
	
	$('#publishing-details-tabs').newTabs();
	
	var buttons = new Array();
	
	if ( params.executeRight ) {
		
		if ( $('#publishing-details-tabs-callinglist').length > 0 ) {
			
			buttons.push({
				text: 'Print calling list day',
				click: function () {
					$.main.ajaxRequest({
						modName: 'publish',
						pageName: 'publish_advisory',
						action: 'printCallingList',
						queryString: 'id=' + params.publicationId + '&t=day',
						success: printPublishDetailsCallingListCallback
					});					
				} 
			});

			buttons.push({
				text: 'Download calling list day',
				click: function () {
					var callingListParams = new Object();
					callingListParams.id = params.publicationId;
					callingListParams.t = 'day';
					$('#downloadFrame').attr( 'src', 'loadfile/publish/publish_advisory/saveCallingList?params=' + JSON.stringify(callingListParams) );
				} 
			});

			buttons.push({
				text: 'Print calling list night',
				click: function () {
					$.main.ajaxRequest({
						modName: 'publish',
						pageName: 'publish_advisory',
						action: 'printCallingList',
						queryString: 'id=' + params.publicationId + '&t=night',
						success: printPublishDetailsCallingListCallback
					});					
				} 
			});

			buttons.push({
				text: 'Download calling list night',
				click: function () {
					var callingListParams = new Object();
					callingListParams.id = params.publicationId;
					callingListParams.t = 'night';
					$('#downloadFrame').attr( 'src', 'loadfile/publish/publish_advisory/saveCallingList?params=' + JSON.stringify(callingListParams) );
				} 
			});
			
			if ( params.canUnlock ) {
				// show the remove lock link for locked calls
				$('.publishing-details-call-remove-lock').each( function () {
					var callId = $(this).attr('data-id'),
						removeLockLink = $(this);
						
					if ( !$('.publishing-details-open-close-call[data-id="' + callId + '"]').hasClass('span-link') ) {
						removeLockLink.show();
					}
				});

				// click on 'Remove lock'
				$('.publishing-details-call-remove-lock').click( function () {
					var callId = $(this).attr('data-id');

					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'publish_details',
						action: 'adminRemoveCallLock',
						queryString: 'id=' + callId + '&publicationId=' + params.publicationId,				
						success: adminRemoveCallLockCallback
					});
					
				});				
			}
			
			// clicked on 'open call for' or 'close call for'
			$('.publishing-details-open-close-call').click( function () {
				if ( $(this).hasClass('span-link') ) {
					var callId = $(this).attr('data-id'),
						callState = ''; 
						
					if ( $('.publishing-details-call-details[data-id="' + callId + '"]').is(':visible') ) {
						$('.publishing-details-call-details[data-id="' + callId + '"]').hide();
						 callState = 'release';
					} else {
						$('.publishing-details-call-details[data-id="' + callId + '"]').show();
						callState = 'set';
					}			
					
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'publish_details',
						action: 'setCallLockState',
						queryString: 'id=' + callId + '&state=' + callState + '&publicationId=' + params.publicationId,				
						success: setCallLockStateCallback
					});				
				}			
			});
			
			// click on button 'Save & Close call'
			$('.btn-publishing-details-call-save').click( function () {
				var callId = $(this).attr('data-id'),
					isCalled = ( $('#is_called_yes_' + callId ).is(':checked') ) ? '1' : '0',
					queryString = 'id=' + callId 
								+ '&publicationId=' + params.publicationId 
								+ '&comments=' + encodeURIComponent( $('.publising-details-call-comments[data-id="' + callId + '"]').val() )
								+ '&isCalled=' + isCalled;
				
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'publish_details',
					action: 'saveCallDetails',
					queryString: queryString,				
					success: saveCallDetailsCallback
				});					
			});
			
			// change close event for this dialog, so it will include clearing the call locks for this user 
			$.main.activeDialog.bind( "dialogclose", function(event, ui) { 
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'publish_details',
					action: 'releaseAllCallLocks',
					queryString: 'publicationId=' + params.publicationId,
					success: null
				});	
				
				if ( $('.dialogs:visible').length == 0 ) {
					$('#screen-overlay').hide();
				}
			});
			
			$('a[href^="#publishing-details-tabs-"]').click( function () {
				if ( $(this).attr('href') == '#publishing-details-tabs-general' ) {
					$(":button:contains('Download details')").show();
					$(":button:contains('calling list')").hide();
				} else {
					$(":button:contains('Download details')").hide();
					$(":button:contains('calling list')").show();
				}
			});
			
		}

		buttons.push({
			text: 'Download details',
			click: function () {
				var detailsParams = new Object();
				detailsParams.id = params.publicationId;
				detailsParams.pt = params.publicationType;
				$('#downloadFrame').attr( 'src', 'loadfile/write/publish_details/downloadPublishDetails?params=' + JSON.stringify(detailsParams) );
			} 
		});
		
		buttons.push({
			text: 'Close',
			click: function () { $(this).dialog('close'); } 
		});
		
		$.main.activeDialog.dialog('option', 'buttons', buttons);
		
		$('a[href="#publishing-details-tabs-general"]').trigger('click');
		$(":button:contains('Close')").css('margin-left', '20px');
	} 
}

function setCallLockStateCallback ( params ) {

	if ( params.lockSetOk ) {
		$('.publishing-details-call-opened-by').empty();

		// update all calls
		updateList ( params.list, params.callId, params.isLocked );
		
		if ( params.lockState == 'set' && !params.isLocked ) {
			$('.publishing-details-call-details[data-id="' + params.callId + '"]').show();
			$('.publishing-details-open-close-call[data-id="' + params.callId + '"]').text('close call for');
			$('.publishing-details-open-close-call[data-id!="' + params.callId + '"]').removeClass('pointer span-link');
		} else {

			$('.publishing-details-call-details[data-id="' + params.callId + '"]').hide();
			$('.publishing-details-open-close-call[data-id="' + params.callId + '"]').text('open call for');
			
			$('.publishing-details-open-close-call').each( function () {
				var callId = $(this).attr('data-id');
				if ( !$('.publishing-details-call-remove-lock[data-id="' + callId + '"]').is(':visible') ) {
					$(this).addClass('pointer span-link');
				}
			});
		}
		
	} else {
		alert( params.message );
	} 
}

function saveCallDetailsCallback ( params ) {

	if ( params.saveOk ) {
	
		if ( $('#is_called_yes_' + params.callId ).is(':checked') ) {
			
			$('.publishing-details-is-called[data-id="' + params.callId + '"]')
				.html("&nbsp;has been informed&nbsp;")
				.addClass('publishing-details-is-called-yes')
				.removeClass('publishing-details-is-called-no');
			
		} else {
			$('.publishing-details-is-called[data-id="' + params.callId + '"]')
				.html("&nbsp;has NOT been informed&nbsp;")
				.removeClass('publishing-details-is-called-yes')
				.addClass('publishing-details-is-called-no');		
		}
	
		$('.publishing-details-call-details[data-id="' + params.callId + '"]').hide();
		$('.publishing-details-open-close-call[data-id="' + params.callId + '"]').text('open call for');
	
		$('.publishing-details-open-close-call').each( function () {
			var callId = $(this).attr('data-id');
			if ( !$('.publishing-details-call-remove-lock[data-id="' + callId + '"]').is(':visible') ) {
				$(this).addClass('pointer span-link');
			}
		});
		
		updateList ( params.list, params.callId, 0 );
		
	} else {
		alert(params.message);
	}	
}

function adminRemoveCallLockCallback ( params ) {

	if ( params.removeOk ) {
		updateList( params.list, 0, 0 );
		$('.publishing-details-open-close-call[data-id="' + params.callId + '"]').addClass('pointer span-link');
		$('.publishing-details-call-opened-by[data-id="' + params.callId + '"]').empty();
		$('.publishing-details-call-remove-lock[data-id="' + params.callId + '"]').hide();
	} else {
		alert(params.message);
	}
}

function updateList ( calls, callId, is_locked ) {

	var is_admin = ( $('.publishing-details-call-remove-lock').length > 0 ) ? true : false;

	//update all calls
	$.each( calls, function( index, call ) {

		if ( call.locked_by != null || ( call.id == callId && is_locked ) ) {

			$('.publishing-details-call-opened-by[data-id="' + call.id + '"]').html( '[ is opened by ' + call.fullname + ' ]' );
			$('.publishing-details-open-close-call[data-id="' + call.id + '"]').removeClass('span-link pointer')

			if ( is_admin ) {
				$('.publishing-details-call-remove-lock[data-id="' + call.id + '"]').show();
			}
		}

		if ( call.is_called != $('input[name="is_called_' + call.id  + '"]:checked').val() ) {
			if ( call.is_called == '1' ) {
				if ( $('.publishing-details-is-called[data-id="' + call.id + '"]').hasClass('publishing-details-is-called-no') ) {
					$('.publishing-details-is-called[data-id="' + call.id + '"]')
						.html("&nbsp;has been informed&nbsp;")
						.addClass('publishing-details-is-called-yes')
						.removeClass('publishing-details-is-called-no');
				}
			} else {
				if ( $('.publishing-details-is-called[data-id="' + call.id + '"]').hasClass('publishing-details-is-called-yes') ) {
					$('.publishing-details-is-called[data-id="' + call.id + '"]')
						.html("&nbsp;has NOT been informed&nbsp;")
						.removeClass('publishing-details-is-called-yes')
						.addClass('publishing-details-is-called-no');
				}
			}
		}

		$('.publising-details-call-comments[data-id="' + call.id + '"]').html( call.comments );
		$('.publising-details-call-comments[data-id="' + call.id + '"]').val( $('.publising-details-call-comments[data-id="' + call.id + '"]').text() );
	});
}

function printPublishDetailsCallingListCallback ( params ) {
	printHtmlInput( params.callingList );
}
