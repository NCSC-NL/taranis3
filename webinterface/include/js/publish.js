/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// downloadframe for downloading publication attachments
	$(document).on('click', '.publish-attachment-link', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/write/publications/loadPublicationAttachment?params=' + JSON.stringify( { fileID: $(this).attr('data-fileid') } ) );
	});
	
	$('#content').on('click', '.img-publish-send', function () {
	
		var publicationType = $(this).attr('data-pubtype'),
			publicationId = $(this).attr('data-publicationid'),
			action = 'openDialogPublish' + publicationType.charAt(0).toUpperCase() + publicationType.slice(1);

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		var queryString = 'id=' + publicationId;

		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_' + publicationType,
			action: action,
			queryString: queryString,
			success: action + 'Callback'
		});		
		
		dialog.dialog('option', 'title', 'Publish publication');
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
	
	// click on lock icon
	$('#content').on('click', '.img-publish-lock', function () {
		if ( $(this).hasClass('pointer') ) {
			if ( confirm('Are you sure you want to remove lock') ) {
				var publicationId = $(this).attr('data-publicationid'),
					publicationType = $(this).attr('data-publicationtype'),
					action = 'close' + publicationType.charAt(0).toUpperCase() + publicationType.slice(1) + 'Publication';
				
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish_' + publicationType,
					action: action,
					queryString: 'id=' + publicationId + '&releaseLock=1',
					success: refreshPublicationList({pub_type: publicationType})
				});				
			}
		} else {
			alert('Publish lock is currently enabled.\nPlease contact your Taranis Administrator if you want this lock to be deleted.');			
		}
	});
	
});

function refreshPublicationList ( params ) {
	var queryString = '';

	if ( params != null && 'pub_type' in params ) {
		queryString = 'pub_type=' + params.pub_type;
	}
			
	$.main.ajaxRequest({
		modName: 'publish',
		pageName: 'publish',
		action: 'displayPublish',
		queryString: queryString,
		success: null
	});
}
