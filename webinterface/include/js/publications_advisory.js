/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

var probabilityFields = new Array('pro_standard','pro_exploit', 'pro_details', 'pro_access', 'pro_credent', 'pro_complexity', 'pro_userint', 'pro_exploited', 'pro_expect', 'pro_solution');
var damageFields = new Array('dmg_dos', 'dmg_codeexec', 'dmg_remrights', 'dmg_privesc', 'dmg_infoleak');

function _valid_advisory_details_form(context) {
	if ( $('#advisory-details-title', context).val() == '' ) {
		alert('Please specify an advisory title.')
		return false;
	}

	if (!setProbability(1, context) && $('#advisory-details-pro-deviation', context).val() == '' ) {
		alert("Probability matrix does not match automatic scaling.\nPlease specify reason for deviation.");
		return false;
	}

	if (!setDamage(1, context) && $('#advisory-details-dmg-deviation', context).val() == '' ) {
		alert("Damage matrix does not match automatic scaling.\nPlease specify reason for deviation.");
		return false;
	}

	var is_cveids = /^CVE-[0-9]{4}-[0-9]{4,10}([, ]+CVE-[0-9]{4}-[0-9]{4,10})*\s*$/;
	var cveids    = $('#advisory-details-cveid', context).val();
	cveids.replace(/^\s+/, '');
	if (cveids != '' && ! is_cveids.test(cveids)) {
		alert("The CVE-ID list is incorrect.");
		return false;
	}

	return true;
}

function openDialogNewAdvisoryCallback ( params ) {
	var publicationId = ( 'is_update' in params ) ? params.publicationid : 'NEW';

	var context =  $('#advisory-details-form[data-publicationid="' + publicationId + '"]');

	// matrix probability setting
	$.each( probabilityFields, function(index, probabilityField) {
		$('input[name="' + probabilityField + '"]', context).change( function () {
			setProbability(0, context)
		});
	});

	// matrix damage setting
	$.each( damageFields, function(index, damageField) {
		$('input[name="' + damageField + '"]', context).change( function () {
			setDamage(0, context)
		});
	});

	$('#advisory-details-tabs', context).newTabs({selected: 0});

	// make sure the dialog resizes correctly in case the dialog was reused
	var dialogWidth = ( 'is_update' in params || 'is_import' in params ) ? '920px' : '860px';
	$.main.activeDialog.dialog('option', 'width', dialogWidth);

	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			id: 'button-save-advisory',
			text: 'Save',
			click: function () {
				if( _valid_advisory_details_form(context) ) {
					$('#advisory-platforms-left-column option', context).each( function (i) {
						$(this).prop('selected', true);
					});

					$('#advisory-products-left-column option', context).each( function (i) {
						$(this).prop('selected', true);
					});

					if ( publicationId == 'NEW' ) {
						$('#button-save-advisory').button('disable');

						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'advisory',
							action: 'saveNewAdvisory',
							queryString: $('#advisory-details-form[data-publicationid="NEW"]').find('.include-in-form').serializeWithSpaces(),
							success: saveNewAdvisoryCallback
						});
					} else {
						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'advisory',
							action: 'saveUpdateAdvisory',
							queryString: $('#advisory-details-form[data-publicationid="' + publicationId + '"]').find('.include-in-form').serializeWithSpaces(),
							success: saveUpdateAdvisoryCallback
						});
					}
				} 
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);

	function filterInUse(context, toggle, list) {
		var $unused = $(list + ' option', context).not('.option-sh-in-use');
		$(toggle, context).is(':checked') ? $unused.hide() : $unused.show();
	}

	// search platforms
	$('#btn-advisory-platforms-inuse-only', context).on('change', function (){
		filterInUse(context, '#btn-advisory-platforms-inuse-only', '#advisory-platforms-right-column');
	});

	$('#btn-advisory-platforms-search', context).click( function () {
		searchSoftwareHardwareWrite( context, 'platforms', publicationId, 'advisory' );	
	});

	// search products
	$('#btn-advisory-products-inuse-only', context).on('change', function (){
		filterInUse(context, '#btn-advisory-products-inuse-only', '#advisory-products-right-column');
	});

	$('#btn-advisory-products-search', context).click( function () {
		searchSoftwareHardwareWrite( context, 'products', publicationId, 'advisory' );
	});

	// do platforms search on ENTER
	$('#advisory-platforms-search', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-advisory-platforms-search', context).trigger('click');
		}
	});

	// do products search on ENTER
	$('#advisory-products-search', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-advisory-products-search', context).trigger('click');
		}
	});

	setAdvisoryUIBehavior(context);
}

