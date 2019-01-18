/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
    // check the item checkboxes
    $('#content-wrapper').on('click', '#checkAllTop', function () {
        $('.pending-item-select-input:visible').prop('checked', true);
    });

    // uncheck the item checkboxes  
    $('#content-wrapper').on('click', '#unCheckAllTop', function () {
        $('.pending-item-select-input:visible').prop('checked', false);
    });

	// add pending item to dossier
	function addPendingItem(itemType, tagID, itemID, qs, success) {
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_pending',
			action: 'addPendingItem',
			queryString: qs+'&itemid='+itemID+'&type='+itemType+'&tagid='+tagID,
			success: function (addParams) {
				if ( addParams.saveOk == 1 ) {
					$('.item-row[data-itemid="' + itemID.replace(/%/g, '\\%') + '"][data-tagid="' + tagID + '"][data-itemtype="' + itemType + '"]').remove();
					if(success) success();
				} else {
					alert( addParams.message );
				}
			}
		});
	}

	function addPendingItems($items, done) {
		var $add     = $items.eq(0);
		if($add.length==0) return done();

		var $row      = $add.parents('.item-row');
		var itemID    = $row.attr('data-itemid'),
			itemType  = $row.attr('data-itemtype'),
			tagID     = $row.attr('data-tagid'),
			dossierID = $row.attr('data-dossier');

		var qs = "event_timtestamp_date=" + $row.find(".event_date").text()
		       + "&event_timtestamp_time=" + $row.find(".event_time").text()
		       + "&tlp=" + $("#dossier-pending-tlp option:selected").val()
		       + "&dossier=" + dossierID;

		addPendingItem(itemType, tagID, itemID, qs,
			function () { addPendingItems($items.not(":eq(0)"), done)} );
		return true;
	}

	// add all checked items to the dossier
    $('#content-wrapper').on('click', '#btn_addPendingBulk', function () {
		var items = [];
		var $selected = $('.pending-item-select-input:checked');
		if($selected.length==0) {
			alert('First select one or more pending items');
			return false;
		}

		$selected.each(function () {
			var $row = $(this).parents('.item-row');
			var itemID = $row.attr('data-itemid'),
				itemType = $row.attr('data-itemtype'),
				tagID = $row.attr('data-tagid');
			items.push(itemType + ',' + tagID + ','+ itemID);
		});

		var dialog = $('<div>').newDialog();
        dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_pending',
			action: 'openDialogAddPendingBulk',
			queryString: 'items=' + items.join(':'),
   			success: function (params) {
				dialog.dialog('option', 'buttons', [ {
					text: 'Save',
					click: function () {
						// avoid sending all updates at the same time
						addPendingItems($('.pending-item-take:checked'),
							function(){ $.main.activeDialog.dialog('close') });
						return false;
					}
				}, {
					text: 'Cancel',
					click: function () { $(this).dialog('close') }
				}])
			}
		});

		dialog.dialog('option', 'title', 'Add pending items to dossiers, bulk');
		dialog.dialog('option', 'width', '500px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});

	// add one item to some dossier
	$('#content').on('click', '.btn-add-item-to-dossier', function () {
		var $row = $(this).parents('.item-row');
		var itemID = $row.attr('data-itemid'),
			itemType = $row.attr('data-itemtype'),
			tagID = $row.attr('data-tagid'),
			dialog = $('<div>').newDialog();
		
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_pending',
			action: 'openDialogAddPendingItem',
			queryString: 'id=' + itemID + '&type=' + itemType + '&tagid=' + tagID,
			success: function (params) {
				dialog.dialog('option', 'buttons', [ {
					text: 'Save',
					click: function () {
						var timeRe = /^((0|1)[0-9]|2[0-3]):[0-5][0-9]$/,
							form = $('#form-dossier-add-pending-item');
						
						if ( timeRe.test( $('#dossier-pending-event-timestamp-time').val() ) == false ) {
							alert("Please specify a valid time.");
						} else if ( validateForm(['dossier-pending-event-timestamp-date']) ) {

							$(":button:contains('Save'), :button:contains('Cancel')")
								.prop('disabled', true)
								.addClass('ui-state-disabled');
							
							$("<div>")
								.html('please wait...')
								.dialog({
									modal: true,
									title: 'wait...',
									appendTo: form,
									closeOnEscape: false,
									position: 'top',
									open: function() {
										$(".ui-dialog-titlebar-close", $(form) ).hide();
									}
								});

							addPendingItem(itemType, tagID, itemID,
 								$('#form-dossier-add-pending-item').serializeWithSpaces(),
								function(){ $.main.activeDialog.dialog('close') }
							);
						}
					}
				}, {
					text: 'Cancel',
					click: function () { $(this).dialog('close') }
				}]);
				
				// add timepicker to time input elements
				$('.time').each( function() {
					$(this).timepicker({ 'scrollDefaultNow': true, 'timeFormat': 'H:i' });
				});
			}
		});

		dialog.dialog('option', 'title', 'Add pending item to dossier');
		dialog.dialog('option', 'width', '500px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
		
	});
	
	// discard pending item
	$('#content').on('click', '.btn-discard-pending-item', function () {
		if ( confirm('Are you realy realy sure you want to discard this pending item?') ) {
			var $row = $(this).parents('.item-row');
			var itemID = $row.attr('data-itemid'),
				itemType = $row.attr('data-itemtype'),
				tagID = $row.attr('data-tagid');
			
			$.main.ajaxRequest({
				modName: 'dossier',
				pageName: 'dossier_pending',
				action: 'discardPendingItem',
				queryString: 'itemid=' + itemID + '&type=' + itemType + '&tagid=' + tagID,
				success: function (params) {
					if ( params.saveOk == 1 ) {
						$('.item-row[data-itemid="' + itemID.replace(/%/g, '\\%') + '"][data-tagid="' + tagID + '"][data-itemtype="' + itemType + '"]').remove();
					} else {
						alert( params.message );
					}
				}
			});
		}
	});
});
