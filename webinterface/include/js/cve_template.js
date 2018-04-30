/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// edit/view cve template details
	$('#content').on( 'click', '.btn-edit-cve-template, .btn-view-cve-template', function () {
		var cveTemplateID = $(this).attr('data-id');
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cve_template',
			action: 'openDialogCVETemplateDetails',
			queryString: 'id=' + cveTemplateID,
			success: function (openParams) {
				var context = $('#form-cve-template[data-id="' + openParams.id + '"]');
				
				if ( openParams.writeRight == 1 ) {
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								
								if ( $.trim( $('#cve-template-details-description', context).val() ) == '' ) {
									alert("Please specify the a description.");
								} else {
								
									$.main.ajaxRequest({
										modName: 'configuration',
										pageName: 'cve_template',
										action: 'saveCVETemplateDetails',
										queryString: $(context).serializeWithSpaces() + '&id=' + openParams.id,
										success: saveCVETemplateCallback
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
		});
		
		dialog.dialog('option', 'title', 'CVE template details');
		dialog.dialog('option', 'width', '600px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
	
		dialog.dialog('open');
	});

	
	// delete a CVE template
	$('#content').on( 'click', '.btn-delete-cve-template', function () {
		if ( confirm('Are you sure you want to delete the CVE template?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'cve_template',
				action: 'deleteCVETemplate',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});
		}
	});
	
	// add a new CVE template
	$('#filters').on( 'click', '#btn-add-cve-template', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cve_template',
			action: 'openDialogNewCVETemplate',
			success: function ( openParams ) {
				if ( openParams.writeRight == 1 ) {
					var context = $('#form-cve-template[data-id="NEW"]');
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
			
								if ( $.trim( $('#cve-template-details-description', context).val() ) == '' ) {
									alert("Please specify the a description.");
								} else {
			
									$.main.ajaxRequest({
										modName: 'configuration',
										pageName: 'cve_template',
										action: 'saveNewCVETemplate',
										queryString: $('#form-cve-template[data-id="NEW"]').serializeWithSpaces(),
										success: saveCVETemplateCallback
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
					})
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Add new CVE template');
		dialog.dialog('option', 'width', '600px');
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

function saveCVETemplateCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cve_template',
			action: 'getCVETemplateItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
