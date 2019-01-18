/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

/* taranis.sorter is expecting the following structure:
 *
 * < id='content'>
 *   < class='content-heading'>
 *     < class='content-heading-sorter' data-column='..'>
 *       < class='fa fa-sort'>
 *   < class='item-row' data-id='..'>
 *     < data-cell='..' data-sorttype='number' data-sort='..'>
 *     < data-cell='..' data-sorttype='number' data-sort='..'>
 *     etc..
 *   < class='item-row' data-id='..'>
 *     < data-cell='..' data-sorttype='number' data-sort='..'>
 *     < data-cell='..' data-sorttype='number' data-sort='..'>
 *     etc..
 *   
 * data-column: attribute value should correspond with a data-cell attribute value
 * data-cell: see data-column
 * data-sorttype: can be 'number' or 'string' and is optional. Defaults to string.
 * data-sort: optional sorting value. If not set, the text contents of the cell will be used as sorting value
 *
*/

$( function () {
	$('#content').on('click', '.content-heading-sorter', function () {
		var sortingColumn = $(this);
		if ( sortingColumn.attr('data-column').length > 0 ) {
			var unorderedList = new Array(),
				sortOn = sortingColumn.attr('data-column'),
				sortingOrderClass = 'fa-sort-desc';
			var cellsToSort = $('[data-cell="' + sortOn + '"]');

			cellsToSort.each( function (i, cell) {
				var rowId = $(cell).parents('.item-row').attr('data-id');
				var sortAttr = $(cell).attr('data-sort');
				var sortValue = ( typeof sortAttr !== 'undefined' && sortAttr !== false ) ? sortAttr : $(cell).text();
				unorderedList.push( { id: rowId, sortValue: sortValue } );
			});
			
			if ( cellsToSort.first().attr('data-sorttype') == 'number' ) {
				orderedList = unorderedList.sort(compareNumbers);
			} else if ( cellsToSort.first().attr('data-sorttype') == 'string' || typeof cellsToSort.first().attr('data-sorttype') === 'undefined' ) {
				orderedList = unorderedList.sort(compareStrings);
			}
			
			if ( orderedList[0].sortValue !== orderedList[orderedList.length -1].sortValue ) {
				
				if ( unorderedList[0].sortValue !== orderedList[0].sortValue || 
					sortingColumn.children('.fa').hasClass('fa-sort') || 
					sortingColumn.children('.fa').hasClass('fa-sort-asc')
				) {
					orderedList.reverse(); // this reverse has the opposite effect because of the insertAfter below! 
				} else if ( sortingColumn.children('.fa').hasClass('fa-sort-desc') ) {
					sortingOrderClass = 'fa-sort-asc';
				}
				
				$.each( orderedList, function(i,cellInfo) {
					$('.item-row[data-id="' + cellInfo.id + '"]').insertAfter('.content-heading');
				});
			}
			
			$('.fa-sort-desc, .fa-sort-asc').addClass('fa-sort').removeClass('fa-sort-desc fa-sort-asc');
			sortingColumn.children('.fa').removeClass('fa-sort').addClass(sortingOrderClass);
			
		}
	});
});

function compareStrings(a, b) {
	return a.sortValue.toLowerCase().localeCompare(b.sortValue.toLowerCase());
}

function compareNumbers(a, b) {
	return a.sortValue - b.sortValue;
}
