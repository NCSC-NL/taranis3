/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// open photo import dialog
	$('#filters').on( 'click', '.btn-import-photo', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'openDialogImportPhoto',
			success: openDialogImportPhotoCallback
		});
		
		dialog.dialog('option', 'title', 'Import photo');
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
	
	// export empty photo
	$('#filters').on( 'click', '.btn-export-photo', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/configuration/photo_management/exportEmptyPhoto?params=' );
	});
	
	// export all photos
	$('#filters').on( 'click', '.btn-export-all-photos', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/configuration/photo_management/exportAllPhotos?params=' );
	});

	// export all products in use
	$('#filters').on( 'click', '.btn-export-photo-in-use', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/configuration/photo_management/exportAllProductsInUSe?params=' );
	});

	// search issues
	$('#filters').on('click', '#btn-photo-issues-search', function () {
		if ( validateForm(['photo-issues-start-date', 'photo-issues-end-date']) ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'searchPhotoIssues',
				queryString: $('#form-photo-issues-search').serializeWithSpaces(),
				success: null
			});
		}
	});	

	// do issue search on ENTER
	$('#filters').on('keypress', '#photo-issues-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-photo-issues-search').trigger('click');
		}
	});	
	
});


function openDialogImportPhotoCallback ( params ) {

	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Load file',
			click: function () {

				if ( $('#photo-issues-constituent-group').val() == '' ) {
					alert('Please select a consituent group.');
				} else if ( $('#photo-issues-import-file').val() == '' ) {
					alert('Please select CSV import file.');
				} else {

					var importData = new FormData( document.getElementById('form-photo-issues-load-photo') );
					
					importData.append('params', '{"constituentGroup":"' + $('#photo-issues-constituent-group').val() + '", "separator":"' + $('#photo-issues-csv-separator').val() + '"}' );
					
					$('#photo-issues-import-file, #photo-issues-constituent-group-block, #photo-issues-photo-list').hide();
					$('#photo-issues-import-file-loading')
						.show()
						.removeClass('hidden');

					$(":button:contains('Load file'), :button:contains('Close')").remove();
					
					$.ajax({
						url: $.main.scriptroot + '/load/configuration/photo_management/loadImportFile',
						data: importData,
						processData: false,
						type: 'POST',
						contentType: false,
						headers: {
							'X-Taranis-CSRF-Token': $.main.csrfToken,
						},
						dataType: 'JSON'
					}).done(function (result) {
						$.main.activeDialog.html( result.page.dialog );
						if ( result.page.params.loadFileOk ) {
							getPhotoDetailsCallback( result.page.params );
						}
					}).fail(function () {
						alert('The photo was not successfully imported.');
					});
				}
			}
	    },
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}
	]);
	
	// get photo import details
	$('.link-photo-issues-photo-item').click( function () {
		$(":button:contains('Load file'), :button:contains('Close'), #photo-issues-photo-list").remove();
		$('#form-photo-issues-load-photo fieldset').html('loading import photo details...')
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'getPhotoDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: getPhotoDetailsCallback
		});
	});
	
	// delete an import photo
	$('.btn-delete-photo').click( function () {
		if ( confirm( 'Are you sure you want to delete this import and unlink connected issues?' ) ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'deletePhoto',
				queryString: 'id=' + $(this).attr('data-photoid') + '&groupid=' + $(this).attr('data-groupid'),
				success: deletePhotoCallback
			});
		}
	});
	
	// show hide imports depending on the selected constituent group
	$('#photo-issues-constituent-group').change( function () {
		if ( $(this).val() != '' ) {
			$('.photo-issues-photo-item').hide();
			$('.photo-issues-photo-item[data-groupid="' + $(this).val() + '"]').show();
			if ( $('.btn-delete-photo[data-groupid="' + $(this).val() + '"]').length > 0 ) {
				$(":button:contains('Load file')").hide();
			} else {
				$(":button:contains('Load file')").show();
			}
		} else {
			$('.photo-issues-photo-item').show();
			$(":button:contains('Load file')").hide();
		}
	});
	
	$(":button:contains('Load file')").hide();
}

