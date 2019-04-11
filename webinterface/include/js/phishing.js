/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// add url
	$('#filters').on('click', '#btn-phishing-add', function () {
		if ( $('#phishing-add-reference[mandatory]').length > 0 && $.trim( $('#phishing-add-reference').val() ) == '' ) {
			alert( 'You forgot to set a reference' );
		} else if ( ! $('#phishing-add-url').val().match(/^https?:\/\/./) ) {
			alert( 'Please provide is a http or https url' );
		} else {
			
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'phishing_overview',
				action: 'addPhishingItem',
				queryString: $('#form-phishing-add').serializeWithSpaces() + '&tool=phishing_checker',
				success: addPhishingItemCallback
			});
		}
	});
	
	// edit reference
	$('#content').on('click', '.btn-edit-reference', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		var phishId = $(this).attr('data-id');
		
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'phishing_overview',
			action: 'openDialogPhishingDetails',
			queryString: 'tool=phishing_checker&id=' + phishId,
			success: function ( params ) {
				$.main.activeDialog.dialog('option', 'buttons', [
					{
						text: 'Save',
						click: function () {
							$('#form-phish-details[data-id="' + phishId + '"]')
							if ( $('#phishing-reference[mandatory]').length > 0 && $.trim( $('#phishing-reference').val() ) == '' ) {
								alert( 'You forgot to set a reference' );
							} else {
								$.main.ajaxRequest({
									modName: 'tools',
									pageName: 'phishing_overview',
									action: 'savePhishingDetails',
									queryString: $('#form-phish-details[data-id="' + phishId + '"]').serializeWithSpaces() + '&tool=phishing_checker&id=' + phishId,
									success: function (saveParams) {
										if ( saveParams.saveOk == 1 ) {
											$('.phishing-item[data-id="' + phishId + '"] .phishing-item-reference').html(saveParams.reference);
											$('.phishing-item[data-id="' + phishId + '"] .phishing-item-campaign').html(saveParams.campaign);
											$.main.activeDialog.dialog('close');
										} else {
											alert( saveParams.message );
										}
									}
								});
							}
						}
					},
					{
						text: 'Cancel',
						click: function () { $(this).dialog('close') }
					}
				]);
				var phishingScreenshotsFieldsetContext = 'fieldset[id="fieldset-phishing-screenshots"][data-id="' + phishId + '"]';

				$('.phishing-site-screenshot', phishingScreenshotsFieldsetContext).click( function () {
					var screenshotDialog = $('<div>').newDialog();
					screenshotDialog.html('<fieldset>loading...</fieldset>');
					
					var phishId = $(this).attr('data-phishid'),
						objectId = $(this).attr('data-objectid');
					
					$.main.ajaxRequest({
						modName: 'tools',
						pageName: 'phishing_overview',
						action: 'openDialogPhishingScreenshot',
						queryString: 'tool=phishing_checker&phishid=' + phishId + '&objectid=' + objectId,
						success: null
					})
					
					screenshotDialog.dialog('option', 'title', 'Phishing checker site screenshot');
					screenshotDialog.dialog('option', 'width', 'auto');
					screenshotDialog.dialog('option', 'position', { my: 'left top', at: 'left top', of: $('#content-wrapper') } );
					screenshotDialog.dialog({
						buttons: {
							'Close': function () {
								$(this).dialog( 'close' );
							}
						}
					});
					screenshotDialog.dialog('open');
					
				});
				
			}
		});
		
		dialog.dialog('option', 'title', 'Phishing checker details');
		dialog.dialog('option', 'width', '400px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});

	// delete url
	$('#content').on('click', '#btn-delete-phishing-item', function () {
		if ( confirm('Are you sure you want to delete the phishing check?') ) {
			
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'phishing_overview',
				action: 'deletePhishingItem',
				queryString: 'tool=phishing_checker&id=' + $(this).attr('data-id'),
				success: deletePhishingItemCallback
			});
		}
	});
	
	// perform a whois on url
	$('#content').on('click', '#btn-whois-phishing-item', function () {
		
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'whois',
			action: 'getWhoisHost',
			queryString: 'tool=whois&whois=' + encodeURIComponent( $(this).attr('data-phishingurl') ),
			success: null
		});	
	});
	
	// add url with enter
	$('#filters').on( 'keypress', '#phishing-add-url, #phishing-add-reference, #phishing-add-campaign', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-phishing-add').trigger('click');
		}
	});
	
	// switch autorefresh on/off
	$('#filters').on('click', '#btn-phishing-autorefresh', function () {
		if ( $.main.phishingTimer.isActive === true ) {
			stopPhishingTimer();
		} else {
			startPhishingTimer();
		}
	});
});

function addPhishingItemCallback ( params ) {
	if ( params.addOk == 1 ) {
		$('#phishing-content-heading').after( params.itemHtml );
		$('.no-items').remove();
	} else {
		alert(params.message);
	}
}

function deletePhishingItemCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		$('.phishing-item[data-id="' + params.id + '"]').remove();
	} else {
		alert(params.message);
	}
}
