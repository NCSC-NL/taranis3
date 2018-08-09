/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function displayAssessAnalysisCallback ( params ) {
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Create analysis',
			click: function () {
				
				var clusterItemIds = ''
				if ( $('input[id^="include-clustered-items"]').length > 0  ) {
					
					var clusterId = $('div[id="' + $('#assess-analyze-item-tabs').attr('data-itemdigest') + '"]').attr('data-clusterid');
					$('.item-cluster-row[data-clusterid="' + clusterId + '"]').each( function (index) {
						clusterItemIds += '&clusterItemId='	+ $(this).attr('id');
					});
				}

				$.main.ajaxRequest({
					modName: 'analyze',
					pageName: 'assess2analyze',
					action: 'createAssessAnalysis',
					queryString: $('#analyze-item-form-new-analysis').serializeWithSpaces() + clusterItemIds,
					success: createOrLinkAssessAnalysisCallback
				});
			}
		},
		{
			text: 'Link to Analysis',
			click: function () {

				var tabSelected = $.main.activeDialog.find('form:visible').attr('id').replace(/(analyze-item-link-analysis-.*?)-form/, '$1');
				if ( $('#' + tabSelected + '-analysis option:selected').length > 0 ) {

					var clusterItemIds = ''
					if ( $('input[id^="include-clustered-items"]').length > 0  ) {
					
						var clusterId = $('div[id="' + $('#assess-analyze-item-tabs').attr('data-itemdigest') + '"]').attr('data-clusterid');
						$('.item-cluster-row[data-clusterid="' + clusterId + '"]').each( function (index) {
							clusterItemIds += '&clusterItemId='	+ $(this).attr('id');
						});
					}				
				
					$.main.ajaxRequest({
						modName: 'analyze',
						pageName: 'assess2analyze',
						action: 'linkAssessAnalysis',
						queryString: $.main.activeDialog.find('form:visible').serializeWithSpaces() + clusterItemIds,
						success: createOrLinkAssessAnalysisCallback
					});				
				} else {
					alert('Please select an analysis to link to.');
				}
			}
		},
		{
			text: 'Preview selected analysis',
			click: function () {
				
				var tabSelected = $.main.activeDialog.find('form:visible').attr('id').replace(/(analyze-item-link-analysis-.*?)-form/, '$1');

				if ( $('#' + tabSelected + '-analysis option:selected').length > 0 ) {
					
					dialog = $('<div>').newDialog();
					dialog.html('<fieldset>loading...</fieldset>');

					$.main.ajaxRequest({
						modName: 'analyze',
						pageName: 'analyze_details',
						action: 'openDialogAnalyzeDetails',
						queryString: 'id=' + $('#' + tabSelected + '-analysis').val(),
						success: openDialogAnalyzeDetailsCallback
					});				
					
					dialog.dialog('option', 'title', 'Analysis details');
					dialog.dialog('option', 'width', '890px');
					dialog.dialog({
						buttons: {
							'Cancel': function () {
								$(this).dialog( 'close' );
							}
						}
					});

					dialog.dialog('open');
					
				} else {
					alert('Please select an analysis to preview.');
				}
			}
		},
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}		
	]);
	
	// init tabs
	$('#assess-analyze-item-tabs').newTabs({selected: 0});	
	
	// show/hide buttons depending on which tab is active
	$('#tab-new-analysis').click( function () {
		$(":button:contains('Link to Analysis')").hide();
		$(":button:contains('Preview selected analysis')").hide();
		$(":button:contains('Create analysis')").show();
	});

	// show/hide buttons depending on which tab is active	
	$('a[id^="tab-link-analysis"]').click( function () {
		$(":button:contains('Link to Analysis')").show();
		$(":button:contains('Preview selected analysis')").show();
		$(":button:contains('Create analysis')").hide();
	});
	
	$('#tab-new-analysis').trigger('click');
		
	// adding comments to the new analysis (tab 'Create new analysis')
	$('#btn-analyze-item-new-analysis-add-comment').click( function () {

		var newLine;
		var curDateTime = new Date();

		if ( $('#analyze-item-new-analysis-comments').val() == '' ) {
			newLine = "";
		} else {
			newLine = "\n\n";
		}
	  
		$('#analyze-item-new-analysis-comments').val( $('#analyze-item-new-analysis-comments').val() + newLine + "[== " + $.main.fullname + " (" + curDateTime.toLocaleString() + ") ==]\n" + $('#analyze-item-new-analysis-add-comment').val() );
		$('#analyze-item-new-analysis-add-comment').val('');
	});

	// when selecting an analysis in one of the tabs display settings like 'Title', 'Status' and 'Link' should change
	$('select[id^="analyze-item-link-analysis"]').change( function () {
		var tabSelected = $(this).attr('id').replace(/(analyze-item-link-analysis-.*?)-analysis/, '$1');
 
		var title = $(this).children('option:selected').text();
		title = title.substr( 14 );
		
		var status = 'pending';
		
		if ( tabSelected != 'analyze-item-link-analysis-pending' ) {
			status = title.match( /.*\((.*?)\)$/ )[1];
			title = title.replace( /\(.*?\)$/, '' );
		}

		$('#' + tabSelected + '-title').val( title );
		$("#" + tabSelected + "-status option:selected").prop('selected', false);
		$("#" + tabSelected + "-status > option[value='" + status + "']").prop('selected', true);
		
	});

	// search for analysis
	$('#btn-analyze-item-link-analysis-search').click( function () {
		
		var digest = $('#analyze-item-form-link-analysis-search input[name="digest"]').val();
		var search = encodeURIComponent( $('#analyze-item-link-analysis-search-input').val() );
		
		$('#analyze-item-link-analysis-search-analysis').html('');
		
		var queryString = 'status=' + $('#select-analyze-item-link-analysis-search-search-status').val() 
			+ '&digest=' + digest 
			+ '&search=' + search;
		
		$.main.ajaxRequest({
			modName: 'analyze',
			pageName: 'assess2analyze',
			action: 'searchAssessAnalysis',
			queryString: queryString,
			success: searchAssessAnalysisCallback
		});		
	});
	
	// trigger analysis search when pressing enter in search input field
	$('#analyze-item-link-analysis-search-input').keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-analyze-item-link-analysis-search').trigger('click');
		}
	});
	
}

