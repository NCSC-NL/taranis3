/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogAnalysisToPublicationCallback ( params ) {
	var context = 'fieldset[data-analysisid="' + params.id + '"]';
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Create',
			click: function () {
				var analysisToPublicationAction = null,
					analysisToPublicationCallback = null,
					analysisToPublicationPage = null,
					queryString = 'analysisId=' + params.id;
				var action = $('input[name="analysis-to-publication-action"]:checked', context).val();
console.log("pub "+action);
				switch (action) {
					case 'advisory':
						analysisToPublicationAction = 'openDialogNewAdvisory';
						analysisToPublicationCallback = 'openDialogNewAdvisoryCallback';
						analysisToPublicationPage = 'advisory';
						break;
					case 'advisory_update':
						analysisToPublicationAction = 'openDialogAnalysisToPublicationUpdate';
						analysisToPublicationCallback = 'openDialogAnalysisToPublicationUpdateCallback';
						analysisToPublicationPage = 'analysis2publication';
						queryString += '&pubclicationType=advisory';
						break;
					case 'advisory_import':
						analysisToPublicationAction = 'openDialogImportAdvisory';
						analysisToPublicationCallback = 'openDialogImportAdvisoryCallback';
						analysisToPublicationPage = 'advisory';
						queryString += '&emailItemId=' + $('#analysis-to-publication-import-source', context).val();
						break;
					case 'forward':
						analysisToPublicationAction = 'openDialogNewForward';
						analysisToPublicationCallback = 'openDialogNewForwardCallback';
						analysisToPublicationPage = 'forward';
						break;
					case 'forward_update':
						analysisToPublicationAction = 'openDialogAnalysisToPublicationUpdate';
						analysisToPublicationCallback = 'openDialogAnalysisToPublicationUpdateCallback';
						analysisToPublicationPage = 'analysis2publication';
						queryString += '&pubclicationType=forward';
						break;
					case 'advisory_link':
						var advisoryId = $('#link-analysis-to-advisory').val();
						if(advisoryId == undefined) {
							alert('Select an existing advisory.');
							return false;
						}
						queryString += '&advisoryId=' + advisoryId;

						var $take = $('input[type="checkbox"][name="link-item"]:checked');
						if($take.length==0) {
							alert('At least one news item must be taken');
							return false;
						}

						queryString += '&newsitems=' + $take
						   .map(function() {return this.value}).get().join(',');

						analysisToPublicationPage = 'advisory';
						analysisToPublicationAction = 'saveAdvisoryLateLinks';
						analysisToPublicationCallback = function () {
							$("div.item-row.analyze-item#"+advisoryId).hide();
							$.main.activeDialog.dialog('close');
						};
						break;
					default:
						alert('Unimplemented action: '+action);
				}

				$.main.ajaxRequest({
					modName: 'write',
					pageName: analysisToPublicationPage,
					action: analysisToPublicationAction,
					queryString: queryString,
					success: analysisToPublicationCallback
				});

				if(action != 'advisory_link') {
					$.main.activeDialog.html('<fieldset>loading...</fieldset>');
				}
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);

	$('input[name="analysis-to-publication-action"]').on('click', function() {
		var action = this.value;
		$('#analysis-to-publication-import-settings', context).hide();
		$('#analysis-to-publication-link', context).hide();

   		if(action == 'advisory_import') {
			$('#analysis-to-publication-import-settings', context).show();
		}
		if(action == 'advisory_link') {
			$('#analysis-to-publication-link', context).show();
		}
	});

    // search publications
    $('#btn-link-to-publication-search').click( function () {
        var search = encodeURIComponent( $('#link-to-publication-search').val() );

        $.main.ajaxRequest({
            modName: 'write',
            pageName: 'analysis2publication',
            action: 'searchPublicationsAnalysisToPublication',
            queryString: 'search=' + search + '&publicationtype=advisory' + '&id=' + params.id + '&include_open=1',
            success: searchPublicationsLinkToPublicationCallback
        });
    });

    // search publications when pressing enter
    $('#link-to-publication-search').keyup( function(e) {
        if ( e.keyCode == 13 ) {
            $('#btn-link-to-publication-search').trigger('click');
        }
        e.preventDefault();
        return false;
    });

	$('input[name="analysis-to-publication-action"][value="advisory"]')
		.click();
}

