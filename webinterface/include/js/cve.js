/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// edit/view cve details
	$('#content').on( 'click', '.btn-edit-cve-description, .btn-view-cve-description', function () {
		openDialogCVEDetails( $(this).attr('data-id') );
	});
	
	// search CVE ID's
	$('#filters').on('click', '#btn-cve-search', function (event, origin) {
		
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cve',
			action: 'searchCVE',
			queryString: $('#form-cve-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do cve search on ENTER
	$('#filters').on('keypress', '#cve-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-cve-search').trigger('click');
		}
	});

	// click on button 'Manage CVE download files
	$('#filters').on('click', '#btn-manage-cve-files', function (event) {
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cve',
			action: 'openDialogCVEFiles',
			success: function (openParams) {
				var context = $('#form-cve-files');
				
				if ( openParams.isAdmin == 1 ) {
					$('.btn-delete-cve-file').click( function () {
						$(this).parent().remove();
					});
					
					$('#cve-file-add').click( function () {
						var cloneBlock = $(this).siblings('.hidden'); 
						var clonedBlock = cloneBlock
							.clone(true,true)
							.insertBefore(cloneBlock)
							.removeClass('hidden');
						clonedBlock.children('input:first').focus();
					});
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								
								$.main.ajaxRequest({
									modName: 'configuration',
									pageName: 'cve',
									action: 'saveCVEFiles',
									queryString: $(context).serializeWithSpaces(),
									success: function (saveParams) {
										if ( saveParams.saveOk ) {
											
											$.main.activeDialog.dialog('close');
											
										} else {
											alert(saveParams.message)
										}
									}
								});
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
		
		dialog.dialog('option', 'title', 'CVE Files');
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
});


function openDialogCVEDetails (cveID) {
	
	var dialog = $('<div>').newDialog();
	dialog.html('<fieldset>loading...</fieldset>');
	
	$.main.ajaxRequest({
		modName: 'configuration',
		pageName: 'cve',
		action: 'openDialogCVEDetails',
		queryString: 'id=' + cveID,
		success: function (openParams) {
			var context = $('#form-cve-description[data-id="' + openParams.id + '"]');
			
			if ( openParams.writeRight == 1 ) {
				
				$.main.activeDialog.dialog('option', 'buttons', [
					{
						text: 'Save',
						click: function () {
							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'cve',
								action: 'saveCVEDetails',
								queryString: $(context).serializeWithSpaces() + '&id=' + openParams.id,
								success: function (saveParams) {
									if ( saveParams.saveOk ) {
								
										if ( $('#cve-content-heading').length > 0 ) {
											var queryString = 'id=' + saveParams.id;
											$.main.ajaxRequest({
												modName: 'configuration',
												pageName: 'cve',
												action: 'getCVEItemHtml',
												queryString: queryString,
												success: function (getHTMLparams) {
													if ( getHTMLparams.insertNew == 1 ) {
														$('#empty-row').remove();
														$('.content-heading').after( getHTMLparams.itemHtml );
													} else {
														$('#' + getHTMLparams.id).html( getHTMLparams.itemHtml );
													}
												}
											});
										}
										
										$.main.activeDialog.dialog('close');
										
									} else {
										alert(saveParams.message)
									}
								}
							});
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
			
			// apply CVE template to 'translation'/'custom description' field
			$('#btn-cve-details-apply-template', context).click( function () {
				if ( $('#cve-details-template', context).val() != '' ) {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'cve',
						action: 'applyCVETemplate',
						queryString: 'cve_id=' + openParams.id + '&template_id=' + $('#cve-details-template', context).val() + '&original_text=' + encodeURIComponent( $('#cve-details-custom-description', context).val() ),
						success: function (cveTemplateParams) {
							if ( cveTemplateParams.message != '' ) {
								var cveTranslationElement = $('#cve-details-custom-description', '#form-cve-description[data-id="' + cveTemplateParams.cve_id + '"]');
								cveTranslationElement.html( cveTemplateParams.replacement_text );
								cveTranslationElement.val( cveTranslationElement.text() );
							} else {
								alert( cveTemplateParams.message );
							}
						}
					});
				}
			});
		}
	});
	
	dialog.dialog('option', 'title', 'CVE description details');
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
