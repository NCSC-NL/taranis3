/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function() {
	
	// remove lock on analysis (should only work for admins and users' own analysis)
	$('#content').on( 'click', '.btn-analyze-lock', function () {
		if ( confirm('Are you sure you want to remove lock') ) {
			var analysisId = $(this).attr('data-analysisid');

			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze_details',
				action: 'closeAnalysis',
				queryString: 'id=' + analysisId,
				success: null
			}, true);				
			
			$(this).attr({'src': $.main.webroot + '/images/icon_none.png', 'class': 'img-placeholder', 'title': '', 'alt': 'no icon'});
			$('img[alt="view"][data-analysisid="' + analysisId + '"]').attr({'src': $.main.webroot + '/images/icon_modify.png', 'alt': 'open', 'title': 'Open analysis'});
		}
	});
	
	//click on icon to hide/show descriptions per item
	$('#content').on('click', '.btn-toggle-description', function () {
		var analysisId = $(this).attr('data-analysisid');

		if ( $('#analyze-description-' + analysisId ).is( ':hidden' ) ) {
			$('#analyze-description-' + analysisId ).slideDown('fast');
			$(this).text('hide comments')
		} else {
			$('#analyze-description-' + analysisId ).slideUp('fast');
			$(this).text('show comments')
		}
	});

	function addComment(comment) {
		if(comment == '') return;

		var $where   = $('#analyze-details-comments');
		var comments = $where.val();

		var now      = new Date();
		var header   = "[== " + $.main.fullname + " (" + now.toLocaleString() + ") ==]\n";
		comments    += (comments == '' ? '' : "\n\n") + header + comment;

		$where.val(comments);
		$where.attr('data-commentsadded', 'yes');
	}

	// add a comment in the analyze details windows
	$(document).on('click', '#btn-analyze-item-new-analysis-add-comment', function () {
		var $commentBlock = $('#analyze-details-add-comment');
		addComment($commentBlock.val());
		$commentBlock.val('');
	});

	// take/release ownership of analysis
	$('#content').on('click','.btn-analyze-ownership', function () {
		var analysisId = $(this).attr('data-analysisidownership');

		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze',
			action: 'checkOwnership',
			queryString: 'id=' + analysisId,
			success: setOwnershipCallback
		}, true);
	});
	
	// open analysis details dialog
	$(document).on('click', '.analyze-item-details-link', function () {
		var analysisId = ( $(this).attr('data-analysisid') ) ? $(this).attr('data-analysisid') : $(this).attr('data-id');
		dialog = $('<div>').newDialog();

		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze_details',
			action: 'openDialogAnalyzeDetails',
			queryString: 'id=' + analysisId,
			success: openDialogAnalyzeDetailsCallback
		});
		
		dialog.html('<fieldset>loading...</fieldset>');
		
		dialog.dialog('option', 'title', 'Analysis details');
		dialog.dialog('option', 'width', '890px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
		
		$('.item-arrow:visible').hide();
		$('#' + $(this).attr('data-analysisid') + ' .item-arrow').show();
	});
	
	// create a publication from an analysis
	$('#content').on('click', '.btn-analyze-to-publication', function () {
		dialog = $('<div>').newDialog();

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'analysis2publication',
			action: 'openDialogAnalysisToPublication',
			queryString: 'id=' + $(this).attr('data-analysisid'),
			success: openDialogAnalysisToPublicationCallback
		});
		
		dialog.html('<fieldset>loading...</fieldset>');
		
		dialog.dialog('option', 'title', 'Put analysis in advisory');
		dialog.dialog('option', 'width', '680px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');

		$('.item-arrow:visible').hide();
		$('#' + $(this).attr('data-analysisid') + ' .item-arrow').show();
		
	});

	// open analysis details readonly dialog
	$(document).on('click', '.analyze-item-details-readonly-link', function () {
		var analysisId = ( $(this).attr('data-analysisid') ) ? $(this).attr('data-analysisid') : $(this).attr('data-id');
		dialog = $('<div>').newDialog();

		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze_details',
			action: 'openDialogAnalyzeDetailsReadOnly',
			queryString: 'id=' + analysisId,
			success: function (readonlyParams) {
				$('div[id="analyze-details-readonly-tabs"][data-analysisid="' + analysisId + '"]').newTabs();
			}
		});
		
		dialog.html('<fieldset>loading...</fieldset>');

		dialog.dialog('option', 'title', 'Analysis details readonly');
		dialog.dialog('option', 'width', '890px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});

	// unlink item from analysis
	$('#content').on('click', '.btn-unlink-from-analysis', function () {
		var analysisId = $(this).attr('data-analysisid'),
			itemId = $(this).attr('data-itemid');
		
		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze',
			action: 'unlinkItem',
			queryString: 'analysisid=' + analysisId + '&itemid=' + itemId,
			success: function (params) {
				if ( params.isUnlinked == 1 ) {
					$('#' + params.analysisId).find('.analyze-item-link[data-itemid="' + params.itemId + '"]').remove();
				} else {
					alert(params.message);
				}
			}
		});
	});
	
});


function getAnalyzeItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		if ( $('#analyze-status').val() == '' || $('#analyze-status').val().toLowerCase() == params.status.toLowerCase() ) {
			$('#analyze-content-heading').after( params.itemHtml );
		}
	} else {
		$('#' + params.analysisId).html( params.itemHtml );
		
		$('.item-arrow:visible').hide();
		$('#' + params.analysisId + ' .item-arrow').show();						
	}
}

function setOwnershipCallback ( params ) {
	
	if ( params.message ) {
		alert( params.message )
		
	} else if ( params.ownershipSet == 1 ) {

		var ownershipButton = $('img[data-analysisidownership="' + params.analysisId + '"]');
		if ( ownershipButton.hasClass('analyze-item-has-no-owner') || ownershipButton.hasClass('analyze-item-is-not-owner') ) {
			ownershipButton
				.attr({
					'src': $.main.webroot + '/images/icon_user_green.png',
					'title': 'you are owner'
				})
				.removeClass('analyze-item-has-no-owner analyze-item-is-not-owner')
				.addClass('analyze-item-is-owner');
		} else {
			ownershipButton
				.attr({
					'src': $.main.webroot + '/images/icon_user_grey.png',
					'title': 'has no owner'
				})
				.removeClass('analyze-item-is-owner')
				.addClass('analyze-item-has-no-owner');
		}		

	} else if ( params.owner == '' || params.userIsOwner == 1 ) {
		
		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze',
			action: 'setOwnership',
			queryString: 'id=' + params.analysisId + '&userIsOwner=' + params.userIsOwner,
			success: setOwnershipCallback
		}, true);		
		
	} else {
		if ( confirm(params.owner + ' is currently owner of this analysis. \nDo you wish to take ownership of this analysis?') ) {
			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze',
				action: 'setOwnership',
				queryString: 'id=' + params.analysisId + '&userIsOwner=0',
				success: setOwnershipCallback
			}, true);
		}
	}
}
