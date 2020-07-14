/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view publication template details
	$('#content').on( 'click', '.btn-edit-publication-template, .btn-view-publication-template', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'publication_templates',
			action: 'openDialogPublicationTemplateDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogPublicationTemplateDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Publication template details');
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
	
	// delete a publication template
	$('#content').on( 'click', '.btn-delete-publication-template', function () {
		if ( confirm('Are you sure you want to delete the publication template?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'publication_templates',
				action: 'deletePublicationTemplate',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});		
		}		
	});

	// view publication template details summary
	$('#content').on( 'click', '.btn-publication-template-overview', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'publication_templates',
			action: 'openDialogPublicationTemplateSummary',
			queryString: 'id=' + $(this).attr('data-id'),
			success: null
		});		
		
		dialog.dialog('option', 'title', 'Constituent group details summary');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Print summary': function () {
					printInput( $('#publication-template-summary') );
				},
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});	
	
	// add a new publication template
	$('#filters').on( 'click', '#btn-add-publication-template', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'publication_templates',
			action: 'openDialogNewPublicationTemplate',
			success: openDialogNewPublicationTemplateCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new publication template');
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

	// search publication templates
	$('#filters').on('click', '#btn-publication-template-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'publication_templates',
			action: 'searchPublicationTemplates',
			queryString: $('#form-publication-template-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do publication template search on ENTER
	$('#filters').on('keypress', '#publication-template-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-publication-template-search').trigger('click');
		}
	});
	
});


function openDialogNewPublicationTemplateCallback ( params ) {
	var context = $('#publication-template-details-form[data-id="NEW"]');
	$('#publication-template-details-tabs', context).newTabs();

	if ( params.writeRight == 1 ) {
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Validate template',
				click: function () { validateTemplate(); }			
			},
			{
				text: 'Save',
				click: function () {

					if ( $("#publication-template-details-title", context).val() == "") {
						alert("Please specify title.");
					} else if ( $("#publication-template-details-template", context).val() == "") {
						alert("Please create a template on the Template tab");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'publication_templates',
							action: 'saveNewPublicationTemplate',
							queryString: $(context).serializeWithSpaces(),
							success: savePublicationTemplateCallback
						});					
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		// show/hide 'validate template' button
		$('a[href^="#publication-template-details-tabs-"]', context).click( function () {
			if ( $(this).attr('href') == '#publication-template-details-tabs-template' ) {
				$(":button:contains('Validate template')").show();
			} else {
				$(":button:contains('Validate template')").hide();
			}
		});
		
		$('a[href^="#publication-template-details-tabs-general"]', context).triggerHandler('click');
	}
}

function openDialogPublicationTemplateDetailsCallback ( params ) {
	var context = $('#publication-template-details-form[data-id="' + params.id + '"]');
	$('#publication-template-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) {
	
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});	
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Validate template',
				click: function () { validateTemplate(); }			
			},
			{
				text: 'Save',
				click: function () {

					if ( $("#publication-template-details-title", context).val() == "") {
						alert("Please specify title.");
					} else if ( $("#publication-template-details-template", context).val() == "") {
						alert("Please create a template on the Template tab");
					} else {
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'publication_templates',
							action: 'savePublicationTemplateDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: savePublicationTemplateCallback
						});
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		// show/hide 'validate template' button
		$('a[href^="#publication-template-details-tabs-"]', context).click( function () {
			if ( $(this).attr('href') == '#publication-template-details-tabs-template' ) {
				$(":button:contains('Validate template')").show();
			} else {
				$(":button:contains('Validate template')").hide();
			}
		});
		
		$('a[href^="#publication-template-details-tabs-general"]', context).triggerHandler('click');
				
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function savePublicationTemplateCallback ( params ) {
	
	if ( params.saveOk ) {
	
		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'publication_templates',
			action: 'getPublicationTemplateItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
