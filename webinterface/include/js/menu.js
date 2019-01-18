/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// hover on main-menu item
	$('.menu-item').hover( 
		function () {
			// hover in
			var hoverOn = $(this).attr('id').replace( /(.*?)\-.*/, '$1');
			$('.selected-submenu').hide();
			$('#' + hoverOn + '-submenu').show();
			$(this).addClass('hover-menu');
			
			if ( $(this).attr('id') != $('.selected-menu').attr('id') ) {
				$('.selected-menu').addClass('hover-submenu');
			}
		},
		function () {
			// hover out
			var hoverOut = $(this).attr('id').replace( /(.*?)\-.*/, '$1');
			$('#' + hoverOut + '-submenu').hide();
			$('.selected-submenu').show();
			$(this).removeClass('hover-menu');
			$('.selected-menu').removeClass('hover-submenu');
		}
	);

	// move mouse over the submenu
	$('.submenu').mouseover( function () {
		var hoverOn = $(this).attr('id').replace( /(.*?)\-.*/, '$1');
		if ( $('#' + hoverOn + '-menu').hasClass('top-menu-item') == false ) {
			$('#' + hoverOn + '-menu').addClass('hover-menu');
	
			if ( $('#' + hoverOn + '-menu').attr('id') != $('.selected-menu').attr('id') ) {
				$('.selected-menu').addClass('hover-submenu');
			}
		}
		$('.selected-submenu').hide();
		$(this).show();
	});

	// move mouse out of the area of the submenu
	$('.submenu').mouseout( function () {
		var hoverOn = $(this).attr('id').replace( /(.*?)\-.*/, '$1');
		$('#' + hoverOn + '-menu').removeClass('hover-menu');
		$('.selected-menu').removeClass('hover-submenu');
		$(this).hide();
		$('.selected-submenu').show();
	});	
	
	// click on a main-menu item or sub-menu item
	$('.menu-item, .submenu-item').click( function () {
		$('.selected-menu').removeClass('hover-submenu');
		$('.selected-menu').removeClass('selected-menu');
		$('.selected-submenu').removeClass('selected-submenu');
		
		var clickedOnId = ( $(this).hasClass('submenu-item') ) ? $(this).parent().attr('id'): $(this).attr('id') ;
		var clickedOn = clickedOnId.replace( /(.*?)\-.*/, '$1');
		
		$('title').html( 'Taranis &mdash; ' + firstLetterToUpper( clickedOn ) );
		
		$('#' + clickedOn + '-menu').addClass('selected-menu');
		$('#' + clickedOn + '-submenu').addClass('selected-submenu');
		
		if ( $(this).hasClass('submenu-item') ) {
			if ( clickedOn == 'assess' ) {
				stopAssessTimer();
				$('#super-secret-link').attr('data-callback', 'startAssessTimer');
			}
			if ( clickedOn == 'analyze' ) {
				$('#super-secret-link').attr('data-callback', 'getTagsForAnalyzePage');
			}
			if ( clickedOn == 'write' ) {
				var callback = '';
				switch ( $(this).attr('data-pubtype') ) {
					case 'advisory':
						callback = 'getTagsForAdvisoryPage';
						break;
					case 'forward':
						callback = 'getTagsForForwardPage';
						break;
					case 'eod':
						callback = 'getTagsForEndOfDayPage';
						break;
					case 'eos':
						callback = 'getTagsForEndOfShiftPage';
						break;
					case 'eow':
						callback = 'getTagsForEndOfWeekPage';
						break;
				}
				$('#super-secret-link').attr('data-callback', callback);
			}
			$('#super-secret-link')
				.attr('href', $(this).attr('data-url'))
				.trigger('click');
		}
	});
	
	// click on Assess main menu item will show all items of today for all allowed categories.
	$('#assess-menu').click( function () {
		stopAssessTimer()
		$('#super-secret-link').attr('data-callback', 'startAssessTimer');
		$('#super-secret-link').attr('href', 'assess/assess/displayAssess/');
		$('#super-secret-link').trigger('click');
	});
	
	// click on Analyze main menu item will show all analysis
	$('#analyze-menu').click( function () {
		$('#super-secret-link').attr('data-callback', 'getTagsForAnalyzePage');
		$('#super-secret-link').attr('href', 'analyze/analyze/displayAnalyze/');
		$('#super-secret-link').trigger('click');
	});	
	
	// click on Write main menu item will show the publication options
	$('#write-menu').click( function () {
		$('#super-secret-link').attr('href', 'write/publications/displayPublicationOptions/');
		$('#super-secret-link').trigger('click');
	});		

	// click on Publish main menu item will show the publication options
	$('#publish-menu').click( function () {
		$('#super-secret-link').attr('href', 'publish/publish/displayPublishOptions/');
		$('#super-secret-link').trigger('click');
	});		

	// click on Dossier main menu item will show all dossiers
	$('#dossier-menu').click( function () {
		$('#super-secret-link').attr('href', 'dossier/dossier/displayMyDossiers/');
		$('#super-secret-link').trigger('click');
	});

	// click on Report main menu item will show all report options
	$('#report-menu').click( function () {
		$('#super-secret-link').attr('href', 'report/report/displayReportOptions/');
		$('#super-secret-link').trigger('click');
	});
	
	// click on Tools main menu item will show the publication options
	$('#tools-menu').click( function () {
		$('#super-secret-link').attr('href', 'tools/toolspage/displayToolOptions/');
		$('#super-secret-link').trigger('click');
	});		
	
	// click on configuration, statistics or about menu item
	$('#configuration-menu, #statistics-menu, #about-menu').click( function () {
		$('.selected-menu').removeClass('hover-submenu');
		$('.selected-menu').removeClass('selected-menu');
		$('.selected-submenu')
			.hide()
			.removeClass('selected-submenu');
		
		$('title').html( 'Taranis &mdash; ' + firstLetterToUpper( $(this).attr('id').replace(/(.*?)-menu/, '$1') ) );
		
		$('#empty-submenu')
			.addClass('selected-submenu')
			.trigger('mouseover');
		$('#empty-submenu').trigger('mouseout')
	});
});

function setMenu ( menuItemID ) {

	if ( typeof menuItemID !== 'string' ) {
		menuItemID = $.main.lastRequest.modName;
	}

	$('.selected-menu').removeClass('hover-submenu');
	$('.selected-menu').removeClass('selected-menu');
	$('.selected-submenu').removeClass('selected-submenu');
	
	var clickedOn = menuItemID.replace( /(.*?)\-.*/, '$1');
	
	$('title').html( 'Taranis &mdash; ' + firstLetterToUpper( clickedOn ) );
	
	$('#' + clickedOn + '-menu').addClass('selected-menu');
	$('#' + clickedOn + '-submenu')
		.addClass('selected-submenu')
		.trigger('mouseover');
		
	$('.submenu').trigger('mouseout');
	
	return clickedOn;
}
