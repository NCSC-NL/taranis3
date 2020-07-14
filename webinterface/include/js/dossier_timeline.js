/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	// show/hide notes of dossier items
	$('#content').on('click', '.dossier-item-timeline-notes-expand', function () {
		var notes = $(this).parent().siblings('.dossier-item-timeline-notes');
		if ( notes.is(':visible') == false ) {
			notes.show();
		} else {
			notes.hide();
		}
	});
	
	// downloadframe for downloading uploaded files in comments
	$(document).on('click', '.dossier-item-link-file', function () {
		$('#downloadFrame').attr( 'src', 'loadfile/dossier/dossier_timeline/loadNoteFile?params=' + JSON.stringify( { fileID: $(this).attr('data-fileid') } ) );		
	})
	
	// add note to dossier item
	$('#content').on('click', '.dossier-item-timeline-add-note', function () {
		
		var itemID = $(this).attr('data-itemid');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_timeline',
			action: 'openDialogNewItemNote',
			success: function (params) {
				
				if ( params.writeRight == 1 ) {
					var context = $('#form-dossier-timeline-note[data-id="NEW"]');
					
					dialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {

								var noteData = new FormData();
								$('.dossier-item-note-files').each( function (i) {
									if ( $(this)[0].files[0] ) {
										noteData.append('noteFiles', $(this)[0].files[0] );
									}
								});

								var paramsObj = $('#form-dossier-timeline-note').serializeHash();
								paramsObj.dossier_item_id = itemID;

								noteData.append('params', JSON.stringify(paramsObj) );

								$.ajax({
									url: $.main.scriptroot + '/load/dossier/dossier_timeline/saveNewItemNote',
									data: noteData,
									processData: false,
									type: 'POST',
									contentType: false,
									headers: {
										'X-Taranis-CSRF-Token': $.main.csrfToken,
									},
									dataType: 'JSON'
								}).done(function (result) {
									if ( result.page.params.saveOk ) {
										
										$.main.ajaxRequest({
											modName: 'dossier',
											pageName: 'dossier_timeline',
											action: 'getItemNoteHtml',
											queryString: 'id=' + result.page.params.noteID,
											success: function (itemHtmlParams) {
												$('.dossier-item-timeline-notes[data-itemid="' + itemID + '"]').append( itemHtmlParams.itemHtml );
											}
										});
										
										$.main.activeDialog.dialog('close');
									} else {
										alert( result.page.params.message )
									}
								}).fail(function () {
									alert('Oh dear...');
								});
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);
					
					// remove url, ticket or file input elements
					$('.btn-delete-note-url, .btn-delete-note-ticket, .btn-delete-note-file').click( function () {
						$(this).parent().remove();
					});
					
					// add url, ticket or file input elements
					$('#note-add-url, #note-add-ticket, #note-add-file').click( function () {
						var cloneBlock = $(this).siblings('.hidden'); 
						var clonedBlock = cloneBlock
							.clone(true,true)
							.insertBefore(cloneBlock)
							.removeClass('hidden');
						
						clonedBlock.children('input:first').focus();
					});

					// change constituent group selection; automagicly changes the contents for individual selection
					$('#dossier-note-constituent-group').change( function () {
						if ( $(this).val() != '' ) {
							$('#dossier-note-constituent-individual option').each( function () {
								$(this).hide();
							});
							$.each( JSON.parse( $(this).val() ), function(i, individualID) {
								$('#dossier-note-constituent-individual option[value="' + individualID + '"]').show()
							});
						} else {
							$('#dossier-note-constituent-individual option').each( function () {
								$(this).show();
							});
						}
						
						$('#dossier-note-constituent-individual option:selected').prop('selected', false);
						$('#dossier-note-constituent-individual option[value=""]').prop('selected', true);
					});

					// add constituent group to note text
					$('#btn-dossier-note-insert-group').click( function () {
						if ( $('#dossier-note-constituent-group').val() != '' ) {
							$('#note-comment-text').textrange('insert', '[[' + $('#dossier-note-constituent-group option:selected').text() + ']]' );
						}
					});

					// add constituent individual to note text
					$('#btn-dossier-note-insert-individual').click( function () {
						if ( $('#dossier-note-constituent-individual').val() != '' ) {
							$('#note-comment-text').textrange('insert', '[[' + $('#dossier-note-constituent-individual option:selected').text() + ']]' );
						}
					});
					
					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Add comment');
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

	// edit dossier item on timeline. Change TLP classification or timestamp on timeline
	$('#content').on( 'click', '.btn-edit-dossier-item', function () {

		var itemID = $(this).attr('data-itemid');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_timeline',
			queryString: 'id=' + itemID,
			action: 'openDialogDossierItemDetails',
			success: function (params) {
				if ( params.writeRight == 1 ) {
					var dossierID = $('#form-dossier-item-details').attr('data-dossierid');
					
					dialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								var timeRe = /^((0|1)[0-9]|2[0-3]):[0-5][0-9]$/;
								if ( timeRe.test( $('#dossier-item-event-timestamp-time').val() ) == false ) {
									alert("Please specify a valid time.");
								} else if ( validateForm(['dossier-item-event-timestamp-date']) ) {

									$.main.ajaxRequest({
										modName: 'dossier',
										pageName: 'dossier_timeline',
										action: 'saveDossierItemDetails',
										queryString: $('#form-dossier-item-details').serializeWithSpaces() + '&id=' + itemID,
										success: function (addParams) {
											if ( addParams.isChanged == 1 ) {
												if ( addParams.saveOk == 1 ) {
													
													$.main.ajaxRequest({
														modName: 'dossier',
														pageName: 'dossier_timeline',
														action: 'displayDossierTimeline',
														queryString: 'id=' + dossierID,
														success: null
													});
													
													$.main.activeDialog.dialog('close');
												} else {
													alert( addParams.message );
												}
											} else {
												$.main.activeDialog.dialog('close');
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
					
					// add timepicker to time input elements
					$('.time').each( function() {
						$(this).timepicker({ 'scrollDefaultNow': true, 'timeFormat': 'H:i' });
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Edit dossier item');
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
	
	// view note details
	$('#content').on( 'click', '.dossier-note-details-link', function () {

		var itemID = $(this).attr('data-itemid');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_note',
			queryString: 'id=' + itemID,
			action: 'openDialogNoteDetails',
			success: null
		});
		
		dialog.dialog('option', 'title', 'View note details');
		dialog.dialog('option', 'width', '680px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});
	
	// view other dossier notes for selected item
	$('#content').on('click', '.dossier-item-timeline-notes-count', function () {
		var dossierID = $(this).attr('data-dossierid'),
			productID = $(this).attr('data-productid'),
			itemType = $(this).attr('data-itemtype');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_timeline',
			queryString: 'dossierid=' + dossierID + '&productid=' + productID + '&itemtype=' + itemType,
			action: 'openDialogNotesOtherDossier',
			success: null
		});
		
		dialog.dialog('option', 'title', 'View notes');
		dialog.dialog('option', 'width', '680px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// mail dossier timeline item.
	$('#content').on('click', '.btn-dossier-item-mail', function () {
		var dossierItemID = $(this).attr('data-itemid'),
			dossierItemType = $(this).attr('data-itemtype');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_timeline',
			action: 'openDialogDossierMailItem',
			queryString: 'itemid=' + dossierItemID + '&itemtype=' + dossierItemType,
			success: function (params) {
				
				// filter recipients
				$('#dossier-search-mail-to').keyup( function () {
					var filterText = $(this).val();
					if ( filterText != '' ) {
						$("#dossier-mail-to option").hide();
						$("#dossier-mail-to option:contains('" + filterText + "')").show();
					} else {
						$("#dossier-mail-to option").show();
					}
				});
				
				// add recipient to recipientlist
				$("#dossier-mail-to option").dblclick( function () {
					var address = $(this).val(),
						titleText = $(this).text()
						optionID = $(this).attr('id');
					
					if ( $('.dossier-mail-to-recipient[data-optionid="' + optionID + '"]').length == 0 ) { 
						$('<div>')
							.addClass('dossier-mail-to-recipient block')
							.text( address )
							.attr({
								'title':titleText,
								'data-optionid': optionID
							})
							.append(
								$('<input>')
									.addClass('button')
									.val('X')
									.attr('type', 'button')
									.click( function () {
										$('#' + $(this).parent().attr('data-optionid') ).removeClass('option-sh-in-use');
										$(this).parent().remove();
									})
							)
							.appendTo('#dossier-mail-to-recipient-list');
						
						$(this).addClass('option-sh-in-use');
					}
				});
				
				// add an address
				$('#btn-dossier-mail-item-add-address').click( function () {
					var emailAddress = $('#dossier-mail-item-extra-address').val(),
						re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;

					if ( emailAddress != '' && re.test( emailAddress ) ) {
						
						$('<div>')
						.addClass('dossier-mail-to-recipient block')
						.text( emailAddress )
						.attr({
							'title':emailAddress,
						})
						.append(
							$('<input>')
								.addClass('button')
								.val('X')
								.attr('type', 'button')
								.click( function () {
									$(this).parent().remove();
								})
						)
						.appendTo('#dossier-mail-to-recipient-list');
						$('#dossier-mail-item-extra-address').val('');
					} else {
						alert('Please enter a valid email address');
					}
				});
				
				$('#dossier-comments').change( function () {
					if ( $(this).is(':checked') == true ) {
						$('#dossier-mail-description-comments')
							.css({'backgroundColor': '#DFFFE9'})
							.prop('disabled', false);
					} else {
						$('#dossier-mail-description-comments')
							.css({'backgroundColor': '#EEE'})
							.prop('disabled', true);
					}
				});
				
				dialog.dialog('option', 'buttons',[
					{
						text: 'Send',
						click: function () {
							if ( $('#dossier-mail-to-recipient-list .dossier-mail-to-recipient').length > 0 ) {
								var addresses = new Array();
								$('#dossier-mail-to-recipient-list .dossier-mail-to-recipient').each( function (i) {
									addresses.push( $(this).text() );
								});
								
								$.main.ajaxRequest({
									modName: 'dossier',
									pageName: 'dossier_timeline',
									action: 'mailDossierItem',
									queryString: $('#form-dossier-mail-item').serializeWithSpaces() + '&itemid=' + dossierItemID + '&addresses=' + encodeURIComponent( JSON.stringify(addresses) ),
									success: function () {
										dialog.dialog('option', 'buttons', [
											{
												text: 'Close',
												click: function () { $(this).dialog('close') }
											}
										]);
										dialog.dialog('option', 'width', '600px');
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
			}
		});
		
		dialog.dialog('option', 'title', 'Mail dossier item');
		dialog.dialog('option', 'width', '1100px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
		
	});

	// display between dates
	var $start_date = $("#dossier-timeline-start-date");
	var $end_date   = $("#dossier-timeline-end-date");

	function subset_items() {
		var from = $start_date.datepicker('getDate');
		var to   = $end_date.datepicker('getDate');
		var from_ymd = from ? $.datepicker.formatDate('yymmdd', from) : '0';
		var to_ymd   = to   ? $.datepicker.formatDate('yymmdd', to) : '2100';
		console.log("subset items between " + from_ymd + " and " + to_ymd);

		var hidden_items = 0;
		$(".item-row-dossier").each( function () {
			var stamp = $(this).attr('data-date');
			if(stamp >= from_ymd && stamp <= to_ymd)
				 $(this).show();
			else {
				$(this).hide();
				hidden_items++;
			}
		});
		console.log("hidden="+hidden_items);
		$("span.dossier-items-hidden").text(hidden_items);
	}

	$start_date.datepicker("option", {
		maxDate: "+0d",
		onSelect: subset_items
	});

	$end_date.datepicker("option", {
		gotoCurrent: true,
		maxDate: "+0d",
		onSelect: subset_items
	});
});
