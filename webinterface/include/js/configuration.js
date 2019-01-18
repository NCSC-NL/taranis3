/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function deleteConfigurationItemCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		$('#' + params.id).remove();
	} else {
		alert(params.message);
	}
}

function getConfigurationItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('.content-heading').after( params.itemHtml );
	} else {
		$('#' + params.id).html( params.itemHtml );
	}
}
