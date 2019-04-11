/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// click on a item in the import list
	$(document).on('click', 'span[id^="span_producer_"], span[id^="span_name_"], span[id^="span_version_"]', function () {
		var sh_id = $(this).attr('id').replace( /span_.*?_(.*?)$/ , "$1");
		try {
			
			if ( sh_id != $('div[id^="div_sh_"]:visible').attr('id').replace( /div_sh_(.*?)$/ , "$1") ) {
				$('div[id^="div_sh_"]:visible').slideToggle('fast');
			}
			
		} catch (e) {}
		
		$('#div_sh_' + sh_id).slideToggle('fast');
	});

	// click on X icon of item in import list ('Discard item')
	$(document).on('click', '.btn-delete-cpe-import-item', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'import_cpe',
			action: 'deleteCPEImportItem',
			queryString: 'id=' + $(this).attr('data-id'),
			success: removeCPEImportItem
		});
	});

	// click + icon of item in import list ('Import item')
	$(document).on('click', '.btn-add-cpe-import-item, .btn-update-cpe-import-item', 'click', function () {
		var sh_id = $(this).attr('data-id');

		var deleteFlag = ( $('#setVersionToDelete').is(':checked') && $('#inp_version_' + sh_id).val() != '' ) ? '1' : '0';
		var action = ( $(this).hasClass('btn-add-cpe-import-item') ) ? 'add' : 'update';
		
		var importObject = new Object();
		importObject.producer = $('#inp_producer_' + sh_id).val();
		importObject.name = $('#inp_name_' + sh_id).val();
		importObject.version = $('#inp_version_' + sh_id).val();
		importObject.cpe_id = $('#inp_cpe_id_' + sh_id).val();
		importObject.type = $('#inp_type_' + sh_id).val();
		importObject.import_id = sh_id;
		importObject.setDelete = deleteFlag;
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'import_cpe',
			action: action + 'CPEImportItem',
			queryString: 'import=' + encodeURIComponent( JSON.stringify( importObject ) ),
			success: removeCPEImportItem
		});		

	});

	// typing in producer field
	$(document).on('keyup', 'input[id^="inp_producer_"]', function () {
		var sh_id = $(this).attr('id').replace( /inp_producer_(.*?)$/ , "$1");
		
		$('#span_producer_' + sh_id).html( $(this).val() + ' ' );
	});

	// typing in productname field
	$(document).on('keyup', 'input[id^="inp_name_"]', function () {
		var sh_id = $(this).attr('id').replace( /inp_name_(.*?)$/ , "$1");
		$('#span_name_' + sh_id).html( $(this).val() + ' ' );
	});

	// typing in version field
	$(document).on('keyup','input[id^="inp_version_"]', function () {
		var sh_id = $(this).attr('id').replace( /inp_version_(.*?)$/ , "$1");
		$('#span_version_' + sh_id).html( $(this).val() + ' ' );
	});	

	// set actions to import or discard
	$(document).on('click', '#cpe-import-list-action-import, #cpe-import-list-action-discard', function () {
		var otherSpanId = $(this).attr('id').match( /cpe-import-list-action-import/ ) ? 'cpe-import-list-action-discard' : 'cpe-import-list-action-import';

		var buttonText = ( $('#btn-cpe-import-action').val().match( /Import/ ) ) ? 'Discard' : 'Import';
		$('#btn-cpe-import-action').val( buttonText );
		
		if ( $(this).hasClass('strikethrough') ) {
			
			$(this).removeClass('strikethrough italic');
			$(this).addClass('bold');
			$('#' + otherSpanId).addClass('strikethrough italic');
			$('#' + otherSpanId).removeClass('bold');
			
		} else {
			$(this).addClass('strikethrough italic');
			$(this).removeClass('bold');
			$('#' + otherSpanId).removeClass('strikethrough italic');
			$('#' + otherSpanId).addClass('bold');
		}
	});

	// make selection of import items
	$(document).on('click', '#cpe-import-list-action-all-new, #cpe-import-list-action-all-changed, #cpe-import-list-action-all-selected', function () {
		$('.cpe-import-list-action-all-x').addClass('strikethrough italic pointer');
		$('.cpe-import-list-action-all-x').removeClass('bold');
		
		if ( $(this).hasClass('strikethrough') ) {
			$(this).removeClass('strikethrough italic pointer');
			$(this).addClass('bold');
		} else {
			$(this).addClass('strikethrough italic pointer');
			$(this).removeClass('bold');
		}
	});

	// select all import items currently in list
	$(document).on('click', '#import-cpe-select-all', function () {
		$('input[id^="chkb_"]').prop('checked', true);
	});

	// deselect all impot items currently in list
	$(document).on('click', '#import-cpe-select-none', function () {
		$('input[id^="chkb_"]').prop('checked', false);
	});

	// bulk import/discard
	$(document).on('click', '#btn-cpe-import-action', function () {

		$(this).prop('disabled', true);
		
		var action = 'bulk' + $(this).val() + 'CPEImport' ;
		var selectionOption = $('.cpe-import-list-action-all-x').not('.strikethrough').attr( 'id' ).replace( /.*?all-(.*?)/, "$1");

		var deleteFlag = ( $('#setVersionToDelete').is(':checked') ) ? '1' : '0';
		var arrSelection = new Array();

		if ( selectionOption == 'new' ) {
			
			$('.is_new').each( function () {
				var objSelection = new Object();
				
				var sh_id = $(this).attr('id').replace( /.*?(\d+)$/ , "$1" );

				objSelection.producer = $('#inp_producer_' + sh_id).val();
				objSelection.name 		= $('#inp_name_' + sh_id).val();
				objSelection.version 	= $('#inp_version_' + sh_id).val();
				objSelection.cpe_id  	= $('#inp_cpe_id_' + sh_id).val();
				objSelection.type		= $('#inp_type_' + sh_id).val();
				objSelection.import_id = sh_id; 

				arrSelection.push( objSelection );
			});
			
		} else if ( selectionOption == 'changed' ) {

			$('.is_changed').each( function () {
				var objSelection = new Object();
				
				var sh_id = $(this).attr('id').replace( /.*?(\d+)$/ , "$1" );

				objSelection.producer = $('#inp_producer_' + sh_id).val();
				objSelection.name 		= $('#inp_name_' + sh_id).val();
				objSelection.version 	= $('#inp_version_' + sh_id).val();
				objSelection.cpe_id  	= $('#inp_cpe_id_' + sh_id).val();
				objSelection.type		= $('#inp_type_' + sh_id).val();
				objSelection.import_id = sh_id; 

				arrSelection.push( objSelection );
			});
			
		} else {

			$('input[id^="chkb_"]:checked').each( function () {
				var objSelection = new Object();
				
				var sh_id = $(this).val()

				objSelection.producer = $('#inp_producer_' + sh_id).val();
				objSelection.name 		= $('#inp_name_' + sh_id).val();
				objSelection.version 	= $('#inp_version_' + sh_id).val();
				objSelection.cpe_id  	= $('#inp_cpe_id_' + sh_id).val();
				objSelection.type		= $('#inp_type_' + sh_id).val();
				objSelection.import_id = sh_id; 

				arrSelection.push( objSelection );
			});
		}

		if ( arrSelection.length == 0 ) {
			$(this).prop('disabled', false);
			return false;
		}
		
		var jsonSelection = JSON.stringify( arrSelection );
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'import_cpe',
			action: action,
			queryString: 'setDelete=' + deleteFlag + '&selection=' + encodeURIComponent( JSON.stringify( arrSelection ) ),
			success: bulkCPEImportItemCallback
		});		

	});

	// mouseover items in import list
	$(document).on('mouseover mouseout', 'span[id^="span_producer_"], span[id^="span_name_"], span[id^="span_version_"]', function(event) {

		var sh_id = $(this).attr('id').replace( /span_(producer|name|version)_(.*?)$/ , "$2");
			
		  if (event.type == 'mouseover') {
				$('#span_producer_' + sh_id + ', #span_name_' + sh_id + ', #span_version_' + sh_id)
					.css({ 'text-decoration': 'underline' });
		  } else {
				$('#span_producer_' + sh_id + ', #span_name_' + sh_id + ', #span_version_' + sh_id)
					.css({ 'text-decoration': 'none' });
		  }
		}
	);
	
	// change option to 'set item as deleted' 
	$(document).on('change', '#cpe-import-set-version-to-delete', function () {
		if ( $(this).is(':checked') ) {
			$('#cpe-import-set-version-to-delete-block').css({'background-color': 'red', 'color': '#FFFFFF', 'font-weight': 'bold'} );
		} else {
			$('#cpe-import-set-version-to-delete-block').css({'background-color': '#FFFFFF', 'color': '#666666', 'font-weight': 'normal'} );			
		}
	});
	
	// open CPE Import dialog
	$('#filters').on('click', '#btn-import-cpe-dictionary', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'import_cpe',
			action: 'openDialogImportCPE',
			success: openDialogImportCPECallback
		});		
		
		dialog.dialog('option', 'title', 'Import CPE dictionary');
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

