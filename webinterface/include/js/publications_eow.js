/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogNewEowCallback ( params ) {
	var context = $('#eow-details-form[data-publicationid="NEW"]');
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Save',
			click: function () {
					
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eow',
					action: 'saveNewEow',
					queryString: $(context).find('.include-in-form').serializeWithSpaces(),
					success: saveNewEowCallback
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
	$('#eow-details-tabs', context).newTabs({selected: 0});
	
	setEowUIBehavior( context );
}

function openDialogEowDetailsCallback ( params ) {
	var context =  $('#eow-details-form[data-publicationid="' + params.publicationid + '"]');
	
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
					$('#eow-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eow-details-preview-text', context) );
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
		
		$('#eow-details-preview-text', context).prop('disabled', false);
		
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
					$('#eow-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#eow-details-preview-text', context) );
				}
			},
			{
				text: 'Ready for review',
				click: function () {
						
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eow',
						action: 'saveEowDetails',
						queryString: $(context).find('.include-in-form').serializeWithSpaces() + '&skipUserAction=1',
						success: null
					});

					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eow',
						action: 'setEowStatus',
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
						pageName: 'eow',
						action: 'saveEowDetails',
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
	
	$('#eow-details-tabs', context).newTabs({selected: 0});

	// show/hide 'Print preview' button depending on which tab is active
	// and update the preview text
	$('a[href^="#eow-details-tabs-"]', context).click( function () {
		if ( $(this).attr('href') == '#eow-details-tabs-preview' ) {
			$(":button:contains('Print preview')").show();

			var obj_eow = new Object();

			obj_eow.introduction = $('#eow-details-introduction-text', context).val();
			obj_eow.sent_advisories = $('#eow-details-sent-advisories-text', context).val();
			obj_eow.newondatabank = $('#eow-details-new-kb-items-text', context).val();
			obj_eow.newsitem = $('#eow-details-other-news-text', context).val();
			obj_eow.closing = $('#eow-details-closing-text', context).val();

			var queryString = 'publicationJson=' + encodeURIComponent( JSON.stringify(obj_eow) ) 
				+ '&publication=eow'
				+ '&publicationid=' + params.publicationid
				+ '&publication_type=email';
			
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

	// change close event for this dialog, so it will include clearing the opened_by of the end-of-week
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
				success: reloadEowHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});

	// trigger click on first tab to display the correct buttons 
	$('a[href="#eow-details-tabs-introduction"]', context).trigger('click');
	
	setEowUIBehavior( context );
}

function openDialogPreviewEowCallback ( params ) {
	var context = $('#form-eow-preview[data-publicationid="' + params.publicationid + '"]');

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
				if ( params.userIsAuthor == 0 && params.executeRight == 1 ) {
					buttonSettingsArray.push( { text: "Approve", status: 2 }  );
				}
				break;
		};
		
		$.each( buttonSettingsArray, function (i, buttonSettings ) {

			var button = {
				text: buttonSettings.text,
				click: function () { 
				
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'eow',
						action: 'setEowStatus',
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
				$('#eow-preview-text', context).attr( 'data-printbefore', printBefore );
				printInput( $('#eow-preview-text', context) );
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
				success: reloadEowHtml
			});			
		}
		
		if ( $('.dialogs:visible').length == 0 ) {
			$('#screen-overlay').hide();
		}
	});
}


//TODO: maak 1 saveNewCallback in common_actions
function saveNewEowCallback ( params ) {
	if ( params.saveOk == 1 ) {
		
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'publications',
			action: 'getPublicationItemHtml',
			queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=eow',
			success: getPublicationItemHtmlCallback
		});

		$.main.activeDialog.dialog('close');
		
	} else {
		alert( params.message );
	}
}

function getSentAdvisoriesCallback ( params ) {
	var context =  $('#eow-details-form[data-publicationid="' + params.publicationId + '"]');
	$('#eow-details-sent-advisories-text', context).html( params.sentAdvisoryText );
	$('#eow-details-sent-advisories-text', context).val( $('#eow-details-sent-advisories-text', context).text() );
}

