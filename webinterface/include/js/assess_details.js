/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogAssessDetailsCallback ( params ) {
	
	var assessDetailsTabs = 'div[id="assess-details-tabs"][data-digest="' + params.digest + '"]';
	
	$(assessDetailsTabs).newTabs();
	
	if ( $('#assess-details-analyze-right', assessDetailsTabs).val() == 1 ) {
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Analyze',
				click: function () {
					if ( $('img.img-assess-item-analyze[data-digest="' + params.digest + '"]').length > 0 ) {
						$('img.img-assess-item-analyze[data-digest="' + params.digest + '"]').trigger('click');
					} else {
						$('#assess-details-digest', assessDetailsTabs).trigger('click')
					}
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
	}

	installCveSummaryTooltips($('.assess-details-id', '#assess-details-tabs'));
}
