/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	$(document).on('mouseenter', '#advisory-platforms-left-column option, #advisory-products-left-column option, #advisory-platforms-right-column option, #advisory-products-right-column option', function () {
		var tab = $(this).parent().attr('data-tab');
		
		var tabContext = $('#advisory-details-tabs-' + tab); 
		$('.publications-software-hardware-fulltext', tabContext).html( $(this).html() );
	});
	
	$(document).on('mouseleave', '#advisory-platforms-left-column option, #advisory-products-left-column option, #advisory-platforms-right-column option, #advisory-products-right-column option', function () {
		var tab = $(this).parent().attr('data-tab');
		
		var tabContext = $('#advisory-details-tabs-' + tab); 
		$('.publications-software-hardware-fulltext', tabContext).html( '' );
	});
	
});

function searchSoftwareHardwareWrite (context, searchType, publicationId, publicationType) {
	if ( $('#' + publicationType + '-' + searchType + '-search').val().length > 1 ) {
		var search = encodeURIComponent( $('#' + publicationType + '-' + searchType + '-search').val() );

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'common_actions',
			action: 'searchSoftwareHardwareWrite',
			queryString: 'search=' + search + '&publicationtype=' + publicationType + '&searchtype=' + searchType + '&publicationid=' + publicationId,
			success: searchSoftwareHardwareWriteCallback
		});
		
	} else {
		alert('Can only search with at least two characters.')
	}
}

function searchSoftwareHardwareWriteCallback ( params ) {
	var context = $('.publication-details-form[data-publicationid="' + params.publicationId + '"]');
	var block   = params.pubType + '-' + params.searchType;
	var rightColumn = $('#' + block + '-right-column', context ); 
	var leftColumn  = $('#' + block + '-left-column', context );
	var in_use      = $('#btn-' + block + '-inuse-only', context);
	var buttons		= $('#' + block + '-left-right', context);

	// clear former searchresults
	rightColumn.children('option').each( function (i) {
		$(this).remove();
	});

	if ( params.data.length > 0 ) {
		$.each( params.data, function (i, sh) {
			
			//create option element and add to rightcolumn
			var searchResult = $('<option>')
				.html( sh.producer.substr(0,1).toUpperCase() + sh.producer.substr(1) + ' ' + sh.name + ' ' + sh.version + ' (' + sh.description + ')' )
				.val( sh.id )
				.attr({
					'data-producer': sh.producer,
					'data-name': sh.name,
					'data-version': sh.version
				})
				.on('dblclick', function () {
					$('.btn-option-to-left', buttons).trigger('click');
				})
				.appendTo( rightColumn );
			
			// mark all the options which are in use by constituents
			if ( sh.in_use > 0 ) {
				searchResult.addClass('option-sh-in-use');
			}
		});
		
	} else {
		// give the search inputfield a red border when no results are found
		rightColumn
			.siblings('input[type="search"]')
			.css('border', '1px solid red')
			.keyup( function () {
				$(this).css('border', '1px solid #bbb');
			});
	}

	if(in_use.length > 0 && in_use.is(':checked')) {
		rightColumn.children('option').not('.option-sh-in-use').hide();
	}

	checkRightColumnOptions(leftColumn, rightColumn);
}


function getPublicationTemplateCallback ( params ) {
	if ( params.templateOk == 1 ) {
		var context = $('.publication-details-form[data-publicationid="' + params.publicationId + '"]');
		$('.publication-template-result[id="' + params.publicationType + '-' + params.tab + '-template"]', context).html(params.template);
	} else {
		alert( params.message );
	}
}

function getTemplateTextCallback ( params ) {
	if ( params.templateOk == 1 ) {
		var context = $('.publication-details-form[data-publicationid="' + params.publicationId + '"]');
		$('.publications-details-' + params.tab + '-text', context).html( params.templateText );
		$('.publications-details-' + params.tab + '-text', context).val( $('.publications-details-' + params.tab + '-text', context).text() );
	} else {
		alert( params.message );
	}
}

function getPulicationPreviewCallback ( params ) {

	if ( params.previewOk == 1 ) {
		var context = $('.publication-details-form[data-publicationid="' + params.publicationId + '"]');
		$('.publications-details-preview', context).html(params.previewText);
	} else {
		alert( params.message );
	}
}

function setPublicationCallback ( params ) {
	if ( params.saveOk == 1 ) {

		$.main.activeDialog.dialog('close');
	} else {
		alert( params.message );
	}	
}