function openDialogImportCPECallback ( params ) {
	
	if ( params.fileImportDone == 1 ) {
		$('#cpe-import-load-file').hide();
		$('#cpe-import-process-items, #import-cpe-load-list-block').show();

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Reload list',
				click: function () {
					$(":button:contains('Reload list')")
						.prop('disabled', true)
						.addClass('ui-state-disabled');
						
					$('#cpe-import-list-table tr').remove();
					
					getEntries();	
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		getEntries();
	} else {
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Load file',
				click: function () {

					if ( $('#import-cpe-location').val() != '' ) {
						
						$(":button:contains('Load file')")
							.prop('disabled', true)
							.addClass('ui-state-disabled');
						
						$('#import-cpe-location-block, #import-cpe-option-block').hide();
						$('#import-cpe-loader-block').show();
						$('#import-cpe-load-file-result').text('(down)loading file');
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'import_cpe',
							action: 'loadCPEFile',
							queryString: 'location=' + encodeURIComponent( $('#import-cpe-location').val() ),
							success: loadCPEFileCallback
						});
						
					}
				}
			},
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);

		$('#import-cpe-location').keypress( function (event) {
			return checkEnter(event);
		});
	}
}

function getEntries () {
	$.main.ajaxRequest({
		modName: 'configuration',
		pageName: 'import_cpe',
		action: 'getCPEImportEntries',
		success: getCPEImportEntriesCallback
	});
}

