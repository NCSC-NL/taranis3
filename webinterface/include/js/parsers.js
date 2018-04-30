/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view parser details
	$('#content').on( 'click', '.btn-edit-parser, .btn-view-parser', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'parsers',
			action: 'openDialogParserDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogParserDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Parser details');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a parser
	$('#content').on( 'click', '.btn-delete-parser', function () {
		if ( confirm('Are you sure you want to delete the parser?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'parsers',
				action: 'deleteParser',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteParserItemCallback
			});		
		}		
	});

	// add a new parser
	$('#filters').on( 'click', '#btn-add-parser', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'parsers',
			action: 'openDialogNewParser',
			success: openDialogNewParserCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new parser');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// search parsers
	$('#filters').on('click', '#btn-parsers-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'parsers',
			action: 'searchParsers',
			queryString: $('#form-parsers-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do parser search on ENTER
	$('#filters').on('keypress', '#parsers-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-parsers-search').trigger('click');
		}
	});
	
});


function openDialogNewParserCallback ( params ) {
	var context = $('#parsers-details-form[data-id="NEW"]');
	$('#parsers-details-tabs', context).newTabs();

	if ( params.writeRight == 1 ) {
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#parsers-details-parsername", context).val() == "") {
						alert("Please specify a name for the parser.");
					} else if ( $("#parsers-details-item-start", context).val() == "" || $("#parsers-details-item-end", context).val() == "") {
						alert("Please specify both item start and end tags.");
					} else if ( $("#parsers-details-title-start", context).val() == "" || $("#parsers-details-title-end", context).val() == "") {
						alert("Please specify both title start and end tags.");
					} else if ( $("#parsers-details-link-start", context).val() == "" || $("#parsers-details-link-end", context).val() == "") {
						alert("Please specify both link start and end tags.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'parsers',
							action: 'saveNewParser',
							queryString: $(context).serializeWithSpaces(),
							success: saveParserCallback
						});					
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
	}
}

function openDialogParserDetailsCallback ( params ) {
	var context = $('#parsers-details-form[data-id="' + params.id + '"]');
	$('#parsers-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) {
	
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});	
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#parsers-details-item-start", context).val() == "" || $("#parsers-details-item-end", context).val() == "") {
						alert("Please specify both item start and end tags.");
					} else if ( $("#parsers-details-title-start", context).val() == "" || $("#parsers-details-title-end", context).val() == "") {
						alert("Please specify both title start and end tags.");
					} else if ( $("#parsers-details-link-start", context).val() == "" || $("#parsers-details-link-end", context).val() == "") {
						alert("Please specify both link start and end tags.");
					} else {
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'parsers',
							action: 'saveParserDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveParserCallback
						});
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveParserCallback ( params ) {
	
	if ( params.saveOk ) {
	
		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'parsers',
			action: 'getParserItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function deleteParserItemCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		$('#' + params.id.replace(/%/g, '\\%') ).remove();
	} else {
		alert(params.message);
	}
}
