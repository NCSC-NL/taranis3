/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function installCveSummaryTooltips($where) {
	$where.tooltip({
		close: function (event, ui) {
			$(this).attr('title', '');
		},
		content: function (callback) {
			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess_details',
				action: 'getRelatedId',
				queryString: 'id=' + $(this).text(),
				success: function (cveDescription) {
					
					var tooltip = '<span class="bold">' + cveDescription.identifier  + '</span><br><pre>';
					
					if ( cveDescription.custom_description ) {
						tooltip += cveDescription.custom_description;
					} else if ( cveDescription.description ) {
						tooltip += cveDescription.description;
					} else {
						tooltip += 'NO DESCRIPTION AVAILABLE';
					}
					tooltip += '<\pre>';
					
					callback(tooltip);
				}
			});
		}
	})
	.off( 'mouseover' )
	.on( 'click', function () {
		$(this).tooltip('open');
		return false;
	});
}
