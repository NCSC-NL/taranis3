/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view tool details
	$('#content').on( 'click', '.btn-edit-tool, .btn-view-tool', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'tools',
			action: 'openDialogToolDetails',
			queryString: 'toolname=' + encodeURIComponent( $(this).attr('data-toolname') ),				
			success: openDialogToolDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Tool details');
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
	
	// delete tool
	$('#content').on( 'click', '.btn-delete-tool', function () {
		if ( confirm('Are you sure you want to delete this tool?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'tools',
				action: 'deleteTool',
				queryString: 'toolname=' + encodeURIComponent( $(this).attr('data-toolname') ),				
				success: deleteToolCallback
			});		
		}		
	});
	
	// add a new tool
	$('#filters').on( 'click', '#btn-add-tool', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'tools',
			action: 'openDialogNewTool',
			success: openDialogNewToolCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new tool');
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
	
});


function openDialogNewToolCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-tools[data-toolname="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $.trim( $("#tool-toolname", context).val() ) == "" ) {
						alert("Please specify a name for the tool.");
					} else if ( $.trim( $("#tool-webscript", context).val() ) == "" ) {
						alert("Please specify the webscript setting.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'tools',
							action: 'saveNewTool',
							queryString: $('#form-tools[data-toolname="NEW"]').serializeWithSpaces(),
							success: saveNewToolCallback
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

function openDialogToolDetailsCallback ( params ) {
	var context = $('#form-tools[data-toolname="' + params.toolname + '"]');
	
	if ( params.writeRight == 1 ) { 
	
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $.trim( $("#tool-toolname", context).val() ) == "" ) {
						alert("Please specify a name for the tool.");
					} else if ( $.trim( $("#tool-webscript", context).val() ) == "" ) {
						alert("Please specify the webscript setting.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'tools',
							action: 'saveToolDetails',
							queryString: $(context).serializeWithSpaces() + '&orig_toolname=' + encodeURIComponent( params.toolname ),
							success: saveToolDetailsCallback
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

function saveNewToolCallback ( params ) {
	
	if ( params.saveOk ) {
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'tools',
			action: 'getToolItemHtml',
			queryString: 'insertNew=1&toolname=' + encodeURIComponent( params.toolname ),
			success: getToolItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function saveToolDetailsCallback ( params ) {
	if ( params.saveOk ) {
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'tools',
			action: 'getToolItemHtml',
			queryString: 'orig_toolname=' + encodeURIComponent( params.originalToolname ) + '&toolname=' + encodeURIComponent( params.toolname ),
			success: getToolItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function getToolItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('#tools-content-heading').after( params.itemHtml );
	} else {
		var toolnameIdentifier = encodeURIComponent( params.originalToolname );
		toolnameIdentifier = toolnameIdentifier.replace( /%/g, '\\%' )
		toolnameIdentifier = toolnameIdentifier.replace( /\./g, '\\.' )
		toolnameIdentifier = toolnameIdentifier.replace( /\:/g, '\\:' )
		
		$('#' + toolnameIdentifier )
			.html( params.itemHtml )
			.attr('id', encodeURIComponent( params.toolname ) );
	}
}

function deleteToolCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		var toolnameIdentifier = encodeURIComponent( params.toolname );
		toolnameIdentifier = toolnameIdentifier.replace( /%/g, '\\%' );
		toolnameIdentifier = toolnameIdentifier.replace( /\./g, '\\.' );
		toolnameIdentifier = toolnameIdentifier.replace( /\:/g, '\\\:' );

		$('#' + toolnameIdentifier ).remove();
	} else {
		alert(params.message);
	}
}
