/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

// short-cuts overview in templates/assess_shortcuts.tt

$( function () {
	
	/* scrolling through list */
	
	// move down one item
	Mousetrap.bind('j', function (e) {
		var currentItem = $('.item-arrow:visible').parent('.assess-item');
		selectNextItem( currentItem );
		return false;
	});
	
	// move up one item
	Mousetrap.bind('k', function (e) {
		var currentItem = $('.item-arrow:visible').parent('.assess-item');
		var previousItem = currentItem.prevAll('.assess-item:visible').first();

		if ( previousItem.hasClass('assess-item') ) {
			$('.item-arrow:visible').hide();
			
			previousItem.children('.item-arrow').show();

			var previousPreviousItem = previousItem.prevAll('.assess-item:visible').first();
			var previousPreviousItemPosition = previousPreviousItem.position();
			
			if ( previousPreviousItemPosition ) {
				$(document).scrollTop( previousPreviousItemPosition.top );
			}
		}
		return false;
	});
	
	/* operations on list */
	
	// check all items
	Mousetrap.bind('c', function (e) {
		$('#checkAllTop').trigger('click')
		return false;
	});
	
	// uncheck all items
	Mousetrap.bind('u', function (e) {
		$('#unCheckAllTop').trigger('click');
		return false;
	});

	// mark all selected items as read
	Mousetrap.bind('r', function (e) {
		$('#btn_markRead').trigger('click');
		return false;
	});

	// mark all selected items as important
	Mousetrap.bind('i', function (e) {
		$('#btn_markImportant').trigger('click');
		return false;
	});

	// open dialog for bulk analysis
	Mousetrap.bind('b', function (e) {
		$('#btn_bulkAnalysis').trigger('click');
		return false;
	});
	
	// open dialog for multiple analysis
	Mousetrap.bind('p', function (e) {
		$('#btn_multipleAnalyses').trigger('click');
		return false;
	});
	
	// load more assess items
	Mousetrap.bind('+', function (e) {
		$('#btn-show-more-items').trigger('click');
		return false;
	});

	/* operations on 1 item */

	function this_item() {
		return $('.item-arrow:visible').parent('.assess-item');
	};

	function item_click(which) {
		var icon = this_item().find('.icon-block').children(which);
		if(icon.length > 0 ) icon.trigger('click');
	};

	// open a link (this can trigger a openDialog or opening the link in a new browser tab)
	Mousetrap.bind('l', function (e) {
		var itemTitleBlock = this_item().find('.assess-item-title');

		if ( itemTitleBlock.children('.span-link').length > 0 ) {
			itemTitleBlock.children('.span-link').trigger('click');
		} else {
			itemTitleBlock.children('a').find('span').trigger('click');
		}
		return false;
	});
	
	// openDialog to create an analysis
	Mousetrap.bind('a', function (e) {
		item_click('.img-assess-item-analyze');
		return false;
	});

	// openDialog to mail item
	Mousetrap.bind('m', function (e) {
		item_click('.img-assess-item-mail');
		return false;
	});

	// openDialog to tag item
	Mousetrap.bind('t', function (e) {
		item_click('.img-edit-tags');
		return false;
	});

	// openDialog to view item details
	Mousetrap.bind('v', function (e) {
		item_click('.img-assess-item-details');
		return false;
	});

	Mousetrap.bind('e', function (e) {
		item_click('.clipboard');
		return false;
	});

	// = unlink clustered item
	
	// check or uncheck checkbox of item
	Mousetrap.bind([ 's', 'space' ], function (e) {
		e.preventDefault();
		if ( $(':focus').attr('type') == 'button' || $(':focus').attr('type') == 'checkbox' ) {
			$(':focus').blur();
		}
		var selector = this_item().find('.assess-item-select-input');
		if (selector.length > 0 ) {
			selector.prop('checked', ! selector.prop('checked'));
		}
		return false;
	});
	
	// fold or unfold clustered items
	Mousetrap.bind('f', function (e) {
		var currentItem = this_item();
		if ( currentItem.hasClass( 'item-top-cluster-row' ) ) {
			currentItem.find('.item-clustering-toggle-items').trigger('click');
		}
		return false;
	});

	// select all items above this one
	Mousetrap.bind('^', function (e) {
		var this_id = this_item().attr('id');
		var take    = 1;
		$('.assess-item').each(function () {
			if(take) $(this).find('.assess-item-select-input').prop('checked', 1);
			if(this_id==$(this).attr('id')) take = 0;
		});
		return false;
	});

	// select all items from this one and below
	Mousetrap.bind('!', function (e) {
		var this_id = this_item().attr('id');
		var take    = 0;
		$('.assess-item').each(function () {
			if(this_id==$(this).attr('id')) take = 1;
			if(take) $(this).find('.assess-item-select-input').prop('checked', 1);
		});
		return false;
	});

	// show shortcuts overview
	Mousetrap.bind('?', function (e) {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>Loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess',
			action: 'displayAssessShortcuts'
		});
		
		dialog.dialog('open');
		
		dialog.dialog('option', 'title', 'Shortcuts overview');
		dialog.dialog('option', 'width', '400px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		return false;
	});
});
