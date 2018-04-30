/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// filter/search analysis
	$('#filters').on('click', '#btn-analyze-search', function (event, origin) {
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		
		if ( $("input:checkbox:checked[name='rating']").length > 0) {
			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze',
				action: 'searchAnalyze',
				queryString: $('#form-analyze-standard-search').serializeWithSpaces(),
				success: 'getTagsForAnalyzePage'
			});
		} else {
			alert("At least one option in the searchbar must be checked to perform search.");
		}
	});
	
	// filter/search analysis by pressing enter in searchfield
	$('#filters').on('keypress', '#analyze-search', function (event) {
	   if ( !checkEnter(event) ) {
		   event.preventDefault();
		   $('#btn-analyze-search').trigger('click', 'searchOnEnter');
	   }
	});
	
	// show join analyses dialog
	$('#content-wrapper').on('click', '.btn-analyze-join', function () {
		
		if ( $('.analyze-item-select-input:checked').length < 2 ) {
		    alert ("You need to check at least 2 analyses!");			
		} else {

			var lastSelectedItemId;
			var queryString = '';
			$('.analyze-item-select-input:checked').each( function (i) {
				queryString += '&id=' + $(this).val();
				lastSelectedItemId = $(this).val();
			});	
			
			$('.item-arrow:visible').hide();
			$('#' + lastSelectedItemId + ' .item-arrow').show();						
			
			var dialog = $('<div>').newDialog();
			dialog.html('<fieldset>loading...</fieldset>');

			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze_join',
				action: 'openDialogAnalyzeJoin',
				queryString: queryString,
				success: openDialogAnalyzeJoinCallback
			});				
			
			dialog.dialog('option', 'title', 'Join Analyses');
			dialog.dialog('option', 'width', '800px');
			dialog.dialog({
				buttons: {
					'Close': function () {
						$(this).dialog( 'close' );
					}
				}
			});
	
			dialog.dialog('open');
		}		
	});
	
	// enable/disable title selection in Join Analysis dialog
	// $.main.activeDialog
	$('#dialog').on('keyup', '#analyze-join-new-title', function () {
		if ( $(this).val() != '' ) {
			$('#analyze-join-existing-title').prop('disabled', true);
		} else {
			$('#analyze-join-existing-title').prop('disabled', false);
		}
	});
	
	// create a new analysis
	$('#content-wrapper').on('click', '.btn-analyze-new', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze_details',
			action: 'openDialogNewAnalysis',
			success: openDialogNewAnalysis
		});
		
		dialog.dialog('option', 'title', 'Create new analysis');
		dialog.dialog('option', 'width', '700px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
		
	});
	
	//click on button 'show all descriptions'
	$('#content-wrapper').on('click', '.btn-analyze-show-hide-descriptions', function () {
		if ( $(this).attr('data-status') == 'hide' ) {
			$('.btn-analyze-show-hide-descriptions').each( function () {
				$(this).attr('data-status', 'show');
				$(this).val('Hide all comments');
			});
			$('.analyze-item-details-description').show();
			$('.btn-toggle-description').text('hide comments')
		} else {
			$('.btn-analyze-show-hide-descriptions').each( function () {
				$(this).attr('data-status', 'hide');
				$(this).val('Show all comments');
			});
			$('.analyze-item-details-description').hide();
			$('.btn-toggle-description').text('show comments')
		}
	});
	
	// click on button 'Reset filter and search'
	$('#filters').on('click', '#btn-analyze-default-search', function () {
		if ( $('#analyze-status option:selected').val() != '' ) {
			$('#analyze-status option:selected').prop('selected', false);
			$('#analyze-status option[value=""]').prop('selected', true);
		}

		$('#analyze-search').val('');
		$('#analyze-rating-low, #analyze-rating-medium, #analyze-rating-high, #analyze-rating-undefined').prop('checked', true);

		$('#btn-analyze-search').trigger('click');
	});
	
});

function openDialogAnalyzeJoinCallback ( params ) {

	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Join',
			click: function () {

				// Que ?
				if ( $('#analyze-join-new-title').val() != '' ) {
					$('#analyze-join-new-title').val( $('#analyze-join-new-title').val() );	
				}
				
				$.main.ajaxRequest({
					modName: 'analyze',
					pageName: 'analyze_join',
					action: 'joinAnalysis',
					queryString: $('#form-analyze-join').serializeWithSpaces(),
					success: joinAnalysisCallback
				});				
				
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}		
	]);
}

function joinAnalysisCallback ( params ) {

	if ( params.analysisJoined == 1 ) {
		
		if ( $('#analyze-status').val() == '' || $('#analyze-status').val().toLowerCase() == 'joined' ) {
			$.each( params.ids, function ( i, id ) {
				$('#' + id + ' .span-analyze-item-status').text('(Joined)');
			});
		} else {
			$.each( params.ids, function ( i, id ) {
				$('#' + id).remove();
			});
		}
		
		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze',
			action: 'getAnalyzeItemHtml',
			queryString: 'insertNew=1&id=' + params.newAnalysisId,
			success: getAnalyzeItemHtmlCallback
		});			
		
		$.main.activeDialog.dialog('close');
	
	} else {
		alert( params.message );
	}

}

function openDialogNewAnalysis ( params ) {
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Save new analysis',
			click: function () {

				if ($('#analyze-details-add-comment').val() != '') {
					alert ("Please add your comment or leave the 'add comment' area blank!");
//TODO: dit moet gebeuren bij het bewerken van een bestaande analysis.					
//				} else if ( ( document.analysis.original_status.value != document.analysis.status.value ) && (document.analysis.added_comments.value == "no" ) ) {
//					    alert ("Please specify a reason for status change from '" + document.analysis.original_status.value + "' to '" + document.analysis.status.value + "' by adding a comment!");
				} else if ( $('#analyze-details-title').val() == '' ) {
					alert ("Please specify a title.");				
				} else {

					$.main.ajaxRequest({
						modName: 'analyze',
						pageName: 'analyze_details',
						action: 'saveNewAnalysis',
						queryString: $('#analyze-details-form').serializeWithSpaces(),
						success: saveNewAnalysisCallback
					});						
				}
			}
		},
		{
	    	text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
	
	$('#analyze-details-title').focus();
}

function saveNewAnalysisCallback ( params ) {
	if ( params.analysisIsAdded == 1 ) {
		
		if ( params.tagsAreSaved == 1 ) {

			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze',
				action: 'getAnalyzeItemHtml',
				queryString: 'insertNew=1&id=' + params.id,
				success: getAnalyzeItemHtmlCallback
			});				
			
			$.main.activeDialog.dialog('close');			
		} else {
		
			$.main.activeDialog.dialog('option', 'buttons', [
				{
					text: 'Close',
					click: function () { $(this).dialog('close') }
				}
			]);			
			alert( params.message );
		}
		
	} else {
		alert( params.message );
	}
}
