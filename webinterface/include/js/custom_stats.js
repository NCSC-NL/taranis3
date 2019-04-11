/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$.customStats = {};

$( function () {
	$.ajaxSetup({ cache: false });
	
	//click on button 'Get Statistics'
	$('#filters').on('click', '#btn-get-custom-statistics', function () {
		
		var selectedStat = $('#custom-statistics-selection').val();
		var selectedStatTitle = $('#custom-statistics-selection option:selected').text();
		
		var sendRequest = true;
		var inputData = new Object();
		$.each( $.customStats.sendData, function () {
			
			if ( this == 'selectedStatusLeft' || this == 'selectedPlatforms' ) {
				for ( var i = 0; i < $('#' + this + ' option').length; i++ ) {
					$('#' + this + ' option')[i].selected = true
				}
			}
			
			if ( this == 'selectedStatusLeft' && $('#selectedStatusLeft option').length == 0  ) {
				alert( 'At least one status has to be selected.' );
				sendRequest = false;
			}
			
			inputData[this] = $('#' + this ).val();
		});
		
		if ( sendRequest ) {
			$('#custom-statistics-content').attr( 'align', 'left' );
			
			var inputDataJSON = JSON.stringify( inputData );
				
			getStats( selectedStat, inputDataJSON, selectedStatTitle );
			$('#custom-statistics-content').css('opacity', '1' );
		}
	});
	
	//'Statistics type' selection
	$('#filters').on('change', '#custom-statistics-selection', function () {
		var selectedStat = $(this).val();
		
		$('#custom-statistics-content > *')
			.css('opacity', '0.5' )
			.prop('disabled', true);
		
		switch ( selectedStat ) {
		case 'selectStatistics':
			$('#form-custom-statistics').empty();
			break;
		case 'itemsCollectedCategory':
		case 'advisoriesClassification':
		case 'advisoriesAuthor':
		case 'advisoriesShType':
		case 'advisoriesConstituentType':
			$('#form-custom-statistics').empty();
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');
			
			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'clustering', 'presentation' ]; 
			
			break;
		case 'itemsCollectedStatus':
			$('#form-custom-statistics').empty();
			
			$('#tableFromUntill')
				.clone(true)
				.html('<tr id="trTitle"></tr><tr id="trInput"></tr>')
				.removeClass('borderDistance')
				.appendTo('#form-custom-statistics');
			
			$('#tdPresentationStyleTitle')
				.clone(true)
				.removeClass('borderDistance')
				.appendTo('#trTitle');

			$('#tdPresentationStyleInput')
				.clone(true)
				.appendTo('#trInput');
				
			$('#tdGetStatisticsButton')
				.clone(true)
				.appendTo('#trInput');
				
			$.customStats.sendData = [ 'presentation' ];
			
			break;
		case 'itemsSources':
			$('#form-custom-statistics').empty();
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');

			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$('td[id="tdClusteringTitle"]:visible').remove();
			$('td[id="tdSClusteringInput"]:visible').remove();			
			$('option[value="bar"]:visible').remove();
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'presentation' ]; 				
			
			break;
		case 'analysesTotal':
		case 'otherPublicationCreatedPublished':			
			$('#form-custom-statistics').empty();
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');

			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$('option[value="pie"]:visible').remove();
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'clustering', 'presentation' ];
			
			break;
		case 'analysesStatus':
			$('#form-custom-statistics').empty();

			$('#statusSelectionWrapper')
				.clone(true)
				.attr('id', 'statusSelectionWrapperClone')
				.appendTo('#form-custom-statistics');
			
			$('#statusSelectionTitleLeft:visible').text('Show statuses');
			$('#statusSelectionTitleRight:visible').text('Excluded statuses');
			$('#statusSelectionHelpText:visible').html('Add statuses to <i>Excluded<br />statuses</i> to exclude them <br />from the statistics.');
			
			$.each( $('#selectedStatusRight option:visible'), function(i) {
				$('#selectedStatusLeft').get(0).options[i] = this;
			});
			
			$('#tableFromUntill')
				.clone(true)
				.html('<tr id="trTitle"></tr><tr id="trInput"></tr>')
				.removeClass('borderDistance')
				.appendTo('#form-custom-statistics');
			
			$('#tdPresentationStyleTitle')
				.clone(true)
				.removeClass('borderDistance')
				.appendTo('#trTitle');

			$('#tdPresentationStyleInput')
				.clone(true)
				.appendTo('#trInput');
				
			$('#tdGetStatisticsButton')
				.clone(true)
				.appendTo('#trInput');
				
			$.customStats.sendData = [ 'presentation', 'selectedStatusLeft' ];
		
			break;
		case 'analysesCreatedClosed':
			$('#form-custom-statistics').empty();

			$('#statusSelectionWrapper')
			.clone(true)
			.attr('id', 'statusSelectionWrapperClone')
			.appendTo('#form-custom-statistics');			
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');

			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$('option[value="pie"]:visible').remove();
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'clustering', 'presentation', 'selectedStatusLeft' ];
			
			break;
		case 'analysesSourcesUsed':
		case 'advisoriesDate':			
			$('#form-custom-statistics').empty();
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');

			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$('td[id="tdClusteringTitle"]:visible').remove();
			$('td[id="tdSClusteringInput"]:visible').remove();
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'presentation' ];
			
			break;
		case 'advisoriesSentToCount':
			$('#form-custom-statistics').empty();
			
			initWeekSelection();
			
			$('#weekSelectionWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'weekSelectionWrapperClone');			

			$('#tdPresentationStyleTitle')
				.clone(true)
				.insertAfter('#tdWeekSelectionTitle');

			$('#tdPresentationStyleInput')
				.clone(true)
				.insertAfter('#tdNextWeek');
			
			$('#btn-get-custom-statistics')
				.clone(true)
				.insertAfter('#tdPresentationStyleInput');
			
			$('option[value="pie"]:visible').remove();
			
			$.customStats.sendData = [ 'selectedWeek', 'presentation' ];
			
			break;
		case 'advisoriesPlatform':
			$('#form-custom-statistics').empty();

			$('#platformSelectionWrapper')
			.clone(true)
			.attr('id', 'platformSelectionWrapperClone')
			.appendTo('#form-custom-statistics');			
			
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');
			
			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'clustering', 'presentation', 'selectedPlatforms' ];
			
			break;			
		case 'advisoriesDamage':
			$('#form-custom-statistics').empty();
			$('#fromUntillWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'fromUntillWrapperClone');

			$('#fromUntillWrapperClone').find('.date-pickers').each( function () {
				$(this).attr('id', 	$(this).attr('id').replace(/^(.*?)Org$/, '$1') );
				$(this).datepicker({dateFormat: "dd-mm-yy"});
			});
			
			$('option[value="bar"]:visible')
				.val('line')
				.text('Line chart');
			
			$.customStats.sendData = [ 'startDate', 'endDate', 'clustering', 'presentation' ];
		
			break;
		case 'otherSentToConstituentsPhotoUsage':
			$('#form-custom-statistics').empty();
			
			initWeekSelection();
			
			$('#weekSelectionWrapper')
				.clone(true)
				.appendTo('#form-custom-statistics')
				.attr('id', 'weekSelectionWrapperClone');			

			$('#tdPresentationStyleTitle')
				.clone(true)
				.insertAfter('#tdWeekSelectionTitle');

			$('#tdPresentationStyleInput')
				.clone(true)
				.insertAfter('#tdNextWeek');
			
			$('#btn-get-custom-statistics')
				.clone(true)
				.insertAfter('#tdPresentationStyleInput');
			
			$('option[value="pie"]:visible').remove();
			
			$.customStats.sendData = [ 'selectedWeek', 'presentation' ];
			
			break;
		case 'otherTop10ShConstituents':
			$('#form-custom-statistics').empty();
			
			$('#tableFromUntill')
				.clone(true)
				.html('<tr id="trTitle"></tr><tr id="trInput"></tr>')
				.removeClass('borderDistance')
				.appendTo('#form-custom-statistics');

			$('#tdPresentationStyleTitle')
				.clone(true)
				.appendTo('#trTitle');
				
			$('#tdPresentationStyleInput')
				.clone(true)
				.appendTo('#trInput');
			
			$('#tdGetStatisticsButton')
				.clone(true)
				.appendTo('#trInput');
			
			$('option[value="pie"]:visible').remove();
			
			$.customStats.sendData = [ 'presentation' ]; 
			
			break;
		default: 
			alert('illigal action');
		}
		
	});
});

