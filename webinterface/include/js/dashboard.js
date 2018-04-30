/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	$('#dashboard-minified-expand').click( function () {

		$('.selected-menu').removeClass('hover-submenu');
		$('.selected-menu').removeClass('selected-menu');
		$('.selected-submenu')
			.hide()
			.removeClass('selected-submenu');
		
		$('title').html('Taranis');
		
		$('#dashboard-submenu')
			.addClass('selected-submenu')
			.trigger('mouseover');
		$('#dashboard-submenu').trigger('mouseout')
		
		$.main.ajaxRequest({
			modName: 'dashboard',
			pageName: 'dashboard',
			action: 'getDashboardData',
			success: getDashboardDataCallback
		}, true);		
		
	});
	$('#icon-keyboard-shortcuts').click( function () {
		Mousetrap.trigger('?');
	});
});

function getDashboardDataCallback ( params ) {
	if ( params.dashboard && $('#dashboard-submenu').hasClass('selected-submenu') ) {
		$.each( params.dashboard, function (i, dashboardItem) {
			if ( $('#' + dashboardItem.name).length > 0 && dashboardItem.type ) {
				switch ( dashboardItem.type ) {
				case 'graph':
					if ( 'xaxis' in dashboardItem.options && 'tickFormatter' in dashboardItem.options.xaxis ) {
						dashboardItem.options.xaxis.tickFormatter = window[dashboardItem.options.xaxis.tickFormatter];
					}

					if ( 'yaxis' in dashboardItem.options && 'tickFormatter' in dashboardItem.options.yaxis && typeof window[dashboardItem.options.yaxis.tickFormatter] === 'function' ) {
						dashboardItem.options.yaxis.tickFormatter = window[dashboardItem.options.yaxis.tickFormatter];
					}

					if ( dashboardItem.options.legend && dashboardItem.options.legend.container ) {
						dashboardItem.options.legend.container = $('#' + dashboardItem.options.legend.container);
					}
					
					if ( $.isArray( dashboardItem.data ) && $.isPlainObject( dashboardItem.data[0] ) ) {
						$.plot( $('#' + dashboardItem.name), dashboardItem.data , dashboardItem.options );
					} else {
						$.plot( $('#' + dashboardItem.name), [ dashboardItem.data ], dashboardItem.options );
					}
					
					if ( dashboardItem.options.grid && dashboardItem.options.grid.hoverable ) {
						var previousPoint = null;
						$('#' + dashboardItem.name).bind("plothover", function (event, pos, item) {

							if ( item ) {

								if (previousPoint != item.dataIndex) {
									previousPoint = item.dataIndex;

									$("#dashboard-graph-datapoint").remove();

									var x = item.datapoint[0].toFixed(2),
									y = item.datapoint[1].toFixed(2);

									if ( dashboardItem.options.xaxis && dashboardItem.options.xaxis.mode == 'time' ) {
										x = new Date( Math.floor(x) );
									}

									var hours = ( ('' + x.getHours() ).length == 1 ) ? '0' + x.getHours() : x.getHours(),
										minutes = ( ( '' + x.getMinutes() ).length == 1 ) ? '0' + x.getMinutes() : x.getMinutes(),
										days = ( ( '' + x.getDate() ).length == 1 ) ? '0' + x.getDate() : x.getDate(),
										months = ( ( '' + ( x.getMonth() + 1 ) ).length == 1 ) ? '0' + ( x.getMonth() + 1 ) : ( x.getMonth() + 1 ),
										formattedTimestamp = hours + ':' + minutes + ' ' + days + '-' + months + '-' + x.getFullYear(),
										yAxisName = ( 'yaxisname' in dashboardItem ) ? ' ' + dashboardItem.yaxisname : '';

									if ( y == Math.floor(y) ) {
										y = Math.floor(y);
									}
									showGraphDataPoint( item.pageX, item.pageY, formattedTimestamp + "<br>" + y + yAxisName );
								}
							} else {
								$('#dashboard-graph-datapoint').remove();
								previousPoint = null;
							}
						});
					}

					break;
				case 'tagcloud':
					if ( dashboardItem.data ) {
						var tagCloudArray = new Array();
						$.each( dashboardItem.data, function (tag, tagCount) {
							if ( dashboardItem.link ) {
								var decodedTag = $('<div>').html(tag).text();
								tagCloudArray.push( {text: decodedTag, weight: tagCount, link: dashboardItem.link + decodedTag, html: { title: decodedTag }} );
							} else {
								tagCloudArray.push( {text: tag, weight: tagCount} );
							}
						});
					}
					$('#' + dashboardItem.name).jQCloud(tagCloudArray);
					
					break;
				}
			}
		});
	}
}

function showGraphDataPoint (x, y, contents) {

	$('<div id="dashboard-graph-datapoint">' + contents + '</div>').css( {
        top: y - 10,
        left: x + 10,
    }).appendTo("body").fadeIn(200);
}

function tickFormatterSuffix ( val, axis ) {
	if (val > 1000000)
	    return (val / 1000000).toFixed(axis.tickDecimals) + "M";
	else if (val > 1000)
	    return (val / 1000).toFixed(axis.tickDecimals) + "k";
	else
	    return val.toFixed(axis.tickDecimals);
}