function getPhotoDetailsCallback( params ) {
	if ( params.importDone ) {
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Return to groupslist',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'openDialogImportPhoto',
						success: openDialogImportPhotoCallback
					});
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
	} else {
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Return to groupslist',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'openDialogImportPhoto',
						success: openDialogImportPhotoCallback
					});
				}
			},
			{
				text: 'Import photo',
				click: function () {
					if ( $('.photo-issue-item.photo-issues-status-color-green').length + $('.photo-issue-item.item-row').length == $('.photo-issue-item').length ) {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'photo_management',
							action: 'importPhoto',
							queryString: 'id=' + params.id,
							success: importPhotoCallback
						});					
					}
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		$('#photo-issues-import-details-tabs').newTabs();
		
		// approve import item for import
		$('.btn-resolve-item-photo-details').click( function () {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'setOkToImport',
				queryString: 'sh_id=' + $(this).attr('data-id') + '&photo_id=' + params.id,
				success: setOkToImportCallback
			});
		});
	
		// create new issue for import item
		$('.btn-create-issue-photo-details').click( function () {
			var sh_id = $(this).attr('data-id');
	
			var issueDescription = $('#span_subtitle_' + sh_id ).text();
			var issueType = $(this).attr('data-issuetype');
			
			var queryString = 'sh_id=' + $(this).attr('data-id') 
							+ '&type=' + $(this).attr('data-issuetype') 
							+ '&description=' + encodeURIComponent( issueDescription );
	
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'createIssue',
				queryString: queryString,
				success: createIssueCallback
			});
		});
	
		// delete import item from import list
		$('.btn-delete-item-photo-details').click( function () {
	
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'dontImport',
				queryString: 'photo_id=' + params.id + '&sh_id=' + $(this).attr('data-id'),
				success: dontImportCallback
			});
		});
		
		// create new software/hardware from import item
		$('.btn-create-software-hardware-photo-details').click( function () {
			var dialog = $.main.activeDialog;
			dialog.html('<fieldset>loading...</fieldset>');
			
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'software_hardware',
				action: 'openDialogNewSoftwareHardware',
				queryString: 'import_id=' + $(this).attr('data-id'),
				success: function (dialogSHParams) {
					
					if ( dialogSHParams.writeRight == 1 ) {
						var context = $('#software-hardware-details-form[data-id="NEW"]');
						var thisDialog = $.main.activeDialog;

						$.main.activeDialog.dialog('option', 'buttons', [
							{
								text: 'Save',
								click: function () {
				
									if ( $("#software-hardware-details-producer", context).val() == "") {
										alert("Please specify Producer.");	
									} else if ( $("#software-hardware-details-name", context).val() == "") {
										alert("Please specify Name.");
									} else if (  $('input[name="monitored"]:checked', context).length == 0 ) {
										alert("Please specify monitored.");
									} else {
										$.main.ajaxRequest({
											modName: 'configuration',
											pageName: 'software_hardware',
											action: 'saveNewSoftwareHardware',
											queryString: $(context).serializeWithSpaces(),
											success: function (addNewSHParams) {
												if ( addNewSHParams.saveOk ) {
											
													var queryString = 'id=' + addNewSHParams.id;
													
													$.main.ajaxRequest({
														modName: 'configuration',
														pageName: 'photo_management',
														action: 'getPhotoDetails',
														queryString: 'id=' +params.id,
														success: getPhotoDetailsCallback
													});
													
												} else {
													alert(addNewSHParams.message)
												}
											}
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
						
						$('#software-hardware-details-tabs', context).newTabs();
					}
				}
			});		
			
			dialog.dialog('option', 'title', 'Add new software/hardware');
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
		
		$('#toggle-darkorange, #toggle-orange, #toggle-blue, #toggle-green, #toggle-white').change( function () {
			var toggleColor = $(this).attr('id').replace( /^.*?-(\w+)$/, '$1');
			if ( $(this).is(':checked') ) {
				$('.photo-issues-status-color-' + toggleColor).show();
			} else {
				$('.photo-issues-status-color-' + toggleColor).hide();
			}
		});
		
		// disable button 'Import photo' if there are still import items to be dealt with
		if ( $('.photo-issue-item.photo-issues-status-color-green').length + $('.photo-issue-item.item-row').length != $('.photo-issue-item').length ) {
			$(":button:contains('Import photo')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');
		}
	}	
}

function deletePhotoCallback ( params ) {
	if ( params.deleteOk ) {
		// add the name of the group to the group selection list
		$('<option />')
			.val( params.groupid )
			.text( $('.link-photo-issues-photo-item[data-id="' + params.id + '"]').text() )
			.appendTo('#photo-issues-constituent-group');

		// remove photo import from import list
		$('.photo-issues-photo-item[data-id="' + params.id + '"]').remove();
	} else {
		alert(params.message);
	}
}

function setOkToImportCallback ( params ) {
	
	if ( params.importOk ) {
		$('.photo-issue-item[data-id="' + params.id + '"]').removeClass('photo-issues-status-color-orange');
		$('.photo-issue-item[data-id="' + params.id + '"]').addClass('photo-issues-status-color-green');
		
		// remove icons
		$('.btn-resolve-item-photo-details[data-id="' + params.id + '"], .btn-create-issue-photo-details[data-id="' + params.id + '"]').remove();
		
		// enable button 'Import photo' when all issue have been resolved
		if ( $('.photo-issue-item.photo-issues-status-color-green').length + $('.photo-issue-item.item-row').length == $('.photo-issue-item').length ) {
			$(":button:contains('Import photo')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}
		
	} else {
		alert( params.message );
	}
}

function createIssueCallback ( params ) {
	
	if ( params.createOk ) {
		
		// add item to issue list in dialog tab 'Issues'
		var newIssue = $('.photo-issues-details-issue-item-blanco').clone().prependTo('#photo-issues-details-issue-list');
		newIssue.removeClass('hidden photo-issues-details-issue-item-blanco');
		newIssue.addClass('photo-issues-pending');
		newIssue.children('.photo-issues-details-issue-item-product').text( $('#span_import_item_' + params.softwareHardwareId).text() );
		newIssue.children('.photo-issues-details-issue-item-type').text( $('#span_import_item_type_' + params.softwareHardwareId).text() );
		newIssue.children('.photo-issues-details-issue-item-description').text( params.description );
		newIssue.attr('data-id', params.id);
		
		// remove item from import list
		$('.photo-issue-item[data-id="' + params.softwareHardwareId + '"]').remove();

		// enable button 'Import photo' when all issue have been resolved
		if ( $('.photo-issue-item.photo-issues-status-color-green').length + $('.photo-issue-item.item-row').length == $('.photo-issue-item').length ) {
			$(":button:contains('Import photo')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}
		
		// add issue to main window issue list
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'getIssueItemHtml',
			queryString: '&id=' + params.id + '&insertNew=1',
			success: getConfigurationItemHtmlCallback
		});		
		
	} else {
		alert( params.message );
	}
}

function dontImportCallback ( params ) {

	if ( params.noImportOk ) {
		
		// add item to issue list in dialog tab 'Ignore imports list'
		var dontImportItem = $('.photo-issues-details-dont-import-item-blanco').clone().prependTo('#photo-issues-details-dont-import-list');
		dontImportItem.removeClass('hidden photo-issues-details-dont-import-item-blanco');
		dontImportItem.children('.photo-issues-details-dont-import-item-type').text( $('#span_import_item_type_' + params.softwareHardwareId).text() );
		dontImportItem.children('.photo-issues-details-dont-import-item-product').text( $('#span_import_item_' + params.softwareHardwareId).text() );
		dontImportItem.attr('data-id', params.id);

		// remove item from import list
		$('.photo-issue-item[data-id="' + params.softwareHardwareId + '"]').remove();

		// enable button 'Import photo' when all issue have been resolved
		if ( $('.photo-issue-item.photo-issues-status-color-green').length + $('.photo-issue-item.item-row').length == $('.photo-issue-item').length ) {
			$(":button:contains('Import photo')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}

		// add issue to main window issue list		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'getIssueItemHtml',
			queryString: '&id=' + params.id + '&insertNew=1',
			success: getConfigurationItemHtmlCallback
		});		
		
	} else {
		alert( params.message );
	}	
}

function importPhotoCallback ( params ) {
	
	if ( params.importOk ) {
		
		// remove the import list
		$('#photo-issues-details-tabs-import-list fieldset div:first-child, #photo-issues-details-import-list *').remove();

		// list the closed issues
		if ( params.closedIssues && params.closedIssues.length > 0 ) {
			$('<span/>')
				.text('The following issue(s) have been closed: ' )
				.appendTo('#photo-issues-details-import-list');
			
			$.each( params.closedIssues, function (index, value) {
				$('<span/>')
					.text('#' + value + ' ')
					.addClass('span-link photo-issue-link')
					.attr('data-id', value)
					.appendTo('#photo-issues-details-import-list');
			});
		}
		
		$('<br>').appendTo('#photo-issues-details-import-list');
		
		$('<span/>')
			.text('A new issue has been created for informing the constituent. Issue ')
			.appendTo('#photo-issues-details-import-list');

		$('<span/>')
			.text('#' + params.id)
			.addClass('span-link photo-issue-link')
			.attr('data-id', params.id)
			.appendTo('#photo-issues-details-import-list');
		
		$('<br>').appendTo('#photo-issues-details-import-list');
		
		// remove the 'Import photo' button
		$(":button:contains('Import photo')").remove();
		
		// Because more than one issue could be changed at this point, 
		// the issue list in main window needs te be refreshed. 
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'displayPhotoIssues',
			queryString: 'no_filters=1',
			success: null
		});			
		
	} else {
		alert( params.message );
	}
}
