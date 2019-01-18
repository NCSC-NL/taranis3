/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	$('#filters').on('click', '#btn-import-export-sources', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources_import_export',
			action: 'openDialogImportExportSources',
			success: openDialogImportExportSourcesCallback
		});		
		
		dialog.dialog('option', 'title', 'Import/Export Sources');
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

function openDialogImportExportSourcesCallback ( params ) {

	$('#sources-import-export-tabs').newTabs();
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Import',
			click: function () {
				$('#sources-import-export-tabs').tabs('disable', 1);

				$(":button:contains('Import'), :button:contains('Export')")
					.prop('disabled', true)
					.addClass('ui-state-disabled');
				
				var importData = new FormData( document.getElementById('sources-import-export-form-import') );
				
				$('#sources-import-export-form-import').hide();
				$('#sources-import-export-processing-import').removeClass('hidden');

				$.ajax({
					url: $.main.scriptroot + '/load/configuration/sources_import_export/importSources',
					data: importData,
					processData: false,
					type: 'POST',
					contentType: false,
					headers: {
						'X-Taranis-CSRF-Token': $.main.csrfToken,
					},
					dataType: 'JSON'
				}).done(function ( result ) {
					$.main.activeDialog.html( result.page.dialog );
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Close',
							click: function () { $(this).dialog('close') }
						}
					]);
					
					$('#sources-import-tabs').newTabs();
				}).fail(function () {
					$('#sources-import-export-tabs').tabs('enable', 1);
					$(":button:contains('Import'), :button:contains('Export')")
						.prop('disabled', false)
						.removeClass('ui-state-disabled');
				});
				
			}
		},
		{
			text: 'Export',
			click: function () {
				var exportParams = new Object();
				
				exportParams.protocols = new Array();
				exportParams.categories= new Array();
				exportParams.parsers = new Array();
				exportParams.languages = new Array();
				
				$('#sources-export-selected-protocols option').each( function (i) {
					exportParams.protocols.push( $(this).val() );	
				});

				$('#sources-export-selected-categories option').each( function (i) {
					exportParams.categories.push( $(this).val() );	
				});
				
				$('#sources-export-selected-languages option').each( function (i) {
					exportParams.languages.push( $(this).val() );	
				});

				$('#sources-export-selected-parsers option').each( function (i) {
					exportParams.parsers.push( $(this).val() );	
				});
				
				$('#downloadFrame').attr( 'src', 'loadfile/configuration/sources_import_export/exportSources?params=' + JSON.stringify( exportParams ) );
			}
		}
	]);
	
	// show/hide Import/Export buttons
	$('a[href^="#sources-import-export-tabs-"]').click( function () {
		if ( $(this).attr('href') == '#sources-import-export-tabs-import' ) {
			$(":button:contains('Import')").show();
			$(":button:contains('Export')").hide();
		} else {
			$(":button:contains('Import')").hide();
			$(":button:contains('Export')").show();
		}
	});
	
	$('a[href="#sources-import-export-tabs-import"]').triggerHandler('click');
	
}
