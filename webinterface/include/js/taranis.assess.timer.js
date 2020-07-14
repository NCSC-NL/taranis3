/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// timer for refreshing Assess page items
	$.main.assessTimer = $.timer( function () {
		if ( $('.selected-submenu').attr('id') == 'assess-submenu' ) {

			var queryString = ( $('#btn-assess-search').is(':visible') )
				? $('#form-assess-standard-search').serializeWithSpaces()
				: $('#form-assess-custom-search').serializeWithSpaces() + '&isCustomSearch=1';
			
			queryString += '&resultCount=' + $('#assess-result-count').text(); 
			if ( $('.item-arrow:visible').parent().attr('id') ) {
				queryString += '&currentItemID=' + $('.item-arrow:visible').parent().attr('id');
			}
			
			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess',
				action: 'refreshAssessPage',
				queryString: queryString,
				success: 'refreshAssessPageCallback',
				isAutoRefresh: true
			}, true);
			
		} else {
			stopAssessTimer();
		}
	}, 300000 ); // 300000 ms = 5 minutes
});

function startAssessTimer ( params ) {
	$.main.assessTimer.play(true);

	// update assess items with added-to-publication-settings
	var addedToPublicationQueryString = ''
	$('.addToPublicationOptionHeader[data-checked="no"]').each( function (i) {
		addedToPublicationQueryString += '&ids=' + $(this).attr('data-digest');
		$(this).attr('data-checked', 'yes');
	});
	
	$.main.ajaxRequest({
		modName: 'assess',
		pageName: 'assess',
		action: 'getAddedToPublication',
		queryString: addedToPublicationQueryString,
		success: function ( callbackParams ) {
			$.each( callbackParams.publications, function (itemDigest, addedToPublicationSettingsArray) {
				$.each( addedToPublicationSettingsArray, function (i,addedToPublicationSetting) {
					$('.addToPublicationOption[data-digest="' + encodeURIComponent(itemDigest) + '"][data-publicationId="' + addedToPublicationSetting.publication_type + '"][data-specifics="' + addedToPublicationSetting.publication_specifics + '"]')
						.addClass('isAddedToPublication')
				})
			});
		}
	});

	if ( typeof( params ) !== 'undefined' && 'showCustomSearch' in params && params.showCustomSearch == 1 ) {
		$('#btn_toggleSearchMode').trigger('click');
	}

	$('.assess-item:first .item-arrow').show();

    installCveSummaryTooltips($('.assess-details-id', '.assess-items'));
}

function stopAssessTimer () {
	$.main.assessTimer.stop();
}
