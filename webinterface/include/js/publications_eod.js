/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogNewEodCallback ( params ) {
	var context =  $('#eod-details-form[data-publicationid="NEW"]');

	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Save',
			click: function () {
					
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eod',
					action: 'saveNewEod',
					queryString: $(context).find('.include-in-form').serializeWithSpaces(),
					success: saveNewEodCallback
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
	$('#eod-details-tabs', context).newTabs({selected: 0});
	
	setEodUIBehavior( context );
}

function openDialogEodDetailsCallback ( params ) {
	var context =  $('#eod-details-form[data-publicationid="' + params.publicationid + '"]');

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
					$('#eod-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eod-details-preview-text', context) );
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
		
		$('#eod-details-preview-text', context).prop('disabled', false);
		
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
					$('#eod-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eod-details-preview-text', context) );
				}
			},
			{
				text: 'Ready for review',
				click: function () {
						
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eod',
						action: 'saveEodDetails',
						queryString: $(context).find('.include-in-form').serializeWithSpaces() + '&skipUserAction=1',
						success: null
					});

					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eod',
						action: 'setEodStatus',
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
						pageName: 'eod',
						action: 'saveEodDetails',
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
	
	$('#eod-details-tabs', context).newTabs({selected: 0});

	// show/hide 'Print preview' button depending on which tab is active
	// and update the preview text
	$('a[href^="#eod-details-tabs-"]', context).click( function () {
		if ( $(this).attr('href') == '#eod-details-tabs-preview' ) {
			$(":button:contains('Print preview')").show();

			var obj_eod = new Object();
			
			obj_eod.handler = $('#eod-details-handler', context).val();
			obj_eod.first_co_handler = $('#eod-details-first-co-handler', context).val();
			obj_eod.second_co_handler = $('#eod-details-second-co-handler', context).val();
			obj_eod.general_info = $('#eod-details-general-info-text', context).val();
			obj_eod.vulnerabilities_threats = $('#eod-details-vulnerabilities-and-threats-text', context).val();
			obj_eod.publised_advisories = $('#eod-details-published-advisories-text', context).val();
			obj_eod.linked_items = $('#eod-details-linked-items-text', context).val();
			obj_eod.incident_info = $('#eod-details-incident-info-text', context).val();
			obj_eod.community_news = $('#eod-details-community-news-text', context).val();
			obj_eod.media_exposure = $('#eod-details-media-exposure-text', context).val();
			obj_eod.tlp_amber = $('#eod-details-tlp-amber-text', context).val();

			var timeframe_begin_date = $('#eod-details-timeframe-start-date', context).val().replace(/^(\d+)-(\d+)-(\d\d\d\d)$/ , "$2-$1-$3");
			obj_eod.timeframe_begin = timeframe_begin_date + ' ' + $('#eod-details-timeframe-begin-time', context).val();

			var timeframe_end_date = $('#eod-details-timeframe-end-date', context).val().replace(/^(\d+)-(\d+)-(\d\d\d\d)$/ , "$2-$1-$3");
			obj_eod.timeframe_end = timeframe_end_date + ' ' + $('#eod-details-timeframe-end-time', context).val();
			

			var queryString = 'publicationJson=' + encodeURIComponent(JSON.stringify(obj_eod)) 
				+ '&publication=eod'
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

	// change close event for this dialog, so it will include clearing the opened_by of the end-of-day
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
				success: reloadEodHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});

	// trigger click on first tab to display the correct buttons 
	$('a[href="#eod-details-tabs-general"]', context).trigger('click');
	
	setEodUIBehavior( context );
}

