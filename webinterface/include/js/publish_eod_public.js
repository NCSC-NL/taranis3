/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogPublishEod_publicCallback ( params ) {

	var context =  $('#eod-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Set to Pending',
			click: function () {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eod',
					action: 'setEodStatus',
					queryString: 'publicationId=' + params.publicationId + '&status=0',
					success: refreshPublicationList({pub_type: 'eod_public'})
				});
				
				$('#screen-overlay').hide();
				$(this).dialog('close');
			}
		},
		{
			text: 'Publish',
			click: function () {

				// we're trimming the text because some PGP signing tools add extra newlines at start and/or end of text 
				$('#eod-preview-text', context).val( $.trim( $('#eod-preview-text', context).val() ) );

				var publicationText = encodeURIComponent( $('#eod-preview-text', context).val() );
				
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish',
					action: 'checkPGPSigning',
					queryString: 'id=' + params.publicationId + '&publicationType=eod_public&publicationText=' + publicationText,
					success: publishEodPublic
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
}

function publishEodPublic ( params ) {
	
	var context = $('#eod-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	if ( params.pgpSigningOk == 1 ) {

		$.main.activeDialog.dialog('option', 'buttons', []);
		$.main.activeDialog.html('Publishing End-of-day...');
		
		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_eod_public',
			action: 'publishEodPublic',
			queryString: $(context).serializeWithSpaces() + '&id=' + params.publicationId,
			success: publishEodPublishCallback
		});
		
	} else {
		$(context).siblings('#dialog-error')
			.removeClass('hidden')
			.text(params.message);
	}
}

function publishEodPublishCallback ( params ) {
	// change close event for this dialog
	$.main.activeDialog.bind( "dialogclose", function(event, ui) {
		refreshPublicationList({pub_type: 'eod_public'});
	});
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}
	]);		
}
