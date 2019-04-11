/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view feed digest details
	$('#content').on( 'click', '.btn-edit-feeddigest, .btn-view-feeddigest', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'feed_digest',
			action: 'openDialogFeedDigestDetails',
			queryString: 'tool=feed_digest&id=' + $(this).attr('data-id'),
			success: function (openDetailsParams) {
				
				var context = $('#form-feeddigest-details[data-id="' + openDetailsParams.id + '"]');
				
				if ( openDetailsParams.writeRight == 1 ) {
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {

								var reEmailAddress = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;

								if ( $('#feeddigest-details-url', context).val() == '' ) {
									alert("Please specify a valid URL.");
								} else if ( $('#feeddigest-details-toaddress', context).val() == '' || reEmailAddress.test( $('#feeddigest-details-toaddress', context).val() ) == false ) {
									alert("Please specify a valid email address.");
								} else {
									$.main.ajaxRequest({
										modName: 'tools',
										pageName: 'feed_digest',
										action: 'saveFeedDigest',
										queryString: 'tool=feed_digest&id=' + openDetailsParams.id + '&' + $(context).serializeWithSpaces(),
										success: function (saveParams) {
											if ( saveParams.saveOk ) {
												$('.feeddigest-item[data-id="' + saveParams.id + '"]').html( saveParams.itemHtml );
												$.main.activeDialog.dialog('close');
											} else {
												alert(saveParams.message);
											}
										}
									});
								}
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);
					
					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
					
				} else {
					$('input, select, textarea', context).each( function (index) {
						$(this).prop('disabled', true);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Feed digest details');
		dialog.dialog('option', 'width', '700px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a feed digest settings
	$('#content').on( 'click', '.btn-delete-feeddigest', function () {
		if ( confirm('Are you sure you want to delete the feed?') ) {
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'feed_digest',
				action: 'deleteFeedDigest',
				queryString: 'tool=feed_digest&id=' + $(this).attr('data-id'),
				success: function (deleteParams) {
					if ( deleteParams.deleteOk ) {
						$('.feeddigest-item[data-id="' + deleteParams.id + '"]').remove();
					} else {
						alert(deleteParams.message);
					}
				}
			});
		}
	});
	
	// add a new feed digest
	$('#filters').on( 'click', '#btn-add-feeddigest', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'feed_digest',
			action: 'openDialogNewFeedDigest',
			queryString: 'tool=feed_digest',
			success: function (params) {
				var context = $('#form-feeddigest-details[data-id="NEW"]');
				
				$.main.activeDialog.dialog('option', 'buttons', [
					{
						text: 'Save',
						click: function () {
		
							var reEmailAddress = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
							
							if ( $('#feeddigest-details-url', context).val() == '' ) {
								alert("Please specify a valid URL.");
							} else if ( $('#feeddigest-details-toaddress', context).val() == '' || reEmailAddress.test( $('#feeddigest-details-toaddress', context).val() ) == false ) {
								alert("Please specify a valid email address.");
							} else {
		
								$.main.ajaxRequest({
									modName: 'tools',
									pageName: 'feed_digest',
									action: 'addFeedDigest',
									queryString: 'tool=feed_digest&' + $(context).serializeWithSpaces(),
									success: function (addParams) {
										if ( addParams.addOk ) {
											$('#feeddigest-content-heading').after( addParams.itemHtml );
											$('.no-items').remove();
											$.main.activeDialog.dialog('close');
										} else {
											alert(addParams.message)
										}
									}
								});
							}
						}
					},
					{
						text: 'Cancel',
						click: function () { $(this).dialog('close') }
					}
				]);
				
				$('input[type="text"]', context).keypress( function (event) {
					return checkEnter(event);
				});
			}
		});		
		
		dialog.dialog('option', 'title', 'Add new feed digest');
		dialog.dialog('option', 'width', '700px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});
});