function openDialogPreviewEodCallback ( params ) {
	var context = $('#form-eod-preview[data-publicationid="' + params.publicationid + '"]');

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
			case 2:
				buttonSettingsArray.push( { text: "Set to Pending", status: 0 } );
				break;
		};

		$.each( buttonSettingsArray, function (i, buttonSettings) {

			var button = {
				text: buttonSettings.text,
				click: function () { 
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eod',
						action: 'setEodStatus',
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
				$('#eod-preview-text', context).attr( 'data-printbefore', printBefore );
				printInput( $('#eod-preview-text', context) );
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
				success: reloadEodHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});
}


//TODO: make 1 saveNewCallback in common_actions
function saveNewEodCallback ( params ) {
	if ( params.saveOk == 1 ) {

		$.main.activeDialog.dialog('close');
		
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'publications',
			action: 'getPublicationItemHtml',
			queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=eod',
			success: getPublicationItemHtmlCallback
		});
		
	} else {
		alert( params.message );
	}
}

function _put_text(pubId, eodField, eodEncodedText) {
	var $context = $('#eod-details-form[data-publicationid="' + pubId + '"]');
	var $field   = $('#eod-details-' + eodField + '-text', $context);

	/* the data is encoded HTML, make it real */
	$field.html(eodEncodedText);
	$field.val($field.text());
}

function getVulnerabilityNewsCallback ( params ) {
	if(params.message) {
		alert(params.message);
		return;
	}
	var eodText = params.vulnerabilityNews;
	if(eodText == '') {
		alert('No vulnerability news found for selected timeframe.');
		return;
	}
	_put_text(params.publicationId, 'vulnerabilities-and-threats', eodText);
}

function getPublishedAdvisoriesCallback ( params ) {
	if(params.message) {
		alert(params.message);
		return;
	}
	var eodText = params.sentPublications;
	if(eodText == '') {
		alert('No published advisories found for selected timeframe.');
		return;
	}
	_put_text(params.publicationId, 'published-advisories', eodText);
}

function getLinkedItemsCallback ( params ) {
	if(params.message) {
		alert(params.message);
		return;
	}
	var eodText = params.linkedItems;
	if(eodText == '') {
		alert('No linked items found for selected timeframe.');
		return;
	}
	_put_text(params.publicationId, 'linked-items', eodText);
}

function getMediaExposureItemsCallback ( params ) {
	if(params.message) {
		alert(params.message);
		return;
	}
	var eodText = params.mediaExposureItems;
	if(eodText == '') {
		alert('No media exposure items found for selected timeframe.');
		return;
	}
	_put_text(params.publicationId, 'media-exposure', eodText);
}

function getCommunityNewsItemsCallback ( params ) {
	if(params.message) {
		alert(params.message);
		return;
	}
	var eodText = params.communityNewsItems;
	if(eodText == '') {
		alert('No community news items found for selected timeframe.');
		return;
	}
	_put_text(params.publicationId, 'community-news', eodText);
}

function _need_time_range(group, context) {
		/* Hum... 'start' and 'begin' :-(    */
	var start_date = $('#eod-details-'+group+'-start-date', context).val(),
		end_date   = $('#eod-details-'+group+'-end-date',   context).val(),
		begin_time = $('#eod-details-'+group+'-begin-time', context).val(),
		end_time   = $('#eod-details-'+group+'-end-time',   context).val();

	if(start_date=='' || end_date=='' || begin_time=='' || end_time=='') {
		alert('Please select a time frame');
		return '';
	}

	return 'begin_date='  + start_date
	     + '&end_date='   + end_date
	     + '&begin_time=' + begin_time
	     + '&end_time='   + end_time;
}

