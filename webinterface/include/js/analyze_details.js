/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogAnalyzeDetailsCallback ( params ) {
	
	var tabsContext = 'div[id="analyze-details-tabs"][data-analysisid="' + params.id + '"]';
	var analyzeDetailsForm = 'form[id="analyze-details-form"][data-analysisid="' + params.id + '"]';
 	$(tabsContext).newTabs();

 	if ( params.isLocked == 1 || params.isJoined == 1 ) {
		$('input, select, textarea', analyzeDetailsForm).each( function (index) {
			$(this).prop('disabled', true);
		});

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);		
		
	} else {
		// if the analysis is not locked, add the save details button 
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save details',
				click: function () {

					if ( $('#analyze-details-add-comment', tabsContext).val() != '' ) {
						alert ("Please add your comment or leave the 'add comment' area blank!");
					} else if ( $('#analyze-details-title', tabsContext).val() == '' ) {
						alert ("Please specify a title.");
					} else if ( 
							( $('#original_status', tabsContext).val() != $('#analyze-details-status', tabsContext).val() ) 
							&& $('#analyze-details-comments', tabsContext).attr('data-commentsadded') == 'no' 
					) {
						alert ("Please specify a reason for changing the analysis status by adding a comment!");
					} else {
					
						$.main.ajaxRequest({
							modName: 'analyze',
							pageName: 'analyze_details',
							action: 'saveAnalyzeDetails',
							queryString: $(analyzeDetailsForm).serializeWithSpaces(),
							success: saveAnalyzeDetailsCallback
						});
					}
				}
			},
			{
				text: 'Cancel',
				click: function () {
					$('#analyze-status').val($('#analyze-details-status', analyzeDetailsForm).val())
					$(this).dialog('close')
				}
			}
		]);
	}
	
	if ( params.isLocked != 1 ) {
		
		// change close event for this dialog, so it will include clearing the opened_by of the analysis (=unlocking the analysis)
		$.main.activeDialog.bind( "dialogclose", function(event, ui) { 

			var activeDialogTabs = $(this).find('.dialog-tabs')
			
			var removeItem = ( 
						$('#analyze-details-status', analyzeDetailsForm).val() == $('#analyze-status').val()
						|| $('#analyze-status').val() == ''
					)
					? 0 : 1;
			
			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze_details',
				action: 'closeAnalysis',
				queryString: 'id=' + activeDialogTabs.attr('data-analysisid') + '&removeItem=' + removeItem,
				success: reloadItemHtml
			});			
			
			if ( $('.dialogs:visible').length == 0 ) {
				$('#screen-overlay').hide();
			}
		});
	}

    {   // Log the changes in analysis status to the comments field
        var $sel = $('#analyze-details-status', analyzeDetailsForm);
        $sel.attr("data-previous-status", $sel.val());
        $sel.change(function () {
			var new_status = $sel.val();
            var old_status = $sel.attr('data-previous-status');
            if(old_status == new_status) return;

            var $where   = $('#analyze-details-comments');
            var comments = $where.val();

            var now      = new Date();
            var header   = "[== " + $.main.fullname + " (" + now.toLocaleString() + ") "
               +  "changed status from '" + old_status + "' to '" + new_status + "' ==]\n";
            comments    += (comments == '' ? '' : "\n\n") + header;

            $where.val(comments);
            $where.data('commentsadded', 'yes');
            $sel.attr("data-previous-status", new_status);
        });
	}

	// setup metasearch on tab3
	if ( $('#analyze-details-idstring').val() != '' ) {
		$('.content-heading', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).hide();
		$('.analyze-details-tab3-searching', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).show();
		
		var queryString = $('form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]').serializeWithSpaces()
			+ '&id=' + params.id
			+ '&archive=0';
		
		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'analyze_details',
			action: 'analyzeDetailsMetaSearch',
			queryString: queryString,
			success: analyzeDetailsMetaSearchCallback
		}, true);
		
		// do search including the acrhived assess items
		$('#btn-search-assess-archive', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]').click( function () {

			var queryString = $('form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]').serializeWithSpaces()
			+ '&id=' + params.id
			+ '&archive=1';
		
			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze_details',
				action: 'analyzeDetailsMetaSearch',
				queryString: queryString,
				success: analyzeDetailsMetaSearchCallback
			});		
			
			$('fieldset .item-row', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).remove();
			$('.content-heading', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).hide();
			$('.analyze-details-tab3-searching', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).show();
			$(this).prop('disabled', true);
		});

	} else {
		$('.content-heading', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' )
			.after('<span>This analysis has no IDs.</span>');

		// remove the 'Search assess archive' button
		$('#btn-search-assess-archive', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]').remove();
	}
}

function saveAnalyzeDetailsCallback ( params ) {

	if ( params.isSaved == 1 ) {
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert( params.message );
	}
}

function analyzeDetailsMetaSearchCallback ( params ) {

	$('.content-heading', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' )
		.after(params.searchResultsHtml);
	
	$('#btn-search-assess-archive', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]')
		.prop('disabled', false)
		
	$('.content-heading', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).show();
	$('.analyze-details-tab3-searching', 'form[class="analyze-details-form-metasearch"][data-analysisid="' + params.id + '"]' ).hide();
}

function reloadItemHtml ( params ) {
	
	if ( $('.selected-submenu').attr('id') == 'analyze-submenu' ) {
		
		if ( params.removeItem == true ) {
			$('#' + params.id ).remove();
		} else {
			$.main.ajaxRequest({
				modName: 'analyze',
				pageName: 'analyze',
				action: 'getAnalyzeItemHtml',
				queryString: 'insertNew=0&id=' + params.id,
				success: getAnalyzeItemHtmlCallback
			});
		}
	}
}