function openDialogUpdateAdvisoryCallback ( params ) {
	params['is_update'] = true;
	openDialogNewAdvisoryCallback( params );
}

function openDialogImportAdvisoryCallback (params ) {
	params['is_import'] = true;
	openDialogNewAdvisoryCallback( params );
}

function openDialogPreviewAdvisoryCallback ( params ) {

	var context = $('#advisory-preview-tabs[data-publicationid="' + params.publicationid + '"]');

	$('#advisory-details-tabs-matrix *', context).prop('disabled', true);

	var buttons = new Array(),
		buttonSettings = new Array(),
		status = 0;

	if ( params.isLocked == 0 && params.noStatusChangeButtons == 0 ) {
		switch (params.currentStatus) {
			case 0:
				buttonSettings.push( { text: "Ready for review", status: 1 } );
				break;
			case 1:
				buttonSettings.push( { text: "Set to Pending", status: 0 } );
				if ( params.userIsAuthor == 0 && params.executeRight == 1 ) {
					buttonSettings.push( { text: "Approve", status: 2 }  );
				}
				break;
			case 2:
				buttonSettings.push( { text: "Set to Pending", status: 0 } );
				break;
		};


		$.each( buttonSettings, function (i, buttonSetting ) {

			var button = {
				text: buttonSetting.text,
				click: function () { 
					$.main.ajaxRequest({
						modName: 'write',
						pageName: 'advisory',
						action: 'setAdvisoryStatus',
						queryString: 'publicationId=' + params.publicationid + '&status=' + buttonSetting.status,
						success: setPublicationCallback
					});				
				}
			}
			buttons.push( button );
		});
	}

	buttons.push(
		{
			text: 'Print preview',
			click: function () { printAdvisoryPreview(context) }
		}
	);

	if ( params.writeRight == 1 ) {
		buttons.push(
				{
					text: 'Save notes',
					click: function () { 
						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'common_actions',
							action: 'savePublicationNotes',
							queryString: 'publicationType=advisory&publicationId=' + params.publicationid + '&notes=' + $('#advisory-preview-notes', context).val() ,
							success: saveAdvisoryNotesCallback
						});
					}
				}
		);	
	}

	buttons.push(
			{
			text: 'Close',
			click: function () { $.main.activeDialog.dialog('close') }
		}
	);

	// add buttons to dialog
	$.main.activeDialog.dialog('option', 'buttons', buttons);
	$(":button:contains('Print preview')").css('margin-left', '20px');

	$.main.activeDialog.dialog('option', 'width', '890px');

	// init tabs
	context.newTabs({selected: 0});
	if ( params.writeRight == 1 ) {
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
					success: reloadAdvisoryHtml
				});			
			}

			if ( $('.dialogs:visible').length == 0 ) {
				$('#screen-overlay').hide();
			}
		});
	}

	// change preview text: email <=> xml
	$('input[name="preview_type"]', context).change( function () {
		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'advisory',
			action: 'getAdvisoryPreview',
			queryString: 'publicationId=' + params.publicationid + '&advisoryId=' + $('#advisory-preview-advisory-id').val() + '&publicationType=' + $(this).val(),
			success: getAdvisoryPreviewCallback
		});
		if ( $(this).val() == 'xml' ) {
			$(":button:contains('Print preview')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');
		} else {
			$(":button:contains('Print preview')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}
	});

	// show/hide print preview button
	$('a[href^="#advisory-preview-tabs-"], a[href^="#advisory-details-tabs-matrix"]', context).click( function () {
		if ( $(this).attr('href') == '#advisory-preview-tabs-general' ) {
			$(":button:contains('Print preview')").show();
		} else {
			$(":button:contains('Print preview')").hide();
		}
	});

	// show/hide 'Save notes' button
	$('a[href^="#advisory-preview-tabs-"], a[href^="#advisory-details-tabs-matrix"]', context).click( function () {
		if ( $(this).attr('href') == '#advisory-preview-tabs-notes' && params.writeRight ) {
			$(":button:contains('Save notes')").show();
		} else {
			$(":button:contains('Save notes')").hide();
		}
	});	

	$('a[href^="#advisory-preview-tabs-general"]', context).trigger('click');

	// sort the platforms and products on tab software/hardware
	sortOptions( $('#advisory-preview-platforms', context).get()[0] );
	sortOptions( $('#advisory-preview-products', context).get()[0] );
}

