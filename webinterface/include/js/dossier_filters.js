/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// button 'Create a new note'
	$('#filters').on('click', '#btn-dossier-note-new', function () {
		var dossierID = $(this).attr('data-dossierid'),
			dialog = $('<div>').newDialog();
		
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_note',
			action: 'openDialogNewNote',
			success: function (params) {

				if ( params.writeRight == 1 ) { 
					var context = $('#form-dossier-new-note[data-id="NEW"]');
					
					dialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {

								var timeRe = /^((0|1)[0-9]|2[0-3]):[0-5][0-9]$/;
								
								if ( timeRe.test( $('#dossier-note-event-timestamp-time').val() ) == false ) {
									alert("Please specify a valid time.");
								} else if ( validateForm(['dossier-note-event-timestamp-date']) ) {
								
									var noteData = new FormData();
									$('.dossier-item-note-files').each( function (i) {
										if ( $(this)[0].files[0] ) {
											noteData.append('noteFiles', $(this)[0].files[0] );
										}
									});
									
									var paramsObj = $('#form-dossier-new-note').serializeHash();
									paramsObj.dossier_id = dossierID;

									noteData.append('params', JSON.stringify(paramsObj) );
		
									$.ajax({
										url: $.main.scriptroot + '/load/dossier/dossier_note/saveNewNote',
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
												action: 'displayDossierTimeline',
												queryString: 'id=' + dossierID,
												success: null
											});
											
											$.main.activeDialog.dialog('close');
										} else {
											alert( result.page.params.message )
										}
									}).fail(function () {
										alert('Great! You broke it!');
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
							$('#note-text').textrange('insert', '[[' + $('#dossier-note-constituent-group option:selected').text() + ']]' );
						}
					});

					// add constituent individual to note text
					$('#btn-dossier-note-insert-individual').click( function () {
						if ( $('#dossier-note-constituent-individual').val() != '' ) {
							$('#note-text').textrange('insert', '[[' + $('#dossier-note-constituent-individual option:selected').text() + ']]' );
						}
					});
					
					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Create new note');
		dialog.dialog('option', 'width', '670px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});
	
	// export dossier to text or PDF by download or email
	$('#filters').on('click', '#btn-dossier-export', function () {
		
		var dossierID = $(this).attr('data-dossierid'),
		dialog = $('<div>').newDialog();
	
		dialog.html('<fieldset>loading...</fieldset>');

		var start_date = $('#dossier-timeline-start-date').val()
		var end_date   = $('#dossier-timeline-end-date').val();

		var settings   = 'id=' + dossierID
		  + '&start_date=' + start_date
		  + '&end_date='  + end_date;

		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier',
			action: 'openDialogExportDossier',
			queryString: settings,
			success: function (params) {
				
				dialog.dialog('option', 'buttons', [
					{
						text: 'Download',
						click: function () {
							
							var detailsParams = new Object();
							detailsParams.id = dossierID;
							detailsParams.include_comments = $('input[name="include_comments"]:checked').val();
							detailsParams.export_format = $('input[name="export_format"]:checked').val();
							detailsParams.export_content = $('input[name="export_content"]:checked').val();
							detailsParams.export_to = $('input[name="export_to"]:checked').val();
							detailsParams.start_date = start_date;
							detailsParams.end_date   = end_date;

							$('#downloadFrame').attr( 'src', 'loadfile/dossier/dossier/dossierExport?params=' + JSON.stringify(detailsParams) );
						}
					},
					{
						text: 'Send',
						click: function () {
							
							dialog.dialog('option', 'buttons', []);

							$.main.ajaxRequest({
								modName: 'dossier',
								pageName: 'dossier',
								action: 'dossierExport',
								queryString: $('#form-dossier-export').serializeWithSpaces() + '&' + settings,
								success: function () {
									dialog.dialog('option', 'buttons', [
										{
											text: 'Close',
											click: function () { $(this).dialog('close') }
										}
									]);
								}
							});
							dialog.html('<fieldset>Sending email. Please wait...</fieldset>');
						}
					},
					{
						text: 'Cancel',
						click: function () { $(this).dialog('close') }
					}
				]);
				
				$(":button:contains('Send')").hide();
				
				$('input[name="export_to"]').change( function () {
					if ( $('input[name="export_to"]:checked').val() == 'email' ) {
						$('#dossier-export-to-mail')
							.removeClass('disabled')
							.prop('disabled', false);
						$(":button:contains('Send')").show();
						$(":button:contains('Download')").hide();
					} else {
						$('#dossier-export-to-mail')
							.addClass('disabled')
							.prop('disabled', true);
						$(":button:contains('Send')").hide();
						$(":button:contains('Download')").show();
					}
				});
				
				var re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
				$('#btn-dossier-mail-add-address').click( function () {
					var emailAddress = $('#dossier-mail-extra-address').val(); 
					if ( emailAddress != '' && re.test( emailAddress ) ) {
						$('<option>')
							.val( emailAddress )
							.text( emailAddress )
							.appendTo('#dossier-mail-to')
							.prop('selected', true);
						$('#dossier-mail-extra-address').val('')
					} else {
						alert ("Please enter a valid e-mail address!");	
					}
				});
			}
		});
		
		dialog.dialog('option', 'title', 'Export dossier');
		dialog.dialog('option', 'width', '740px');
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
