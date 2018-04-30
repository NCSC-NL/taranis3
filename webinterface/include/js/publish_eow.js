/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogPublishEowCallback ( params ) {

	var context =  $('#eow-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Set to Pending',
			click: function () {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eow',
					action: 'setEowStatus',
					queryString: 'publicationId=' + params.publicationId + '&status=0',
					success: refreshPublicationList({pub_type: 'eow'})
				});
				
				$('#screen-overlay').hide();
				$(this).dialog('close');
			}
		},
		{
			text: 'Publish',
			click: function () {

				// we're trimming the text because some PGP signing tools add extra newlines at start and/or end of text 
				$('#eow-preview-text', context).val( $.trim( $('#eow-preview-text', context).val() ) );

				var publicationText = encodeURIComponent( $('#eow-preview-text', context).val() );
				
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish',
					action: 'checkPGPSigning',
					queryString: 'id=' + params.publicationId + '&publicationType=eow&publicationText=' + publicationText,
					success: publishEow
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
}

function publishEow ( params ) {
	
	var context = $('#eow-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	if ( params.pgpSigningOk == 1 ) {

		$.main.activeDialog.dialog('option', 'buttons', []);
		$.main.activeDialog.html('Publishing End-of-week...');
		
		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_eow',
			action: 'publishEow',
			queryString: $(context).serializeWithSpaces() + '&id=' + params.publicationId,
			success: publishEowCallback
		});
		
	} else {
		$(context).siblings('#dialog-error')
			.removeClass('hidden')
			.text(params.message);
	}
}

function publishEowCallback ( params ) {
	// change close event for this dialog
	$.main.activeDialog.bind( "dialogclose", function(event, ui) {
		refreshPublicationList({pub_type: 'eow'});
	});
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}
	]);		
}