function openDialogAdvisoryDetailsCallback ( params ) {
	var context =  $('#advisory-details-form[data-publicationid="' + params.publicationid + '"]');

	if ( params.isLocked == 1 ) {
		// setup dialog buttons
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Print preview',
				click: function () { printAdvisoryPreview(context) }
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

		$('#advisory-details-preview-text', context).prop('disabled', false);
		$('input[name="preview_type"]', context).prop('disabled', false);

	} else {
		// setup dialog buttons
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Print preview',
				click: function () { printAdvisoryPreview(context) }
			},
			{
				text: 'Ready for review',
				click: function () { 
					if(_valid_advisory_details_form(context)) {
						$('#advisory-platforms-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});

						$('#advisory-products-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});

						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'advisory',
							action: 'saveAdvisoryDetails',
							queryString: $('#advisory-details-form[data-publicationid="' + params.publicationid + '"]').find('.include-in-form').serializeWithSpaces() + '&skipUserAction=1',
							success: null
						});

						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'advisory',
							action: 'setReadyForReview',
							queryString: 'publicationId=' + params.publicationid + '&advisoryId=' + $('#advisory-details-advisory-id', context).val(),
							success: setPublicationCallback
						});				
					}				
				}
			},
			{
				text: 'Save',
				click: function () {
					if(_valid_advisory_details_form(context)) {
						$('#advisory-platforms-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});

						$('#advisory-products-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});

						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'advisory',
							action: 'saveAdvisoryDetails',
							queryString: $('#advisory-details-form[data-publicationid="' + params.publicationid + '"]').find('.include-in-form').serializeWithSpaces(),
							success: setPublicationCallback
						});
					} 
				}
			},
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);

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
					success: reloadAdvisoryHtml
				});			
			}

			if ( $('.dialogs:visible').length == 0 ) {
				$('#screen-overlay').hide();
			}
		});

		// matrix probability setting
		$.each( probabilityFields, function(index, probabilityField) {
			$('input[name="' + probabilityField + '"]', context).change( function () {
				setProbability(0, context);
				setReadyForReviewButton(context);
			});
		});

		// matrix damage setting
		$.each( damageFields, function(index, damageField) {
			$('input[name="' + damageField + '"]', context).change( function () {
				setDamage(0, context);
				setReadyForReviewButton(context);
			});
		});

		$('#advisory-details-probability, #advisory-details-damage', context).change( function () {
			setReadyForReviewButton(context);
		});

	/* XXX This is the logical spot for this code.  However, it does not
	   work in production.  Possibly a load timing issue.  Therefore
	   moved to main.js until understood.
		$('.btn-sort', context).click( function () {
			var ta_name = $(this).data('textarea');
			var $t      = $(ta_name, context);
			$t.val($t.val().trim().split("\n").sort().join("\n"));
		});
     */

		// search platforms
		$('#btn-advisory-platforms-search', context).click( function () {
			searchSoftwareHardwareWrite( context, 'platforms', params.publicationid, 'advisory' );	
		});

		// search products
		$('#btn-advisory-products-search', context).click( function () {
			searchSoftwareHardwareWrite( context, 'products', params.publicationid, 'advisory' );
		});

		// do platforms search on ENTER
		$('#advisory-platforms-search', context).keypress( function (event) {
			if ( !checkEnter(event) ) {
				$('#btn-advisory-platforms-search', context).trigger('click');
			}
		});

		// do products search on ENTER
		$('#advisory-products-search', context).keypress( function (event) {
			if ( !checkEnter(event) ) {
				$('#btn-advisory-products-search', context).trigger('click');
			}
		});

		setReadyForReviewButton( context );
		setAdvisoryUIBehavior(context);

	}

	$('#advisory-details-tabs', context).newTabs({selected: 0});

	// show/hide 'Print preview' button depending on which tab is active
	// and update the preview text
	$('a[href^="#advisory-details-tabs-"]', context).click( function () {
		if ( $(this).attr('href') == '#advisory-details-tabs-preview' ) {
			$('input[name="preview_type"]', context).triggerHandler('change');
			$(":button:contains('Print preview')").show();
		} else {
			$(":button:contains('Print preview')").hide();
		}
	});

	// change the preview text
	$('input[name="preview_type"]', context).change( function () {

		if ( $('input[name="preview_type"]:checked', context).val() == 'xml' ) {
			var obj_advisory_xml = new Object();

			var govcertid_version 		= $('#advisory-details-id', context).text();
			obj_advisory_xml.govcertid	= govcertid_version.replace( /^(.*?) \[.*/ , "$1" );
			obj_advisory_xml.version	= govcertid_version.replace( /.*?\[v(.*?)\]/ , "$1" );
			obj_advisory_xml.title    	= $('#advisory-details-title', context).val();
			obj_advisory_xml.created_by	= $('#advisory-details-author', context).html();
			obj_advisory_xml.damage 	= $('#advisory-details-damage option:selected', context).val();
			obj_advisory_xml.probability = $('#advisory-details-probability option:selected', context).val();

			obj_advisory_xml.hyperlinks = '';
			$('input[name="advisory_links"]:checked', context).each( function () {
				obj_advisory_xml.hyperlinks += $(this).val() + '\n';
			});

			obj_advisory_xml.hyperlinks += $('.advisory-details-additional-links', context).val();

			obj_advisory_xml.ids = $('#advisory-details-cveid', context).val();

			obj_advisory_xml.platforms = new Array();
			$('#advisory-platforms-left-column > option', context).each( function () {
				obj_advisory_xml.platforms.push( $(this).val() );
			});

			obj_advisory_xml.platforms_text = $('#advisory-platforms-txt', context).val();

			obj_advisory_xml.products = new Array();
			$('#advisory-products-left-column > option', context).each( function () {
				obj_advisory_xml.products.push( $(this).val() );
			});

			obj_advisory_xml.products_text = $('#advisory-products-txt', context).val();
			obj_advisory_xml.versions_text = $('#advisory-versions-txt', context).val();

			obj_advisory_xml.publication_id = params.publicationid

			obj_advisory_xml.ques_dmg_codeexec 		= $('input[name="dmg_codeexec"]:checked', context).val();
			obj_advisory_xml.ques_dmg_deviation 	= $('input[name="dmg_deviation"]', context).val();
			obj_advisory_xml.ques_dmg_dos 			= $('input[name="dmg_dos"]:checked', context).val();
			obj_advisory_xml.ques_dmg_infoleak 		= $('input[name="dmg_infoleak"]:checked', context).val();
			obj_advisory_xml.ques_dmg_privesc 		= $('input[name="dmg_privesc"]:checked', context).val();
			obj_advisory_xml.ques_dmg_remrights 	= $('input[name="dmg_remrights"]:checked', context).val();
			obj_advisory_xml.ques_pro_access 		= $('input[name="pro_access"]:checked', context).val();
			obj_advisory_xml.ques_pro_complexity 	= $('input[name="pro_complexity"]:checked', context).val();
			obj_advisory_xml.ques_pro_credent 		= $('input[name="pro_credent"]:checked', context).val();
			obj_advisory_xml.ques_pro_details 		= $('input[name="pro_details"]:checked', context).val();
			obj_advisory_xml.ques_pro_deviation 	= $('input[name="pro_deviation"]', context).val();
			obj_advisory_xml.ques_pro_expect 		= $('input[name="pro_expect"]:checked', context).val();
			obj_advisory_xml.ques_pro_exploit 		= $('input[name="pro_exploit"]:checked', context).val();
			obj_advisory_xml.ques_pro_exploited 	= $('input[name="pro_exploited"]:checked', context).val();
			obj_advisory_xml.ques_pro_solution 		= $('input[name="pro_solution"]:checked', context).val();
			obj_advisory_xml.ques_pro_standard 		= $('input[name="pro_standard"]:checked', context).val();
			obj_advisory_xml.ques_pro_userint 		= $('input[name="pro_userint"]:checked', context).val();

			obj_advisory_xml.solution = $('#advisory-solution-text', context).val();
			obj_advisory_xml.tlpamber = $('#advisory-tlpamber-text', context).val();
			obj_advisory_xml.summary  = $('#advisory-summary-text', context).val()

			obj_advisory_xml.update   = $('#advisory-update-text', context).val()
			obj_advisory_xml.consequences	= $('#advisory-consequences-text', context).val();
			obj_advisory_xml.description	= $('#advisory-description-text', context).val();			

			obj_advisory_xml.damageIds = new Array(); 
			$('input[name="damage_description"]:checked', context).each( function () {
				obj_advisory_xml.damageIds.push( $(this).val() );
			});

			var queryString = 'publicationJson=' + encodeURIComponent( JSON.stringify(obj_advisory_xml) ) 
				+ '&publication=advisory'
				+ '&publicationid=' + params.publicationid
				+ '&publication_type=xml';

			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'common_actions',
				action: 'getPulicationPreview',
				queryString: queryString,
				success: getPulicationPreviewCallback
			});

			$(":button:contains('Print preview')")
				.prop('disabled', true)
				.addClass('ui-state-disabled');

		} else {
			var obj_advisory = new Object();

			obj_advisory.update       = ( $('#advisory-update-text', context).val() ) ? $('#advisory-update-text', context).val() : "";
			obj_advisory.summary      = ( $('#advisory-summary-text', context).val() ) ? $('#advisory-summary-text', context).val() : "";
			obj_advisory.solution     = $('#advisory-solution-text', context).val();
			obj_advisory.tlpamber     = $('#advisory-tlpamber-text', context).val();
			obj_advisory.consequences = $('#advisory-consequences-text', context).val();

			obj_advisory['publication_advisory.description'] = $('#advisory-description-text', context).val();

			obj_advisory.hyperlinks = '';
			$('input[name="advisory_links"]:checked', context).each( function () {
				obj_advisory.hyperlinks += $(this).val() + '\n';
			});

			obj_advisory.hyperlinks += $('.advisory-details-additional-links', context).val();

			obj_advisory.fullname	= $('#advisory-details-author', context).html();
			obj_advisory.ids		= $('#advisory-details-cveid', context).val();
			obj_advisory.damage		= $('#advisory-details-damage option:selected', context).val();
			obj_advisory.probability = $('#advisory-details-probability option:selected', context).val();

			obj_advisory.title 		= $('#advisory-details-title', context).val();
			var govcertid_version	= $('#advisory-details-id', context).text();
			obj_advisory.govcertid	= govcertid_version.replace( /^(.*?) \[.*/ , "$1" );
			obj_advisory.version	= govcertid_version.replace( /.*?\[v(.*?)\]/ , "$1" );

			obj_advisory['damage_description.description'] = new Array(); 

			$('input[name="damage_description"]:checked + label', context).each( function () {
				var obj_temp = new Object();
				obj_temp.description = $(this).text();
				obj_advisory['damage_description.description'].push( obj_temp );
			});

			obj_advisory.platforms_text = $('#advisory-platforms-txt', context).val();
			obj_advisory.products_text = $('#advisory-products-txt', context).val();
			obj_advisory.versions_text = $('#advisory-versions-txt', context).val();		
			obj_advisory.published_on = '';

			var queryString = 'publicationJson=' + encodeURIComponent( JSON.stringify(obj_advisory) ) 
				+ '&publication=advisory'
				+ '&publicationid=' + params.publicationid
				+ '&publication_type=' + $('input[name="preview_type"]', context).val();

			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'common_actions',
				action: 'getPulicationPreview',
				queryString: queryString,
				success: getPulicationPreviewCallback
			});

			$(":button:contains('Print preview')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		}
	});

	// open notifications details window
	$('.advisory-details-notification-link').click( function () {
		dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'write',
			pageName: 'advisory',
			action: 'openDialogAdvisoryNotificationDetails',
			queryString: 'id=' + $(this).attr('data-errorid'),
			success: null
		});				

		dialog.dialog('option', 'title', 'Advisory notification details');
		dialog.dialog('option', 'width', '650px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});

	// trigger click on first tab to display the correct buttons 
	$('a[href="#advisory-details-tabs-general"]', context).trigger('click');

	// adjust width of publications details dialog because of the many tabs
	var dialogWidth = (params.isUpdate == 1) ? '990px' : '920px';
	$.main.activeDialog.dialog('option', 'width', dialogWidth);
}