function getCPEImportEntriesCallback ( params ) {
	if ( params.getEntriesOk == 1 ) {
		$('#img_ajax2, #span_ajax2').hide();
		
		if ( params.importList.length == 0 && params.leftToImport == 0 ) {
			
			$('#cpe-import-list-table, #cpe-import-list-action, #cpe-import-list-header, #cpe-import-set-version-to-delete-block').remove();
			
			$('<span />')
				.attr('id', 'span_importResult')
				.text( 'Import of CPE complete.' )
				.appendTo('#cpe-import-list');
			
			$('#cpe-import-list').show();
			
		} else if ( params.importList.length == 0 ) {

			$.main.activeDialog.dialog('option', 'buttons', [
				{
					text: 'Import rest',
					click: function () {
						$('#img_ajax2').show();
						$('#cpe-import-list').empty();
						
						$.main.activeDialog.dialog('option', 'buttons', [
							{
								text: 'Close',
								click: function () { $(this).dialog('close') }
							}
						]);
						
						$('<span />')
							.text( 'Importing rest of items, this may take a few minutes...' )
							.attr('id', 'span_importResult')
							.appendTo('#cpe-import-list');
					
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'import_cpe',
							action: 'importRest',
							success: importRestCallback
						});				
					}
				},
				{
					text: 'Clear import',
					click: function () {
					  	$('#img_ajax2').show();
						$('#cpe-import-list').empty();

						$.main.activeDialog.dialog('option', 'buttons', [
							{
								text: 'Close',
								click: function () { $(this).dialog('close') }
							}
						]);						
					
						$('<span />')
							.text( 'Clearing rest of import items...' )
							.attr('id', 'span_importResult')
							.appendTo('#cpe-import-list');		
					
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'import_cpe',
							action: 'clearImport',
							success: clearImportCallback
						});	
					}
				},
				{
					text: 'Close',
					click: function () { $(this).dialog('close') }
				}
			]);			
			
			$('#cpe-import-list-table, #cpe-import-list-action, #cpe-import-list-header, #cpe-import-set-version-to-delete-block').remove();

			$('<span />')
				.html( 'There are <span class="bold">' + params.leftToImport + '</span> items with version left to import.<br>Taranis can take items with same producer, product and type but with different versions and import them as one item without CPE ID.<br>You can also choose to clear the rest of the import.<br>' )
				.attr('id', 'span_importResult')
				.appendTo('#cpe-import-list');
			
			$('#cpe-import-list')
				.css('padding', '10px')
				.show();
			
		} else {
			$('#cpe-import-process-items *').show();			
			$('#import-cpe-load-list-block').hide();

			$(":button:contains('Reload list')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
			
			for ( var i = 0; i < params.importList.length; i++ ) {
				var sh = params.importList[i];

				$('<tr />')
					.addClass( 'item-row' )
					.attr({ 'id' : 'tr_' + sh.id })
					.appendTo( '#cpe-import-list-table' );

				$('<td />')
					.attr({ 'id' : 'td_' + sh.id })
					.css({ 'width': '630px' })
					.appendTo( '#tr_' + sh.id );
				
				$('<span />')
					.attr({ 'id' : 'span_producer_' + sh.id })
					.addClass( 'pointer' )	
					.html( sh.producer + ' ' )
					.appendTo( '#td_' + sh.id );

				$('<span />')
					.attr({ 'id' : 'span_name_' + sh.id })
					.addClass( 'bold pointer' )
					.html( sh.name + ' ' )
					.appendTo( '#td_' + sh.id );

				$('<span />')
					.attr({ 'id' : 'span_version_' + sh.id })
					.addClass( 'italic pointer' )
					.html( sh.version + ' ' )
					.appendTo( '#td_' + sh.id );

				if ( sh.is_new ) {
					
					$('<span />')
					.html( '&nbsp;NEW&nbsp;' )
					.attr('id', 'span_isNew_' + sh.id)
					.addClass( 'bold italic is_new' )
					.css({ 'color': 'white', 'background-color': '#7F7F7F'})							
					.appendTo( '#td_' + sh.id  );

					if ( sh.has_multiple ) {
						$('<span />')
							.html( '&nbsp;MULTIPLE FOUND WITHOUT CPE ID&nbsp;' )
							.attr({'id': 'span_TaranisMultipleWOCPE_' + sh.id, 'title': 'Multiple items found in Taranis that match this item, but without CPE ID. Importing this item will add a new item.'})
							.addClass( 'bold' )
							.css({ 'color': '#FFF', 'background-color': '#D30202', 'cursor': 'help'})							
							.insertAfter( '#span_isNew_' + sh.id );
					}
					
					$('<br />').insertAfter( '#span_TaranisMultipleWOCPE_' + sh.id );							

				} 
				
				$('<div />')
					.attr({ 'id' : 'div_sh_' + sh.id })
					.hide()
					.appendTo( '#td_' + sh.id );							

				if ( !sh.is_new ) {
					
					$('<span />')
						.html( sh.taranisEntry.producer + ' ' )
						.appendTo( '#div_sh_' + sh.id );

					$('<span />')
						.addClass( 'bold' )
						.html( sh.taranisEntry.name + ' ' )
						.appendTo( '#div_sh_' + sh.id );
											
					$('<span />')
						.addClass( 'italic' )
						.html( sh.taranisEntry.version + ' ' )
						.appendTo( '#div_sh_' + sh.id );
					
					$('<span />')
						.html( '&nbsp;TARANIS&nbsp;' )
						.attr('id', 'span_TaranisTag_' + sh.id )
						.addClass( 'bold is_changed' )
						.css({ 'color': '#FFF', 'background-color': '#7F7F7F'})							
						.appendTo( '#div_sh_' + sh.id );
					
					if ( sh.taranisEntry.cpe_id == '' || sh.taranisEntry.cpe_id == null ) {
						$('<span />')
							.html( '&nbsp;NO CPE ID&nbsp;' )
							.attr('id', 'span_TaranisNoCpe_' + sh.id )
							.addClass( 'bold is_changed' )
							.css({ 'color': '#FFF', 'background-color': '#D30202'})							
							.appendTo( '#div_sh_' + sh.id );
					}								

					$('<br />').insertAfter( '#span_TaranisNoCpe_' + sh.id );	
					
				} 
				
				$('<input />')
					.addClass('input-default')
					.css({ 'width' : '400px', 'margin-top': '5px'})
					.attr({ 'id' : 'inp_producer_' + sh.id })
					.val( $.trim( $('#span_producer_' + sh.id ).text() ) )
					.appendTo( '#div_sh_' + sh.id );

				$('<br />').insertAfter( '#inp_producer_' + sh.id );
											
				$('<input />')
					.addClass('input-default')
					.css({ 'width' : '400px', 'margin-top': '5px'})
					.attr({ 'id' : 'inp_name_' + sh.id })
					.val( $.trim( $('#span_name_' + sh.id ).text() ) )
					.appendTo( '#div_sh_' + sh.id );

				$('<br />').insertAfter( '#inp_name_' + sh.id );
				
				$('<input />')
					.addClass('input-default')
					.css({ 'width' : '400px', 'margin-top': '5px'})
					.attr({ 'id' : 'inp_version_' + sh.id })
					.val( $.trim( $('#span_version_' + sh.id ).text() ) )
					.appendTo( '#div_sh_' + sh.id );

				$('<input />')
					.addClass('input-default')
					.css({ 'width' : '400px', 'margin-top': '5px'})
					.attr({ 'id' : 'inp_cpe_id_' + sh.id, 'type' : 'text', 'disabled' : 'disabled' })
					.val( sh.cpe_id )
					.appendTo( '#div_sh_' + sh.id );						

				$('<input />')
					.attr({ 'id' : 'inp_type_' + sh.id, 'type' : 'hidden' })
					.val( sh.type )
					.appendTo( '#div_sh_' + sh.id );	
				
				$('<td />')
					.attr({ 'id' : 'td_icons_' + sh.id })
					.addClass('align-block-right')
					.appendTo( '#tr_' + sh.id );

				var buttonType = ( sh.is_new ) ? 'btn-add-cpe-import-item' : 'btn-update-cpe-import-item';				

				$('<input />')
					.attr({ 'id': 'chkb_' + sh.id, 'type': 'checkbox' })
					.val( sh.id )
					.appendTo( '#td_icons_' + sh.id );
				
				$('<img />')
					.attr({ 'src': $.main.webroot + '/images/icon_update.png', 'data-id': sh.id,'title': 'Import item' })
					.addClass('pointer ' + buttonType)
					.appendTo( '#td_icons_' + sh.id );
				
				$('<img />')
					.attr({ 'src': $.main.webroot + '/images/icon_delete.png', 'data-id': sh.id, 'title': 'Discard item' })
					.addClass('pointer btn-delete-cpe-import-item')
					.appendTo( '#td_icons_' + sh.id );
				
			}	
			$('#cpe-import-list, #cpe-import-list-action, #cpe-import-list-header, #cpe-import-set-version-to-delete-block').show();
		
			$('#btn-cpe-import-action').prop('disabled', false);
		}
	} else {
		alert( params.message );
	}
}

