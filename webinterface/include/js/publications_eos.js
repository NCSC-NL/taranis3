/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogNewEosCallback ( params ) {
	var context =  $('#eos-details-form[data-publicationid="NEW"]');
	
	$.main.activeDialog.dialog('option', 'width', '1150px');
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Save',
			click: function () {
					
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eos',
					action: 'saveNewEos',
					queryString: $(context).find('.include-in-form').serializeWithSpaces(),
					success: saveNewEosCallback
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
	$('#eos-details-tabs', context).newTabs({selected: 0});
	
	setEosUIBehavior( context );
}

function openDialogEosDetailsCallback ( params ) {
	var context =  $('#eos-details-form[data-publicationid="' + params.publicationid + '"]');
	
	$.main.activeDialog.dialog('option', 'width', '1150px');
	
	if ( params.isLocked == 1 ) {
		// setup dialog buttons
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Print preview',
				click: function () {
					var printBefore = '';
					$('[data-printable]', context).each( function () {
						printBefore += $(this).attr('data-printable') + "\n";
					});
					$('#eos-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eos-details-preview-text', context) );
				}
			},
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		// disable all fields
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
		
		$('#eos-details-preview-text', context).prop('disabled', false);
		
	} else {
	
		// setup dialog buttons
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Print preview',
				click: function () {
					var printBefore = '';
					$('[data-printable]', context).each( function () {
						printBefore += $(this).attr('data-printable') + "\n";
					});
					$('#eos-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eos-details-preview-text', context) );
				}
			},
			{
				text: 'Ready for review',
				click: function () {
						
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eos',
						action: 'saveEosDetails',
						queryString: $(context).find('.include-in-form').serializeWithSpaces() + '&skipUserAction=1',
						success: null
					});

					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eos',
						action: 'setEosStatus',
						queryString: 'publicationId=' + params.publicationid + '&status=1',
						success: setPublicationCallback
					});
				}
			},
			{
				text: 'Save',
				click: function () {
						
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eos',
						action: 'saveEosDetails',
						queryString: $(context).find('.include-in-form').serializeWithSpaces(),
						success: setPublicationCallback
					});
				}
			},
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
	}
	
	$('#eos-details-tabs', context).newTabs({selected: 0});

	// show/hide 'Print preview' button depending on which tab is active
	// and update the preview text
	$('a[href^="#eos-details-tabs-"]', context).click( function () {
		if ( $(this).attr('href') == '#eos-details-tabs-preview' ) {
			$(":button:contains('Print preview')").show();

			var obj_eos = new Object();
			obj_eos.handler = $('#eos-details-handler', context).val();

			var timeframe_begin_date = $('#eos-details-timeframe-start-date', context).val().replace(/^(\d+)-(\d+)-(\d\d\d\d)$/ , "$2-$1-$3");
			obj_eos.timeframe_begin = timeframe_begin_date + ' ' + $('#eos-details-timeframe-begin-time', context).val();

			var timeframe_end_date = $('#eos-details-timeframe-end-date', context).val().replace(/^(\d+)-(\d+)-(\d\d\d\d)$/ , "$2-$1-$3");
			obj_eos.timeframe_end = timeframe_end_date + ' ' + $('#eos-details-timeframe-end-time', context).val();
			
			obj_eos.notes = $('#eos-details-notes', context).val();
			obj_eos.contact_log = $('#eos-details-contact-log', context).val();
			obj_eos.incident_log = $('#eos-details-incident-log', context).val();
			obj_eos.special_interest = $('#eos-details-special-interest', context).val();
			obj_eos.todo = $('#eos-details-todo', context).val();
			obj_eos.done = $('#eos-details-done', context).val();
			
			var queryString = 'publicationJson=' + encodeURIComponent(JSON.stringify(obj_eos)) 
				+ '&publication=eos'
				+ '&publicationid=' + params.publicationid
				+ '&publication_type=email'
				+ '&line_width=0';
			
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'common_actions',
				action: 'getPulicationPreview',
				queryString: queryString,
				success: getPulicationPreviewCallback
			});
			
		} else {
			$(":button:contains('Print preview')").hide();
		}
	});

	// change close event for this dialog, so it will include clearing the opened_by of the end-of-shift
	$.main.activeDialog.bind( "dialogclose", function(event, ui) { 

		if ( 
			$.main.lastRequest.action != 'getPublicationItemHtml' 
			|| ( $.main.lastRequest.action == 'getPublicationItemHtml' && $.main.lastRequest.queryString.indexOf( 'id=' + params.publicationid ) == -1 ) 
		) {
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'closePublication',
				queryString: 'id=' + params.publicationid,
				success: reloadEosHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});

	// trigger click on first tab to display the correct buttons 
	$('a[href="#eos-details-tabs-general"]', context).trigger('click');
	
	setEosUIBehavior( context );
}