function initWeekSelection () {
	var startOfWeek = new Date();
	var endOfWeek = new Date();

	var subtractDays = ( startOfWeek.getDay() > 0 ) ? startOfWeek.getDay() - 1 : 6;
	var addDays = ( endOfWeek.getDay() > 0 ) ? 7 - endOfWeek.getDay() : 0;
	
	startOfWeek.setDate( startOfWeek.getDate() - subtractDays );
	endOfWeek.setDate( endOfWeek.getDate() + addDays );

	var startOfWeekText = startOfWeek.getDate() + '-' + ( startOfWeek.getMonth() + 1 ) + '-' + startOfWeek.getFullYear();
	var endOfWeekText =  endOfWeek.getDate() + '-' + ( endOfWeek.getMonth() + 1 ) + '-' + endOfWeek.getFullYear();
	
	$('#selectedWeek').val( startOfWeekText + ' till ' + endOfWeekText);

	$('#btnPreviousWeek').click( function () {
		startOfWeek.setDate( startOfWeek.getDate() - 7 );
		startOfWeekText = startOfWeek.getDate() + '-' + ( startOfWeek.getMonth() + 1 ) + '-' + startOfWeek.getFullYear();

		endOfWeek.setDate( endOfWeek.getDate() - 7 );
		endOfWeekText = endOfWeek.getDate() + '-' + ( endOfWeek.getMonth() + 1 ) + '-' + endOfWeek.getFullYear();

		$('#selectedWeek').val( startOfWeekText + ' till ' + endOfWeekText );
	});

	$('#btnNextWeek').click( function () {
		startOfWeek.setDate( startOfWeek.getDate() + 7 );
		startOfWeekText = startOfWeek.getDate() + '-' + ( startOfWeek.getMonth() + 1 ) + '-' + startOfWeek.getFullYear();

		endOfWeek.setDate( endOfWeek.getDate() + 7 );
		endOfWeekText = endOfWeek.getDate() + '-' + ( endOfWeek.getMonth() + 1 ) + '-' + endOfWeek.getFullYear();

		$('#selectedWeek').val( startOfWeekText + ' till ' + endOfWeekText );
	});	
	
}