function setAdvisoryUIBehavior (context ) {

	// platforms text changes automagicly when adding or removing platforms
	$('#advisory-platforms-left-right .btn-option-to-left, #advisory-platforms-left-right .btn-option-to-right', context).click( function () {
		var platformsText = '';
		$(this).parent().siblings('div').children('.select-left').children('option').each( function (i) {
			var option = $(this);
			platformsText += option.attr('data-producer') + ' ' + option.attr('data-name');
			if ( $.trim( option.attr('data-version') ) != '' ) {
				platformsText += ' ' + option.attr('data-version'); 
			}
			platformsText += "\n";
		});
		$(this).parentsUntil('#advisory-details-tabs-platforms').find('#advisory-platforms-txt').html( platformsText );
	});

	// products text and version text changes automagicly when adding or removing products
	$('#advisory-products-left-right .btn-option-to-left, #advisory-products-left-right .btn-option-to-right', context).click( function () {
		var productsText = '';
		var versionText = '';

		$(this).parent().siblings('div').children('.select-left').children('option').each( function (i) {
			var option = $(this);
			productsText += option.attr('data-producer') + ' ' + option.attr('data-name') + "\n";

			if ( $.trim( option.attr('data-version') ) != '' ) {
				versionText += option.attr('data-version') + "\n"; 
			}
		});

		$(this).parentsUntil('#advisory-details-tabs-products').find('#advisory-products-txt').html( productsText );
		$(this).parentsUntil('#advisory-details-tabs-products').find('#advisory-versions-txt').html( versionText );
	});	

	// select a template 
	$('.advisory-template-selection', context).change( function () {
		var selectElement = $(this);
		if ( selectElement.val() != '' ) {

			if ( selectElement.find('option:selected').parent().attr('label') == 'CVE list' ) {

				var selectedOptionElement = selectElement.find('option:selected');
				var cveLink = $('<span>')
						.addClass('span-link')
						.text( selectElement.val() )
						.click( function () {
							openDialogCVEDetails( selectElement.val() );
						});

				var additionalCVEInfo = $('<ul>');
				additionalCVEInfo.append('<li><br>CVE published: ' + selectedOptionElement.attr('data-published') + '</li>');
				additionalCVEInfo.append('<li><br>CVE modified: ' + selectedOptionElement.attr('data-modified') + '</li>');

				if ( selectedOptionElement.attr('data-hasdescription') == 0 ) {
					additionalCVEInfo.append('<li><br>CVE has no description</li>');
				}
				if ( selectedOptionElement.attr('data-hastranslation') == 0 ) {
					additionalCVEInfo.append('<li><br>no translation added yet</li>');
				}

				$('.publication-template-result[id="advisory-' + selectElement.attr('data-tab') + '-template"]', context)
					.html('')
					.append(cveLink)
					.append(additionalCVEInfo);

			} else {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'common_actions',
					action: 'getPublicationTemplate',
					queryString: 'templateid=' + selectElement.val() + '&tab=' + selectElement.attr('data-tab') + '&publicationType=advisory&publicationid=' + context.attr('data-publicationid'),
					success: getPublicationTemplateCallback
				});
			}
		}
	});

	sortOptions( $('#advisory-platforms-left-column', context).get()[0] );
	sortOptions( $('#advisory-products-left-column', context).get()[0] );

	// click on apply template
	$('.btn-advisory-details-apply-template', context).click( function () {
		var tab = $(this).attr('data-tab');
		var templateObject = new Object();
		var selectElement = $('.advisory-template-selection[data-tab="' + tab + '"]', context);
		var action = 'getTemplateText';

		if ( selectElement.val() != '' ) {

			if ( selectElement.find('option:selected').parent().attr('label') == 'CVE list' ) {
				action = 'getCVEText';
				templateObject['cveId'] = selectElement.val();
			} else {
				var templateArray = $('#advisory-' + tab + '-template :input', context).serializeArray();

				$.each( templateArray, function (i,templateInput) {
					if ( templateInput.name in templateObject ) {
						if ( typeof templateObject[templateInput.name] == 'object' ) {
							templateObject[templateInput.name].push( templateInput.value );
						} else {
							templateObject[templateInput.name] = new Array( templateObject[templateInput.name], templateInput.value );
						}
					} else {
						templateObject[templateInput.name] = templateInput.value;
					}
				});

				templateObject['template_id'] = selectElement.val();
			}

			templateObject['original_txt'] = $('#advisory-' + tab + '-text', context).val();

			var queryString = 'templateData=' + encodeURIComponent( JSON.stringify( templateObject ) )
				+ '&tab=' + tab 
				+ '&publicationid=' + context.attr('data-publicationid');

			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'common_actions',
				action: action,
				queryString: queryString,
				success: getTemplateTextCallback
			});
		}			
	});
}

