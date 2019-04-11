/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// open the 'create analysis from assess item' dialog (assess2analyze)
	$(document).on('click', '.img-assess-item-analyze, #assess-details-digest, .btn-link-to-other-analysis', function () {
		
		var itemDigest = $(this).attr('data-digest');
		
		var hasClusteredItems = ( $('div[id="' + itemDigest +'"]').hasClass('item-top-cluster-row') ) ? 1 : 0;
		
		if ( itemDigest == undefined ) {
			itemDigest = $(this).val();
		}
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		var queryString = 'digest=' + itemDigest + '&hasClusteredItems=' + hasClusteredItems; 
		if ( $(this).hasClass('btn-link-to-other-analysis') ) {
			queryString += '&ul=' + $(this).attr('data-analysisid');
		}

		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'assess2analyze',
			action: 'displayAssessAnalysis',
			queryString: queryString,
			success: displayAssessAnalysisCallback
		});		

		dialog.dialog('open');
		
		// do not show dialog with content if user has no analysis_rights.read_right (assess2analyze) 
		dialog.dialog('option', 'title', 'Analyze item');
		dialog.dialog('option', 'width', '780px');
		dialog.dialog({
			buttons: {
				'Cancel': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		if ( $(this).hasClass('img-assess-item-analyze') ) {
			$('.item-arrow:visible').hide();
			$('#' + itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();
		}
		// Continue with displayAssessAnalysisCallback in assess2anayze.js after AJAX request is done.
	});
	
	// open assess details dialog
	$(document).on('click', '.img-assess-item-details, .btn-analyze-assess-details, .assess-details-link', function () {
		
		var itemDigest = ( $(this).attr('data-digest') ) ? $(this).attr('data-digest') : $(this).attr('data-id'),
			queryString = 'digest=' + itemDigest; 
			
		if ( $(this).attr('data-isArchived') ) {
			queryString += '&is_archived=' + $(this).attr('data-isArchived');
		}
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess_details',
			action: 'openDialogAssessDetails',
			queryString: queryString,
			success: openDialogAssessDetailsCallback
		});
		
		dialog.dialog('open');
		
		dialog.dialog('option', 'title', 'Assessment details');
		dialog.dialog('option', 'width', '890px');
		dialog.dialog({
			buttons: [
			    {
					text: 'Close',
					click: function () {
						$(this).dialog( 'close' );
					}
			    }
			]
		});

		if ( $(this).hasClass('img-assess-item-details') ) {
			$('.item-arrow:visible').hide();
			$('#' + itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();
		}
		
	});

	// clicking on email items will open a dialog window showing the email.
	$(document).on('click', '.assess-email-item-link', function () {		

		// the following replace is needed because of legacy 
		var queryString = $(this).attr('data-link').replace( /.*?(id=\d+)/, '$1');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'show_mail',
			action: 'displayMail',
			queryString: queryString,
			success: showmailCallback
		});		
		
		dialog.dialog('option', 'title', 'Email item details');
		dialog.dialog('option', 'width', '850px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');

		var itemDigest = $(this).attr('data-id');
		if ( itemDigest ) {
			$('.item-arrow:visible').hide();
			$('#' + itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();
		}		
		// Continue with showmailCallback() after AJAX request is done.
	});
	
	
	$(document).on('click', '.assess-screenshot-item-link', function () {
		var itemDigest = $(this).attr('data-id');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess_dialogs',
			action: 'openDialogAssessItemScreenshot',
			queryString: 'digest=' + itemDigest,
			success: function (params) {
				
			}
		});
		
		dialog.dialog('option', 'title', 'Assess screenshot item');
		dialog.dialog('option', 'width', 'auto');
		dialog.dialog('option', 'position', { my: 'left top', at: 'left top', of: $('#content-wrapper') } );
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
		
		if ( itemDigest ) {
			$('.item-arrow:visible').hide();
			$('#' + itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();
		}

	});
	
});

function showmailCallback ( params ) {
//TODO: add context to selectors
	$('#assess-show-mail-tabs').newTabs({selected: 0});

	$('.assess-show-mail-attachment').click( function () {
		var downloadParams = new Object();
		downloadParams.id = $('#mailItemId').val();
		downloadParams.attachmentName = $(this).text();
		
		$('#downloadFrame').attr( 'src', 'loadfile/assess/download_attachment/downloadAttachment?params=' + JSON.stringify(downloadParams) );
	});
	
}
