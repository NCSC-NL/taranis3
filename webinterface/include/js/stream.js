/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view stream details
	$('#content').on( 'click', '.btn-edit-stream, .btn-view-stream', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'stream',
			action: 'openDialogStreamDetails',
			queryString: 'tool=streams&id=' + $(this).attr('data-id'),
			success: function (openDetailsParams) {
				
				var context = $('#form-stream-details[data-id="' + openDetailsParams.id + '"]');
				
				if ( openDetailsParams.writeRight == 1 ) {
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {

								if ( $('#stream-details-description', context).val() == '' ) {
									alert("Please specify a description.");
								} else if ( $('#stream-details-transition-time', context).val() == '' ) {
									alert("Please specify a transition time in seconds.");
								} else {
									$.main.ajaxRequest({
										modName: 'tools',
										pageName: 'stream',
										action: 'saveStream',
										queryString: 'tool=streams&id=' + openDetailsParams.id + '&' + $(context).serializeWithSpaces(),
										success: function (saveParams) {
											if ( saveParams.saveOk ) {
												$('.stream-item[data-id="' + saveParams.id + '"]').html( saveParams.itemHtml );
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
		
		dialog.dialog('option', 'title', 'Stream details');
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
	
	// delete a stream
	$('#content').on( 'click', '.btn-delete-stream', function () {
		if ( confirm('Are you sure you want to delete the stream?') ) {
			$.main.ajaxRequest({
				modName: 'tools',
				pageName: 'stream',
				action: 'deleteStream',
				queryString: 'tool=streams&id=' + $(this).attr('data-id'),
				success: function (deleteParams) {
					if ( deleteParams.deleteOk ) {
						$('.stream-item[data-id="' + deleteParams.id + '"]').remove();
					} else {
						alert(deleteParams.message);
					}
				}
			});
		}
	});
	
	// add a new stream
	$('#filters').on( 'click', '#btn-add-stream', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'tools',
			pageName: 'stream',
			action: 'openDialogNewStream',
			queryString: 'tool=streams',
			success: function (params) {
				var context = $('#form-stream-details[data-id="NEW"]');
				
				$.main.activeDialog.dialog('option', 'buttons', [
					{
						text: 'Save',
						click: function () {
		
							if ( $('#stream-details-description', context).val() == '' ) {
								alert("Please specify a description.");
							} else if ( $('#stream-details-transition-time', context).val() == '' ) {
								alert("Please specify a transition time in seconds.");
							} else {
		
								$.main.ajaxRequest({
									modName: 'tools',
									pageName: 'stream',
									action: 'addStream',
									queryString: 'tool=streams&' + $(context).serializeWithSpaces(),
									success: function (addParams) {
										if ( addParams.addOk ) {
											$('#stream-content-heading').after( addParams.itemHtml );
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
		
		dialog.dialog('option', 'title', 'Add new stream');
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