function saveNewAdvisoryCallback ( params ) {

	if ( params.saveOk == 1 ) {

		if ( $('.selected-submenu').attr('id') == 'write-submenu' ) {

			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'getPublicationItemHtml',
				queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=advisory',
				success: getPublicationItemHtmlCallback
			});
		}

		$.main.activeDialog.dialog('close');

	} else {
		alert(params.message);
		$('#button-save-advisory').button('enable');
	}
}

function saveUpdateAdvisoryCallback ( params ) {
	if ( params.saveOk == 1 ) {

		if ( $('.selected-submenu').attr('id') == 'write-submenu' ) {
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'getPublicationItemHtml',
				queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=advisory',
				success: getPublicationItemHtmlCallback
			});			

			$('.img-publications-update[data-detailsid="' + params.detailsId + '"]').remove();
		}

		$.main.activeDialog.dialog('close');		

	} else {
		alert( params.message );
	}
} 

function getAdvisoryPreviewCallback ( params ) {
	if ( !params.message ) {
		var context = $('#advisory-preview-tabs[data-publicationid="' + params.publicationId + '"]');
		$('#advisory-preview-text', context).html(params.previewText);
	} else {
		alert( params.message );
	}
}

function saveAdvisoryNotesCallback ( params ) {
	if ( params.saveOk == 1 ) {
		var context = $('#advisory-preview-tabs[data-publicationid="' + params.publicationId + '"]');

		$('#advisory-preview-notes-save-result', context)
			.text('Notes have been saved')
			.show()
			.removeClass('hide');
	} else {
		$('#advisory-preview-notes-save-result', context)
			.text(params.message)
			.show()
			.removeClass('hide');
	}
}

