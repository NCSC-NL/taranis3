/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// downloadframe for downloading publication attachments
	$(document).on('click', '.publication-attachment-link', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/write/publications/loadPublicationAttachment?params=' + JSON.stringify( { fileID: $(this).attr('data-fileid') } ) );
	});
	
	// open publications details dialog
	$('#content').on('click', '.img-publications-edit, .img-publications-view', function () {
		var pubType = $(this).attr('data-pubtype'),
			publicationId = ( $(this).attr('data-publicationid') ) ? $(this).attr('data-publicationid') : $(this).attr('data-id'),
			action = 'openDialog' + pubType.charAt(0).toUpperCase() + pubType.slice(1) + 'Details';
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'write',
			pageName: pubType,
			action: action,
			queryString: 'id=' + publicationId,
			success: action + 'Callback'
		});		
		
		dialog.dialog('option', 'title', 'Publication details');
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
	
	// unlock publication (user needs to be admin)
	$('#content').on('click', '.img-publications-lock', function () {
		if ( confirm('Are you sure you want to remove lock') ) {
			var publicationId = $(this).attr('data-publicationid');
			// closePublication
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'closePublication',
				queryString: 'id=' + publicationId + '&closeByAdmin=1',
				success: null
			}, true);
			
			// reload item
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'getPublicationItemHtml',
				queryString: 'insertNew=0&id=' + publicationId + '&pubType=' + $(this).attr('data-pubtype'),
				success: getPublicationItemHtmlCallback
			}, true);			
		}
	});

    // delete publication
    $('#content').on('click', '.img-publications-delete', function () {
    	var publicationId = $(this).attr('data-publicationid');
    	
    	if ( confirm('Are you sure you want to delete "' + $.trim( $('.publications-item-title', $('#' + publicationId) ).text() ) + '"' ) ) {
    		
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'deletePublication',
				queryString: 'del=' + $(this).attr('data-detailsid') + '&publicationId=' + publicationId + '&pubType=' + $(this).attr('data-pubtype'),
				success: deletePublicationCallback
			}, true);
    	}
    });
    
    // open update publication dialog
    $('#content').on('click', '.img-publications-update',function () {
		var pubType = $(this).attr('data-pubtype'),
			publicationId = $(this).attr('data-publicationid');
		
		var action = 'openDialogUpdate' + pubType.charAt(0).toUpperCase() + pubType.slice(1);
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'write',
			pageName: pubType,
			action: action,
			queryString: 'id=' + publicationId + '&pubType=' + pubType,
			success: action + 'Callback'
		});		
		
		dialog.dialog('option', 'title', 'Publication update');
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

    // open preview publication dialog
    $('#content').on('click', '.img-publications-preview, .publications-preview-link', function () {
		var pubType = $(this).attr('data-pubtype'),
			publicationId = ( $(this).attr('data-publicationid') ) ? $(this).attr('data-publicationid') : $(this).attr('data-id'),
			action = 'openDialogPreview' + pubType.charAt(0).toUpperCase() + pubType.slice(1);
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'write',
			pageName: pubType,
			action: action,
			queryString: 'id=' + publicationId + '&pubType=' + pubType,
			success: action + 'Callback'
		});		
		
		dialog.dialog('option', 'title', 'Publication preview');
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

function getPublicationItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('#publications-content-heading').after( params.itemHtml );
	} else {
		$('#' + params.publicationId)
			.html( params.itemHtml )
			.removeClass( 'publications-pending publications-ready4review publications-approved publications-published publications-sending' )
			.addClass( 'publications-' + params.publicationStatus );
	}
}

function deletePublicationCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		if ( params.multiplePublicationsUpdated == 1) {
			$('#btn-publications-search').trigger('click');
		} else {
			$('#' + params.publicationid ).remove();
	
			if (params.previousVersion != '' ) {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'publications',
					action: 'getPublicationItemHtml',
					queryString: 'insertNew=0&id=' + params.previousVersion + '&pubType=' + $('#' + params.previousVersion).attr('data-pubtype'),
					success: getPublicationItemHtmlCallback
				}, true);	
			}
		}		
	} else {
		alert( params.message );
	}
}

// used by advisory and advisory forward
function setProbability (is_test, context) {
	var count = 0;
	for ( var i = 0; i < probabilityFields.length; i++ ) {
		$('input[name="' + probabilityFields[i] + '"]', context).each( function (i) {
			if ( $(this).is(':checked') ) {
				count += Number( $(this).val() );
			}
		});
	}
	if ( count < 19 ) {
		if ( is_test ) {
			return $('#advisory-details-probability option[value="3"]', context).is(':selected');
		} else {
			$('#advisory-details-probability option[value="3"]', context).prop('selected', true);			
		}
	} else if ( count < 28 ) {
		if ( is_test ) {
			return $('#advisory-details-probability option[value="2"]', context).is(':selected');
		} else {
			$('#advisory-details-probability option[value="2"]', context).prop('selected', true);
		}
	} else if ( count >= 28  ) {
		if ( is_test ) {
			return $('#advisory-details-probability option[value="1"]', context).is(':selected');
		} else {
			$('#advisory-details-probability option[value="1"]', context).prop('selected', true);
		}
	}
}

// used by advisory and advisory forward
function setDamage (is_test, context) {
	var level = 0;

	for ( var i = 0; i < damageFields.length; i++ ) {
		$('input[name="' + damageFields[i] + '"]', context).each( function (i) {
			if ( $(this).is(':checked') && $(this).val() > level ) {
				level = Number( $(this).val() );
			}
		});
	}
	if ( level == 0 ) {
		if ( is_test ) {
			return $('#advisory-details-damage option[value="3"]', context).is(':selected');
		} else {
			$('#advisory-details-damage option[value="3"]', context).prop('selected', true);
		}
	} else if ( level == 1 ) {
		if ( is_test ) {
			return $('#advisory-details-damage option[value="2"]', context).is(':selected');
		} else {
			$('#advisory-details-damage option[value="2"]', context).prop('selected', true);
		}
	} else if ( level == 2 ) {
		if ( is_test ) {
			return $('#advisory-details-damage option[value="1"]', context).is(':selected');
		} else {
			$('#advisory-details-damage option[value="1"]', context).prop('selected', true);
		}
	}
}

// used by advisory and advisory forward
function setReadyForReviewButton ( context ) {
	if ( $('#advisory-details-publish-LL').val() == 0 ) {
		if ( $('#advisory-details-probability', context).val() == 3 && $('#advisory-details-damage', context).val() == 3 ) {
			$(":button:contains('Ready for review')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');
			
			$('#advisory-messages[data-publicationid="' + $(context).attr('data-publicationid') + '"]')
				.removeClass('hidden')
				.show()
				.text('Matrix is set with LOW probability and LOW damage!');
		} else {
			$(":button:contains('Ready for review')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
			
			$('#advisory-messages[data-publicationid="' + $(context).attr('data-publicationid') + '"]')
				.hide()
				.text('');
			
		}
	}
}
