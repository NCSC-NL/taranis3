/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view strips details
	$('#content').on( 'click', '.btn-edit-strips, .btn-view-strips', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'strips',
			action: 'openDialogStripsDetails',
			queryString: 'id=' + encodeURIComponent( $(this).attr('data-id') ),				
			success: openDialogStripsDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Strips details');
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
	
	// delete strips
	$('#content').on( 'click', '.btn-delete-strips', function () {
		if ( confirm('Are you sure you want to delete these strips?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'strips',
				action: 'deleteStrips',
				queryString: 'id=' + encodeURIComponent( $(this).attr('data-id') ),				
				success: deleteStripsCallback
			});		
		}		
	});
	
	// add a new strips
	$('#filters').on( 'click', '#btn-add-strips', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'strips',
			action: 'openDialogNewStrips',
			success: openDialogNewStripsCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new strips');
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

	// search strips
	$('#filters').on('click', '#btn-strips-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'strips',
			action: 'searchStrips',
			queryString: $('#form-strips-search').serializeWithSpaces(),
			success: null
		});
	});	
	
	// do strips search on ENTER
	$('#filters').on('keypress', '#strips-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-strips-search').trigger('click');
		}
	});	
	
});


function openDialogNewStripsCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-strips[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $.trim( $("#strips-details-hostname", context).val() ) == "" ) {
						alert("Please specify the hostname.");
					} else if ( $.trim( $("#strips-details-strip0", context).val() ) == "" ) {
						alert("Please specify strip0.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'strips',
							action: 'saveNewStrips',
							queryString: $('#form-strips[data-id="NEW"]').serializeWithSpaces(),
							success: saveNewStripsCallback
						});					
					}
				}
		    },
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});
	}
}

function openDialogStripsDetailsCallback ( params ) {
	var context = $('#form-strips[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $.trim( $("#strips-details-hostname", context).val() ) == "" ) {
						alert("Please specify the hostname.");
					} else if ( $.trim( $("#strips-details-strip0", context).val() ) == "" ) {
						alert("Please specify strip0.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'strips',
							action: 'saveStripsDetails',
							queryString: $(context).serializeWithSpaces() + '&originalId=' + encodeURIComponent( params.id),
							success: saveStripsDetailsCallback
						});
					}
				}
		    },
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});
		
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveNewStripsCallback ( params ) {
	
	if ( params.saveOk ) {
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'strips',
			action: 'getStripsItemHtml',
			queryString: 'insertNew=1&id=' + encodeURIComponent( params.id ),
			success: getStripsItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function saveStripsDetailsCallback ( params ) {
	if ( params.saveOk ) {
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'strips',
			action: 'getStripsItemHtml',
			queryString: 'originalId=' + encodeURIComponent( params.originalId) + '&id=' + encodeURIComponent( params.id ),
			success: getStripsItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function getStripsItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('#strips-content-heading').after( params.itemHtml );
	} else {
		var stripsIdentifier = encodeURIComponent( params.originalId );
		stripsIdentifier = stripsIdentifier.replace( /%/g, '\\%' )
		stripsIdentifier = stripsIdentifier.replace( /\./g, '\\.' )
		stripsIdentifier = stripsIdentifier.replace( /\:/g, '\\:' )
		
		$('#' + stripsIdentifier )
			.html( params.itemHtml )
			.attr('id', encodeURIComponent( params.id ) );
	}
}

function deleteStripsCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		var stripsIdentifier = encodeURIComponent( params.id );
		stripsIdentifier = stripsIdentifier.replace( /%/g, '\\%' );
		stripsIdentifier = stripsIdentifier.replace( /\./g, '\\.' );
		stripsIdentifier = stripsIdentifier.replace( /\:/g, '\\\:' );

		$('#' + stripsIdentifier ).remove();
	} else {
		alert(params.message);
	}
}