function reloadAdvisoryHtml ( params ) {
	$.main.ajaxRequest({
		modName: 'write',
		pageName: 'publications',
		action: 'getPublicationItemHtml',
		queryString: 'insertNew=0&id=' + params.id + '&pubType=advisory',
		success: getPublicationItemHtmlCallback
	});
}

function printAdvisoryPreview(context) {

	var head = '<head><title>Advisory preview</title><style type="text/css">* {font-size: 11px} pre {font-family: Courier} h1 {font-size: 14px} .advisory-matrix-deviation {width: 400px} </style><meta charset="utf-8"></head>';


	var before = '';
	$('[data-printable]', context).each( function () {
		before += $(this).attr('data-printable') + "<br>\n";
	});

	var advisory = $('#advisory-details-preview-text', context).val();
	if(advisory===undefined) {
		advisory = $('#advisory-preview-text', context).val();
	}

	var matrices = '';
	$('.advisory-matrix', context).each( function () {
		matrices += "<table>\n" + $(this).html() + "</table><br>";
	});

	var html = "<!DOCTYPE html>\n<html>\n" + head
 		+ '<body onload="window.print();window.close()">' + "\n"
		+ before
		+ "<h1>Advisory to be previewed:</h1>\n"
		+ "<pre>" + advisory + "</pre>\n"
		+ "<h1 style='page-break-before: right'>Advisory matrix:</h1>\n"
		+ matrices
		+ "</body></html>\n";

	var win = window.open('','_blank','menubar,scrollbars,resizable');
	win.document.open();
	win.document.write(html);
	win.document.close();
}