function openDialogAnalysisToPublicationUpdateCallback ( params ) {
	var tabsContext = 'div[id="analysis-to-publication-tabs"][data-analysisid="' + params.id + '"]';
	
	// init tabs
 	$(tabsContext).tabs({
 		select: function (event,ui) {
 			if ( $(ui.tab).attr('href') == '#analysis-to-publication-tabs-2' ) {
 				$('#analysis-to-publication-search-results').triggerHandler('change');
 			} else {
 				$('#analysis-to-publication-publication-id-match').triggerHandler('change');
 			}
 		}
 	});
	
	// change existing dialog width
	$.main.activeDialog.dialog('option', 'width', '700px');
	
	// add dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Create',
			click: function () {
				var analysisToPublicationAction = null,
					analysisToPublicationCallback = null,
					analysisToPublicationPage = null,
					queryString = 'analysisId=' + params.id;
				
				switch ( $(tabsContext).attr('data-publicationtype') ) {
					case 'advisory':
						analysisToPublicationAction = 'openDialogUpdateAdvisory';
						analysisToPublicationCallback = 'openDialogUpdateAdvisoryCallback';
						analysisToPublicationPage = 'advisory';
						break;
					case 'forward':
						analysisToPublicationAction = 'openDialogUpdateForward';
						analysisToPublicationCallback = 'openDialogUpdateForwardCallback';
						analysisToPublicationPage = 'forward';
						break;
					default:
						alert('No can do');
				}
				
				$.main.ajaxRequest({
					modName: 'write',
					pageName: analysisToPublicationPage,
					action: analysisToPublicationAction,
					queryString: 'id=' + $.main.activeDialog.find('.analysis-to-publication-select:visible').val() + '&analysisId=' + params.id,
					success: analysisToPublicationCallback
				});
				
				$.main.activeDialog.html('<fieldset>loading...</fieldset>');
			}
		},
		{
			text: 'Preview publication',
			click: function () {
				
				var pubType = $(tabsContext).attr('data-publicationtype');

				var action = 'openDialogPreview' + pubType.charAt(0).toUpperCase() + pubType.slice(1);
				
				var dialog = $('<div>').newDialog();
				dialog.html('<fieldset>loading...</fieldset>');

				$.main.ajaxRequest({
					modName: 'write',
					pageName: pubType,
					action: action,
					queryString: 'id=' + $.main.activeDialog.find('.analysis-to-publication-select:visible').val() + '&pubType=' + pubType,
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
			}
		},	
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]); 	
 	
	// search publications
	$('#btn-analysis-to-publication-search', tabsContext).click( function () {

		var search = encodeURIComponent( $('#analysis-to-publication-search', tabsContext).val() );

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'analysis2publication',
			action: 'searchPublicationsAnalysisToPublication',
			queryString: 'search=' + search + '&publicationtype=' + $(tabsContext).attr('data-publicationtype') + '&id=' + params.id,
			success: searchPublicationsAnalysisToPublicationCallback
		});
	});

	// search publications when pressing enter
	$('#analysis-to-publication-search', tabsContext).keyup( function(e) {
		if ( e.keyCode == 13 ) {
			$('#btn-analysis-to-publication-search', tabsContext).trigger('click');
		}
		e.preventDefault();
		return false;
	});

	// enable/disable buttons 'Create' and 'Preview publication' depending on wether a publication is selected
	$('#analysis-to-publication-publication-id-match, #analysis-to-publication-search-results', tabsContext).change( function () {
		if ( $(this).val() == null ) {
			$(":button:contains('Create')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');

			$(":button:contains('Preview publication')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');
		} else {
			$(":button:contains('Create')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
				
			$(":button:contains('Preview publication')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}
	});
 
 	$('#analysis-to-publication-publication-id-match', tabsContext).triggerHandler('change');	
}

function searchPublicationsAnalysisToPublicationCallback ( params ) {
	if ( params.message ) {
		alert( params.message );
	} else {
		var context = 'div[id="analysis-to-publication-tabs"][data-analysisid="' + params.id + '"]';
		
		// remove old results
		$('#analysis-to-publication-search-results option', context).each( function () {
			$(this).remove();
		});
		
		// add new results
		$.each( params.publications, function () {
			$('<option />')
				.val( this.publication_id )
				.text( this.named_id + " [v" + this.version + "] " + this.publication_title )
				.appendTo('#analysis-to-publication-search-results');
		});
		
		$('#analysis-to-publication-search-results').triggerHandler('change');
	}
}

function searchPublicationsLinkToPublicationCallback(params) {
	if ( params.message ) {
		alert( params.message );
	} else {
		$('#link-analysis-to-advisory option').not('.link-advisory-match').remove();
		$.each( params.publications, function () {
			$('<option />')
			.val( this.publication_id )
			.text( this.named_id + " [v" + this.version + "] " + this.publication_title )
			.appendTo('#link-analysis-to-advisory');
		});
		
		$('#link-to-publication-search-results').triggerHandler('change');
	}
}
