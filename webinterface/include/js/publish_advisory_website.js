// $Author$
// $Rev$
// $Id$
// $Date$

function openDialogPublishWebsiteCallback ( params ) {
	var context =  $('#advisory-website-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Publish',
			click: function () {
				
				$(":button:contains('Publish')").prop('disabled', true).addClass('ui-state-disabled');
				var publicationText = encodeURIComponent( $('#advisory-preview-text', context).val() );
					
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish',
					action: 'checkPGPSigning',
					queryString: 'id=' + params.publicationId + '&publicationType=website&publicationText=' + publicationText,
					success: publishAdvisoryWebsite,
					error: function() {
						$(":button:contains('Publish')").prop('disabled', false).removeClass('ui-state-disabled');
					}
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
}

function publishAdvisoryWebsite ( params ) {
	
	var context =  $('#advisory-website-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	if ( params.pgpSigningOk == 1 ) {

		$.main.activeDialog.dialog('option', 'buttons', []);
		$.main.activeDialog.html('Publishing Advisory...');
		
		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_website',
			action: 'publishAdvisoryWebsite',
			queryString: $(context).serializeWithSpaces() + '&id=' + params.publicationId,
			success: publishAdvisoryWebsiteCallback
		});
		
	} else {
		$(context).siblings('#dialog-error')
			.removeClass('hidden')
			.text(params.message);
		$(":button:contains('Publish')")
			.prop('disabled', false)
			.removeClass('ui-state-disabled');
	}
}

function publishAdvisoryWebsiteCallback ( params ) {

	// change close event for this dialog
	$.main.activeDialog.bind( "dialogclose", function(event, ui) {
		refreshPublicationList({ pub_type: 'website' });
	});
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}	
	]);
}