function createOrLinkAssessAnalysisCallback ( params ) {
	if ( params.analysis_is_linked == 1 ) {
		
		if ( $('#assess-menu').hasClass('selected-menu') ) {
		
			// set item visualy to status 'waitingroom'
			$('div[id="' + params.itemDigest + '"] .assess-item-title, div[id="' + params.itemDigest + '"] .assess-item-title')
				.addClass('assess-waitingroom')
				.removeClass('assess-unread assess-read assess-important');
			
			// if waitingroom in the filter is unchecked, hide the item
			if ( $('#waitingroom').is(':checked') == false ) {
				$('div[id="' + params.itemDigest + '"]').fadeOut('slow');
			}
			
			$.each( params.updateItems, function(i,id) {
				id = encodeURIComponent( id );
				if ( $('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').hasClass('assess-waitingroom') == false ) {
					// set item visualy to status 'read' or 'waitingroom'
					$('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').removeClass('assess-unread assess-read assess-important');
					$('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').addClass('assess-' + params.updateItemsStatus);
				}			
			});				
			
		} else if ( $('#analyze-menu').hasClass('selected-menu') ) {
			
			if ( 'analysisUnlinkId' in params && params.analysisUnlinkId != undefined ) {
				var unlinkedItemSpan = $('#' + params.analysisUnlinkId).find('span[data-linkdigest="' + params.itemDigest + '"]');
				unlinkedItemSpan.remove();
			}
			
			if ( 'analysisId' in params ) {
				$.main.ajaxRequest({
					modName: 'analyze',
					pageName: 'analyze',
					action: 'getAnalyzeItemHtml',
					queryString: 'insertNew=1&id=' + params.analysisId,
					success: getAnalyzeItemHtmlCallback
				});
			}
			
			if ( 'linkToAnalysis' in params && params.linkToAnalysis != undefined ) {
				$.main.ajaxRequest({
					modName: 'analyze',
					pageName: 'analyze',
					action: 'getAnalyzeItemHtml',
					queryString: 'insertNew=0&id=' + params.linkToAnalysis,
					success: getAnalyzeItemHtmlCallback
				});
			}
			
		}
		
		$.main.activeDialog.dialog('close');
		
	} else {
		$('#dialog-error')
			.text( params.message )
			.show();
	}
}

function searchAssessAnalysisCallback ( params ) {

	$.each( params.analysis, function (i, a) {
		var optionText = 'AN-' + String(a.id).substr(0,4) + '-' + String(a.id).substr(4,4) + ': ' + a.title + ' (' + a.status.toLowerCase() + ')';
		
		$('<option>')
			.html(optionText)
			.val(a.id)
			.appendTo('#analyze-item-link-analysis-search-analysis');
	});
	
}