function getStats ( selectedStat, inputDataJSON, selectedStatTitle ) {
	
	
	$.main.ajaxRequest({
		modName: 'statistics',
		pageName: 'custom_stats',
		action: 'getCustomStats',
		queryString: 'stat=' + selectedStat + '&input=' + inputDataJSON + '&title=' + selectedStatTitle,				
		success: getStatsCallback
	});
}

function getStatsCallback ( params ) {
	var data = params.stats;
	if ( data.error != undefined ) {
		$('#custom-statistics-content').html( data.error );
	} else {
		
		$('#custom-statistics-content').attr( 'align', 'center' );
		
		switch ( data.type ) {
		case 'bar':
			$('#custom-statistics-content').empty();

			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btnXAxisTitle' })
				.val( 'Change X axis title direction' )
				.click( function () {
						getStats( 'xAxisTitleBarChart', data.json, '' );
				})
				.appendTo('#custom-statistics-content');				
			
			$('<p>').insertAfter('#btnXAxisTitle');
			
			var img = new Image();
			
			$(img).load( 
				function () {
					$(this).hide();
					$(this).fadeIn();
				})
				.attr( 'src', $.main.webroot + '/custom-stats/' + data.statImageName )
				.appendTo('#custom-statistics-content');
			
			break;
		case 'pie':
			$('#custom-statistics-content').empty();

			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btnRotatePie' })
				.val('Rotate chart 45°')
				.click( function () {
						getStats( 'rotatePieChart', data.json, '' );
				})
				.appendTo('#custom-statistics-content');

			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btnIncreasePie' })
				.addClass('borderDistance')
				.val('Increase pie radius')
				.click( function () {
					getStats( 'increasePieChart', data.json, '' );
				})
				.appendTo('#custom-statistics-content');
			
			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btnDecreasePie' })
				.addClass('borderDistance')
				.val('Decrease pie radius')
				.click( function () {
					getStats( 'decreasePieChart', data.json, '' );
				})
				.appendTo('#custom-statistics-content');						
			
			$('<p>').insertAfter('#btnDecreasePie');				

			var img = new Image();
			
			$(img).load( 
				function () {
					$(this).hide();
					$(this).fadeIn();
				})
				.attr( 'src', $.main.webroot + '/custom-stats/' + data.statImageName )
				.appendTo('#custom-statistics-content');
			
			break;
		case 'text':
			$('#custom-statistics-content').empty();
			
			$('<div>')
				.attr({'id': 'textPresentationDiv', 'align': 'left'})
				.css({ 'height' : '100%', 'width': '720px', 'border': '1px solid #AAAAAA' })
				.appendTo( '#custom-statistics-content' );
			
			$('<textarea />')
				.attr({'id' : 'textPresentation', 'readonly': 'readonly'})
				.text( data.text )
				.css({ 'border' : '0px', 'width': '720px', 'height' : data.lineCount + 'em', 'line-height' : '1em' })
				.appendTo( '#textPresentationDiv' );

			if ( data.lineWidth > 100 ) {
				$('#textPresentationDiv').css({ 'overflow-x' : 'scroll' });
				$('#textPresentation').css({ 'width' : data.lineWidth + 'em' });
			}
			
			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btn_selectText' })
				.val('Select text')
				.click( function () {
					$('#textPresentation').select();
				})
				.insertBefore('#textPresentationDiv');
			
			$('<p>').insertAfter('#btn_selectText');
			
			break;
		case 'line':
			$('#custom-statistics-content').empty();

			$('<input />')
				.addClass('button')
				.attr({ 'type' : 'button', 'id': 'btnXAxisTitle' })
				.val( 'Change X axis title direction' )
				.click( function () {
						getStats( 'xAxisTitleLineChart', data.json, '' );
				})
				.appendTo('#custom-statistics-content');				
			
			$('<p>').insertAfter('#btnXAxisTitle');
			
			var img = new Image();
			
			$(img).load( 
				function () {
					$(this).hide();
					$(this).fadeIn();
				})
				.attr( 'src', $.main.webroot + '/custom-stats/' + data.statImageName )
				.appendTo('#custom-statistics-content');
			
			break;						
		}
	}
}