function getAnalysisForEowCallback ( params ) {
	var context = $('#eow-details-form[data-publicationid="' + params.publicationid + '"]');
	var details = params.analysis;
	
	$('#eow-details-analysis-title', context).html(details.title);
	$('#eow-details-analysis-title', context)
		.val( $('#eow-details-analysis-title', context).text() )
		.attr('title', $('#eow-details-analysis-title', context).text() );
	
	$('#eow-details-analysis-description', context).html(details.comments);
	$('#eow-details-analysis-description', context)
		.val( $('#eow-details-analysis-description', context).text() )
		.attr('title', $('#eow-details-analysis-description', context).text() );

	$('#eow-details-item-links', context).html('');
	for ( var i = 0; i < details.links.length; i++ ) {
		$('#eow-details-item-links', context).html( $('#eow-details-item-links', context).html() + "<input type='checkbox' name='links' id='" + details.links[i] + "' value='" + details.links[i] + "' checked='checked'> <label for='" + details.links[i] + "' title='" + details.links[i] + "'>" + details.links[i] + "</label><br>");
	}

}

function setEowUIBehavior (context ) {
	
	// set the content for 'Sent advisories' tab
	$('.btn-eow-details-apply-selection', context).click( function () {
		if ( validateForm(['eow-details-start-date', 'eow-details-end-date']) ) {
			var startDate = encodeURIComponent( $('#eow-details-start-date').val() );
			var endDate = encodeURIComponent( $('#eow-details-end-date').val() );

			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'eow',
				action: 'getSentAdvisories',
				queryString: 'publicationid=' + $(context).attr('data-publicationid') + '&startDate=' + startDate + '&endDate=' + endDate,
				success: getSentAdvisoriesCallback
			});
		}	
	});
	
	// select analysis on 'other news' tab
	$('#eow-details-analysis-selection', context).change( function () {
		var analysisId = $(this).val();
		
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'eow',
			action: 'getAnalysisForEow',
			queryString: 'publicationid=' + $(context).attr('data-publicationid') + '&analysisid=' + analysisId,
			success: getAnalysisForEowCallback
		});
	});
	
	// add analysis text to 'other news'
	$('#btn-eow-details-other-news-use-item', context).click( function () {
		
		var title = '* ' + $('#eow-details-analysis-title', context).val();
		var description = $('#eow-details-analysis-description', context).val();
		

		var linksText = '';
		$('input[type="checkbox"][name="links"]:checked').each( function (i) {
			linksText += $(this).val() + '\n';
		});

		
		var text = title + '\n' + description + '\n\n' + linksText + '\n';

		var txt_area = document.getElementById('eow-details-other-news-text')
		var strPos = txt_area.selectionStart;
		
		var oldScrollHeight = txt_area.scrollHeight;
		var scrollPos = txt_area.scrollTop;
		
		var previous_txt = (txt_area.value).substring(0,strPos); 
		var next_txt = (txt_area.value).substring(strPos, txt_area.value.length);
		txt_area.innerHTML = previous_txt + text + next_txt 
		txt_area.value = txt_area.textContent;
		
		strPos = strPos + text.length; 
		
		txt_area.selectionStart = strPos; 
		txt_area.selectionEnd = strPos; 
			 	
		txt_area.focus();
		scrollPos = ( txt_area.scrollHeight - oldScrollHeight ) + scrollPos;
		txt_area.scrollTop = scrollPos;
	});
	
}

function reloadEowHtml ( params ) {
	$.main.ajaxRequest({
		modName: 'write',
		pageName: 'publications',
		action: 'getPublicationItemHtml',
		queryString: 'insertNew=0&id=' + params.id + '&pubType=eow',
		success: getPublicationItemHtmlCallback
	});	
}