function importRestCallback ( params ) {
	if ( params.importOk == 1 ) {
		$('#span_importResult').html( '<b>' + params.itemsImported + '</b> items imported without CPE ID. Import of CPE done.' );
		$('#img_ajax2').hide();
	} else {
		alert(params.message)
	}
}

function clearImportCallback ( params ) {
	if ( params.clearOk == 1 ) {
		$('#span_importResult').text( 'Rest of import cleared. Import of CPE done.' );
		$('#img_ajax2').hide();
	} else {
		alert(params.message);
	}
}

function removeCPEImportItem ( params ) {
	if ( params.importAction == 1 ) {
		$('#tr_' + params.id).remove();
	} else {
		alert( params.message );
	}
}

function bulkCPEImportItemCallback ( params ) {

	if ( params.importOk == 1 ) {
		$.each( params.importIDs, function ( index ) {
			$('#tr_' + params.importIDs[index] ).remove();
		});
	
		if ( $('span[id^="span_producer_"]').length == 0 ) {
			$('#img_ajax2, #span_ajax2').show();
			getEntries();
		}
	} else {
		alert(params.message)
	}
	$('#btn-cpe-import-action').prop('disabled', false);		
}

function loadCPEFileCallback ( params ) {

	if ( params.loadFileOk == 1 ) {
		$('#import-cpe-load-file-result').text('Processing cpe dictionary. (this may take a few minutes)');		
		
		var xmlFile = params.location;
		
		var importVersions = ( $('#import-cpe-option').is(':checked') ) ? '1' : '0'; 
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'import_cpe',
			action: 'processXml',
			queryString: 'importOptionVersions=' + importVersions + '&file=' + encodeURIComponent( xmlFile ),
			success: processXmlCallback
		});
		
	} else {
		
		$('#import-cpe-location-block, #import-cpe-option-block').show();
		$('#img_ajax').hide();
 		$('#import-cpe-load-file-result').text(params.message);
		
		$('#img_ajax, #span_ajax').hide();
	}
}

function processXmlCallback ( params ) {
	$('#import-cpe-loader-block').hide();

	if ( params.message == 1 ) {
		alert(params.message);
	} else {
		$('#cpe-import-load-file').hide();
		$('#cpe-import-process-items, #import-cpe-load-list-block').show();

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Reload list',
				click: function () {
					$(":button:contains('Reload list')")
						.prop('disabled', true)
						.addClass('ui-state-disabled');
						
					$('#cpe-import-list-table tr').remove();
					
					getEntries();	
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);		
		
		getEntries();		
	}
}