function openDialogPreviewEosCallback ( params ) {
	var context = $('#form-eos-preview[data-publicationid="' + params.publicationid + '"]');

	var buttonsArray = new Array(),
		buttonSettingsArray = new Array(),
		status = 0;
	
	if ( params.isLocked == 0 ) {
		// available button settings:
		// [ { text: "Set to Pending", status: 0 }, { text: "Ready for review", status: 1 } , { text: "Approve", status: 2 } ]
		switch (params.currentStatus) {
			case 0:
				buttonSettingsArray.push( { text: "Ready for review", status: 1 } );
				break;
			case 1:
				buttonSettingsArray.push( { text: "Set to Pending", status: 0 } );
				if ( params.executeRight == 1 ) {
					buttonSettingsArray.push( { text: "Approve", status: 2 }  );
				}
				break;
		};

		$.each( buttonSettingsArray, function (i, buttonSettings) {

			var button = {
				text: buttonSettings.text,
				click: function () { 
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eos',
						action: 'setEosStatus',
						queryString: 'publicationId=' + params.publicationid + '&status=' + buttonSettings.status,
						success: setPublicationCallback
					});				
				}
			}
			buttonsArray.push( button );
		});
	}
		
	buttonsArray.push(
		{
			text: 'Print preview',
			click: function () {
				var printBefore = '';
				$('[data-printable]', context).each( function () {
					printBefore += $(this).attr('data-printable') + "\n";
				});
				$('#eos-preview-text', context).attr( 'data-printbefore', printBefore );
				printInput( $('#eos-preview-text', context) );
			}
		}
	);

	buttonsArray.push(
			{
			text: 'Close',
			click: function () { $.main.activeDialog.dialog('close') }
		}
	);
	
	// add buttons to dialog
	$.main.activeDialog.dialog('option', 'buttons', buttonsArray);
	$(":button:contains('Print preview')").css('margin-left', '20px');

	// change close event for this dialog, so it will include clearing the opened_by of the advisory
	$.main.activeDialog.bind( "dialogclose", function(event, ui) { 

		if ( 
			$.main.lastRequest.action != 'getPublicationItemHtml' 
			|| ( $.main.lastRequest.action == 'getPublicationItemHtml' && $.main.lastRequest.queryString.indexOf( 'id=' + params.publicationid ) == -1 ) 
		) {
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'closePublication',
				queryString: 'id=' + params.publicationid,
				success: reloadEosHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});
}

//TODO: maak 1 saveNewCallback in common_actions
function saveNewEosCallback ( params ) {
	if ( params.saveOk == 1 ) {

		$.main.activeDialog.dialog('close');
		
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'publications',
			action: 'getPublicationItemHtml',
			queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=eos',
			success: getPublicationItemHtmlCallback
		});
		
	} else {
		alert( params.message );
	}
}

function setEosUIBehavior (context ) {
	// add timepicker to time input elements
	$('.time', context).each( function() {
		$(this).timepicker({ 'scrollDefaultNow': true, 'timeFormat': 'H:i' });
	});
}

function reloadEosHtml ( params ) {
	$.main.ajaxRequest({
		modName: 'write',
		pageName: 'publications',
		action: 'getPublicationItemHtml',
		queryString: 'insertNew=0&id=' + params.id + '&pubType=eos',
		success: getPublicationItemHtmlCallback
	});
}