function setEodUIBehavior (context) {

	// add timepicker to time input elements
	$('.time', context).each( function() {
		$(this).timepicker({ 'scrollDefaultNow': true, 'timeFormat': 'H:i' });
	});

	// change value of begin-time input elements when begin of timeframe changes
	$('#eod-details-timeframe-begin-time', context).change( function () {
		$('input[id$="-begin-time"]', context).each( function() {
			if ( $(this).attr('id') != 'eod-details-timeframe-begin-time' ) {
				$(this).val( $('#eod-details-timeframe-begin-time', context).val() );
			}
		});
	});

	// change value of end-time input elements when end of timeframe changes
	$('#eod-details-timeframe-end-time', context).change( function () {
		$('input[id$="-end-time"]', context).each( function() {
			if ( $(this).attr('id') != 'eod-details-timeframe-end-time' ) {
				$(this).val( $('#eod-details-timeframe-end-time', context).val() );
			}
		});
	});

	// change value of start-date input elements when start-date of timeframe changes
	$('#eod-details-timeframe-start-date', context).change( function () {
		$('input[id$="-start-date"]', context).each( function() {
			if ( $(this).attr('id') != 'eod-details-timeframe-start-date' ) {
				$(this).val( $('#eod-details-timeframe-start-date', context).val() );
			}
		});
	});

	// change value of end-date input elements when end-date of timeframe changes
	$('#eod-details-timeframe-end-date', context).change( function () {
		$('input[id$="-end-date"]', context).each( function() {
			if ( $(this).attr('id') != 'eod-details-timeframe-end-date' ) {
				$(this).val( $('#eod-details-timeframe-end-date', context).val() );
			}
		});
	});

	// set all date and time fields to their initial value
	$('#eod-details-timeframe-start-date', context).trigger('change');
	$('#eod-details-timeframe-end-date',   context).trigger('change');
	$('#eod-details-timeframe-begin-time', context).trigger('change');
	$('#eod-details-timeframe-end-time',   context).trigger('change');

	// vulnerability news items
	$('#btn-eod-details-apply-vulnerabilities-and-threats', context).click( function () {
		var time_range = _need_time_range('vulnerabilities-and-threats', context);
		if(time_range == '') return;

		var queryString = 'publicationTypeId='
			+ $('#eod-details-publication-type-id', context).val()
			+ '&publicationid=' + $(context).attr('data-publicationid')
			+ '&' + time_range;

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eod',
			action: 'getVulnerabilityNews',
			queryString: queryString,
			success: getVulnerabilityNewsCallback
		});
	});

	// media exposure items (added for this publication on Assess page) 
	$('#btn-eod-details-apply-media-exposure', context).click( function () {
		var time_range = _need_time_range('media-exposure', context);
		if(time_range == '') return;

		var queryString = 'publicationTypeId='
			+ $('#eod-details-publication-type-id', context).val()
			+ '&publicationid=' + $(context).attr('data-publicationid')
			+ '&' + time_range;

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eod',
			action: 'getMediaExposureItems',
			queryString: queryString,
			success: getMediaExposureItemsCallback
		});
	});

	// community news items (added for this publication on Assess page) 
	$('#btn-eod-details-apply-community-news', context).click( function () {
		var time_range = _need_time_range('community-news', context);
		if(time_range == '') return;

		var queryString = 'publicationTypeId=' + $('#eod-details-publication-type-id', context).val()
			+ '&publicationid=' + $(context).attr('data-publicationid')
			+ '&' + time_range;

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eod',
			action: 'getCommunityNewsItems',
			queryString: queryString,
			success: getCommunityNewsItemsCallback
		});
	});

    // get published advisories
	$('#btn-eod-details-apply-published-advisories', context).click( function ()
{
		var time_range = _need_time_range('published-advisories', context);
		if(time_range == '') return;

		var queryString = 'publicationTypeId=' + $('#eod-details-publication-type-id', context).val()
			+ '&publicationid=' + $(context).attr('data-publicationid')
			+ '&' + time_range;

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eod',
			action: 'getPublishedAdvisories',
			queryString: queryString,
			success: getPublishedAdvisoriesCallback
		});
	});

	// linked items
	$('#btn-eod-details-apply-linked-items', context).click( function () {
		var time_range = _need_time_range('linked-items', context);
		if(time_range == '') return;

		var queryString = 'publicationTypeId=' + $('#eod-details-publication-type-id', context).val()
			+ '&publicationid=' + $(context).attr('data-publicationid')
			+ '&' + time_range;

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eod',
			action: 'getLinkedItems',
			queryString: queryString,
			success: getLinkedItemsCallback
		});
	});
}

function reloadEodHtml ( params ) {
	$.main.ajaxRequest({
		modName: 'write',
		pageName: 'publications',
		action: 'getPublicationItemHtml',
		queryString: 'insertNew=0&id=' + params.id + '&pubType=eod',
		success: getPublicationItemHtmlCallback
	});
}
