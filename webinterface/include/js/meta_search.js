/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// click on meta search button (=magnifying glass)
	$('#btn-metasearch').click( function( event, origin ) {
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}

		// hide active submenu and deselect main menu item
		$('.selected-menu').removeClass('hover-submenu');
		$('.selected-menu').removeClass('selected-menu');
		$('.selected-submenu')
			.hide()
			.removeClass('selected-submenu');
		
		$('title').html('Taranis &mdash; Search');
		
		$('#metasearch-submenu')
			.addClass('selected-submenu')
			.trigger('mouseover');
		$('#metasearch-submenu').trigger('mouseout')
		
		if ( $.trim( $('#metasearch-input').val() ) != '' ) {
			$.main.ajaxRequest({
				modName: 'search',
				pageName: 'meta_search',
				action: 'doMetaSearch',
				queryString: 'search=' + encodeURIComponent( $('#metasearch-input').val() ) + '&hidden-page-number=' + $('#hidden-page-number').val(),
				success: doMetaSearchCallback
			});
		}
	});	
	
	// do meta search on ENTER
	$('#metasearch-input').keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-metasearch').trigger('click', 'searchOnEnter');
		}		
	});
	
	$('#metasearch-show-advanced').click( function () {
		// hide active submenu and deselect main menu item
		$('.selected-menu').removeClass('hover-submenu');
		$('.selected-menu').removeClass('selected-menu');
		$('.selected-submenu')
			.hide()
			.removeClass('selected-submenu');
		
		$('title').html('Taranis &mdash; Search');
		
		$('#metasearch-submenu')
			.addClass('selected-submenu')
			.trigger('mouseover');
		$('#metasearch-submenu').trigger('mouseout')
		
		$.main.ajaxRequest({
			modName: 'search',
			pageName: 'meta_search',
			action: 'showAdvancedSearchSettings',
			success: showAdvancedSearchSettingsCallback
		});
	});
	
	// show/hide advanced search settings
	$('#filters').on('click', '#btn-meta-search-advanced-show', function () {
		if ( $('.meta-search-advanced:visible').length > 0 ) {
			$('.meta-search-advanced, .meta-search-advanced-settings').hide();
			$(this).val('Show advanced search settings');
		} else {
			$('.meta-search-advanced, .meta-search-advanced-settings').show();
			$(this).val('Hide advanced search settings');
		}
	})
	
	// show/hide parts of the advanced search settings
	$('#filters').on('click', '#meta-search-assess, #meta-search-analyze, #meta-search-publications, #meta-search-publications-advisory', function () {
		if ( $(this).is(':checked') ) {
			$(this).siblings('div').css('visibility', 'inherit');
			$(this).siblings('div').find('input,select').prop('disabled', false);
		} else {
			$(this).siblings('div').css('visibility', 'hidden');
			$(this).siblings('div').find('input,select').prop('disabled', true);
		}
	});
	
	// do search with advanced search settings
	$('#filters').on('click', '#btn-meta-search-advanced-search', function (event, origin) {
		
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}
		
		if ( 
			!$('#meta-search-assess').is(':checked')
			&& !$('#meta-search-analyze').is(':checked')
			&& !$('#meta-search-publications').is(':checked')
		) {
			alert('Please select one or more options (Assess, Analyze and/or Publications');
		} else if ( 
			$('#meta-search-publications').is(':checked')
			&& !$('#meta-search-publications-end-of-week').is(':checked')
			&& !$('#meta-search-publications-end-of-day').is(':checked')
			&& !$('#meta-search-publications-end-of-shift').is(':checked')
			&& !$('#meta-search-publications-advisory').is(':checked')
		) {
			alert('Please select one or more publication options or uncheck the publications option.');
		} else if ( validateForm(['meta-search-start-date', 'meta-search-end-date']) ) {
		
			$.main.ajaxRequest({
				modName: 'search',
				pageName: 'meta_search',
				action: 'doAdvancedMetaSearch',
				queryString: $('#form-meta-search-advanced').serializeWithSpaces(),
				success: doMetaSearchCallback
			});
		}
	});
	
	// do meta search on ENTER
	$('#filters').on('keypress', '#meta-search-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-meta-search-advanced-search').trigger('click', 'searchOnEnter');
		}		
	});	
	
});

function doMetaSearchCallback ( params ) {
	
	var re_analysis_id = new RegExp('(AN-[0-9]{4}-[0-9]{4})', 'gi'),
		re_govecert_id = new RegExp('(' + params.advisoryPrefix + '-[0-9]{4}-[0-9]+ \\[v[0-9]\.[0-9]{2}\\])', 'gi'),
		re_endofweek = new RegExp('(End-of-Week)', 'gi'),
		re_endofshift = new RegExp('(End-of-Shift)', 'gi'),
		re_endofday = new RegExp('(End-of-Day)', 'gi');
	
	$('.meta-search-item-title-description div, .meta-search-item-title-description span').each( function() {
		var txt = $(this).html();
		txt = txt.replace( re_analysis_id, '<span class="bold">$1</span>' );
		txt = txt.replace( re_govecert_id, '<span class="bold">$1</span>' );
		txt = txt.replace( re_endofweek, '<span class="bold">$1</span>' );
		txt = txt.replace( re_endofshift, '<span class="bold">$1</span>' );
		txt = txt.replace( re_endofday, '<span class="bold">$1</span>' );
		
		/*** mark all keywords yellow ***/
		$.each( params.keywords, function (i, keyword) {
			var strippedKeyword = keyword.replace(/[+|\?.*^$(){}\[\]]/g, '' ), 
				re = new RegExp( strippedKeyword, 'gi' );
			txt = txt.replace( re, '<span class="search-mark-keyword">' + strippedKeyword + '</span>' );
		});
		$(this).html( txt );
	});

}

function showAdvancedSearchSettingsCallback ( params ) {
	$('#btn-meta-search-advanced-show').trigger('click');
}
