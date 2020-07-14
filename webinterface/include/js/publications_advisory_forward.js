/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

var probabilityFields = new Array('pro_standard','pro_exploit', 'pro_details', 'pro_access', 'pro_credent', 'pro_complexity', 'pro_userint', 'pro_exploited', 'pro_expect', 'pro_solution');
var damageFields = new Array('dmg_dos', 'dmg_codeexec', 'dmg_remrights', 'dmg_privesc', 'dmg_infoleak');

function openDialogNewForwardCallback ( params ) {
	var publicationId = ( 'is_update' in params ) ? params.publicationid : 'NEW';
	
	var context = $('#forward-details-form[data-publicationid="' + publicationId + '"]');

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

	$('#forward-details-tabs', context).newTabs({selected: 0});

	// make sure the dialog resizes correctly in case the dialog was reused
	var dialogWidth = ( 'is_update' in params || 'is_import' in params ) ? '920px' : '860px';
	$.main.activeDialog.dialog('option', 'width', dialogWidth);
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Save',
			click: function () {
				
				if ( $('#advisory-details-title', context).val() == '' ) {
					alert('Please specify an advisory title.')
				} else if (!setProbability(1, context) && $('#advisory-details-pro-deviation', context).val() == '' ) {
					alert("Probability matrix does not match automatic scaling.\nPlease specify reason for deviation.");
				} else if (!setDamage(1, context) && $('#advisory-details-dmg-deviation', context).val() == '' ) {
					alert("Damage matrix does not match automatic scaling.\nPlease specify reason for deviation.");
				} else {
					
					$('#forward-platforms-left-column option', context).each( function (i) {
						$(this).prop('selected', true);
					});
					
					$('#forward-products-left-column option', context).each( function (i) {
						$(this).prop('selected', true);
					});
					
					if ( publicationId == 'NEW' ) {
						saveAdvisoryForward( 'saveNewForward', $('#forward-details-form[data-publicationid="NEW"]'), saveNewAdvisoryForwardCallback );
					} else {
						saveAdvisoryForward( 'saveUpdateForward', $('#forward-details-form[data-publicationid="' + publicationId + '"]'), saveNewAdvisoryForwardCallback );
					}
				} 
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);

	// search platforms
	$('#btn-advisory-platforms-search', context).click( function () {
		searchSoftwareHardwareWrite( context, 'platforms', publicationId, 'forward' );
	});

	// search products
	$('#btn-advisory-products-search', context).click( function () {
		searchSoftwareHardwareWrite( context, 'products', publicationId, 'forward' );
	});
	
	// do platforms search on ENTER
	$('#forward-platforms-search', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-advisory-platforms-search', context).trigger('click');
		}
	});

	// do products search on ENTER
	$('#forward-products-search', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-advisory-products-search', context).trigger('click');
		}
	});
	
	setForwardUIBehavior(context);
}

function openDialogUpdateForwardCallback ( params ) {
	params['is_update'] = true;
	openDialogNewForwardCallback( params );
}

function openDialogPreviewForwardCallback ( params ) {

	var context = $('#advisory-preview-tabs[data-publicationid="' + params.publicationid + '"]');
	
	$('#advisory-details-tabs-matrix *', context).prop('disabled', true);
	
	var buttons = new Array(),
		buttonSettings = new Array(),
		status = 0;
	
	if ( params.isLocked == 0 && params.noStatusChangeButtons == 0 ) {
		// available button settings:
		// [ { text: "Set to Pending", status: 0 }, { text: "Ready for review", status: 1 } , { text: "Approve", status: 2 } ]
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
						pageName: 'forward',
						action: 'setForwardStatus',
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
			click: function () {
				var printBefore = '';
				$('[data-printable]', context).each( function () {
					printBefore += $(this).attr('data-printable') + "\n";
				});
				$('#advisory-preview-text', context).attr( 'data-printbefore', printBefore );
				
				printInput( $('#advisory-preview-text', context) );
			}
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
							queryString: 'publicationType=forward&publicationId=' + params.publicationid + '&notes=' + $('#advisory-preview-notes', context).val() ,
							success: saveForwardNotesCallback
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
					success: reloadForwardHtml
				});			
			}
			
			if ( $('.dialogs:visible').length == 0 ) {
				$('#screen-overlay').hide();
			}
		});
	}
	
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
		if ( $(this).attr('href') == '#advisory-preview-tabs-notes' && params.writeRight == 1 ) {
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

function openDialogForwardDetailsCallback ( params ) {
	var context =  $('#forward-details-form[data-publicationid="' + params.publicationid + '"]');
	
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
					$('#advisory-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#advisory-details-preview-text', context) );
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
		
		$('#advisory-details-preview-text', context).prop('disabled', false);
		
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
					$('#advisory-details-preview-text', context).attr( 'data-printbefore', printBefore );
					printInput( $('#advisory-details-preview-text', context) );
				}
			},
			{
				text: 'Ready for review',
				click: function () { 
	
					if ( $('#advisory-details-title', context).val() == '' ) {
						alert('Please specify an advisory title.')
					} else if (!setProbability(1, context) && $('#advisory-details-pro-deviation', context).val() == '' ) {
						alert("Probability matrix does not match automatic scaling.\nPlease specify reason for deviation.");
					} else if (!setDamage(1, context) && $('#advisory-details-dmg-deviation', context).val() == '' ) {
						alert("Damage matrix does not match automatic scaling.\nPlease specify reason for deviation.");
					} else {
					
						$('#forward-platforms-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});
						
						$('#forward-products-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});
						
						saveAdvisoryForward( 'saveForwardDetails', $('#forward-details-form[data-publicationid="' + params.publicationid + '"]'), null );
						
						$.main.ajaxRequest({
							modName: 'write',
							pageName: 'forward',
							action: 'setForwardStatus',
							queryString: 'publicationId=' + params.publicationid + '&status=1',
							success: setPublicationCallback
						});
					}
				}
			},
			{
				text: 'Save',
				click: function () {
					
					if ( $('#advisory-details-title', context).val() == '' ) {
						alert('Please specify an advisory title.')
					} else if (!setProbability(1, context) && $('#advisory-details-pro-deviation', context).val() == '' ) {
						alert("Probability matrix does not match automatic scaling.\nPlease specify reason for deviation.");
					} else if (!setDamage(1, context) && $('#advisory-details-dmg-deviation', context).val() == '' ) {
						alert("Damage matrix does not match automatic scaling.\nPlease specify reason for deviation.");
					} else {
					
						$('#forward-platforms-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});
						
						$('#forward-products-left-column option', context).each( function (i) {
							$(this).prop('selected', true);
						});
						
						saveAdvisoryForward( 'saveForwardDetails', $('#forward-details-form[data-publicationid="' + params.publicationid + '"]'), setPublicationCallback );
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
					success: reloadForwardHtml
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
		
		// search platforms
		$('#btn-advisory-platforms-search', context).click( function () {
			searchSoftwareHardwareWrite( context, 'platforms', params.publicationid, 'forward' );	
		});
	
		// search products
		$('#btn-advisory-products-search', context).click( function () {
			searchSoftwareHardwareWrite( context, 'products', params.publicationid, 'forward' );
		});
		
		// do platforms search on ENTER
		$('#forward-platforms-search', context).keypress( function (event) {
			if ( !checkEnter(event) ) {
				$('#btn-advisory-platforms-search', context).trigger('click');
			}
		});
	
		// do products search on ENTER
		$('#forward-products-search', context).keypress( function (event) {
			if ( !checkEnter(event) ) {
				$('#btn-advisory-products-search', context).trigger('click');
			}
		});
		
		setReadyForReviewButton( context );
		setForwardUIBehavior(context);
		
	}
	
	$('#forward-details-tabs', context).newTabs({selected: 0});
	
	// update preview text and show/hide ' Print preview' button
	$('a[href^="#advisory-details-tabs-"]', context).click( function () {
		if ( $(this).attr('href') == '#advisory-details-tabs-preview' ) {
			
			var obj_advisory = new Object();
	
			obj_advisory.update       = ( $('#advisory-update-text', context).val() ) ? $('#advisory-update-text', context).val() : "";
			obj_advisory.summary      = ( $('#advisory-summary-text', context).val() ) ? $('#advisory-summary-text', context).val() : "";
			obj_advisory.source       = ( $('#advisory-source-text', context).val() ) ? $('#advisory-source-text', context).val() : "";
			obj_advisory.tlpamber     = $('#advisory-tlpamber-text', context).val();
			
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
	
			obj_advisory.platforms_text = $('#forward-platforms-txt', context).val();
			obj_advisory.products_text = $('#forward-products-txt', context).val();
			obj_advisory.versions_text = $('#forward-versions-txt', context).val();		
			obj_advisory.published_on = '';
			
			var queryString = 'publicationJson=' + encodeURIComponent( JSON.stringify(obj_advisory) ) 
				+ '&publication=advisory'
				+ '&publicationid=' + params.publicationid
				+ '&publication_type=forward';
			
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'common_actions',
				action: 'getPulicationPreview',
				queryString: queryString,
				success: getPulicationPreviewCallback
			});
			
			$(":button:contains('Print preview')").show();
 		} else {
			$(":button:contains('Print preview')").hide();
		}
	});
	
	// trigger click on first tab to display the correct buttons 
	$('a[href="#advisory-details-tabs-general"]', context).trigger('click');
	
	// adjust width of publications details dialog because of the many tabs
	$.main.activeDialog.dialog('option', 'width', '920px');
	
}

function setForwardUIBehavior ( context ) {

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
		$(this).parentsUntil('#advisory-details-tabs-platforms').find('#forward-platforms-txt').html( platformsText );
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
		
		$(this).parentsUntil('#advisory-details-tabs-products').find('#forward-products-txt').html( productsText );
		$(this).parentsUntil('#advisory-details-tabs-products').find('#forward-versions-txt').html( versionText );
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
				
				$('.publication-template-result[id="forward-' + selectElement.attr('data-tab') + '-template"]', context)
					.html('')
					.append(cveLink)
					.append(additionalCVEInfo);
				
			} else {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'common_actions',
					action: 'getPublicationTemplate',
					queryString: 'templateid=' + selectElement.val() + '&tab=' + selectElement.attr('data-tab') + '&publicationType=forward&publicationid=' + context.attr('data-publicationid'),
					success: getPublicationTemplateCallback
				});
			}
		}

	});
	
	sortOptions( $('#forward-platforms-left-column', context).get()[0] );
	sortOptions( $('#forward-products-left-column', context).get()[0] );
	
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
				var templateArray = $('#forward-' + tab + '-template :input', context).serializeArray();
	
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
	
	// remove publication attachment input
	$('.btn-delete-publication-file', context).click( function () {
		$(this).parent().remove();
	});
	
	// add publication attachment input
	$('#advisory-details-add-file', context).click( function () {
		var cloneBlock = $(this).siblings('.hidden');
		var clonedBlock = cloneBlock
			.clone(true,true)
			.insertBefore(cloneBlock)
			.removeClass('hidden');
		
		clonedBlock.children('input:first').focus();
	});	

	// remove publication attachment
	$('.btn-delete-publication-attachment', context).click( function () {
		$('tr[data-attachmentid="' + $(this).attr('data-attachmentid') + '"]').remove();
	});
	
	// add publication screenshot url to list
	$('#btn-add-publication-screenshot-url', context).click( function () {
		var selectedURL = $('#advisory-details-screenshot-url-select option:selected', context),
			screenshotDescription = $('#advisory-details-screenshot-url-description', context);
		
		if ( selectedURL.val() !== undefined ) {
			$('<li>')
				.addClass('padding-default')
				.append('<input type="hidden" class="include-in-form" name="screenshot_url" value="' + selectedURL.val() + '">')
				.append('<span title="' + selectedURL.val() + '" class="advisory-details-screenshot-url-item-span break-word block align-top">' + selectedURL.val() + '</span>&nbsp;&nbsp;')
				.append('<input type="text" name="screenshot_description" placeholder="screenshot description" class="include-in-form input-default dialog-input-text-narrow" value="' +  screenshotDescription.val() + '">&nbsp;&nbsp;')
				.append(
					$('<img>')
						.attr( 'src', $.main.webroot + '/images/icon_delete.png')
						.click( 
							function () {
								$('<option>')
									.val( $(this).siblings('input[type="hidden"]').val() )
									.html( $(this).siblings('input[type="hidden"]').val() )
									.appendTo( $('#advisory-details-screenshot-url-select', context) );
								$(this).parent().remove();
							}
						)
						.addClass('pointer align-middle')
				)
				.appendTo( $('#advisory-details-screenshot-url-list', context ) );
			
			screenshotDescription.val('');
			selectedURL.remove();
		}
	});
}

function getForwardPreviewCallback ( params ) {
	if ( !params.message ) {
		var context = $('#advisory-preview-tabs[data-publicationid="' + params.publicationId + '"]');
		$('#advisory-preview-text', context).html(params.previewText);
	} else {
		alert( params.message );
	}
}

function saveForwardNotesCallback ( params ) {
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

function reloadForwardHtml ( params ) {
	$.main.ajaxRequest({
		modName: 'write',
		pageName: 'publications',
		action: 'getPublicationItemHtml',
		queryString: 'insertNew=0&id=' + params.id + '&pubType=forward',
		success: getPublicationItemHtmlCallback
	});
}

function saveNewAdvisoryForwardCallback ( params ) {
	if ( params.saveOk == 1 ) {
		if ( $('.selected-submenu').attr('id') == 'write-submenu' ) {
		
			$.main.ajaxRequest({
				modName: 'write',
				pageName: 'publications',
				action: 'getPublicationItemHtml',
				queryString: 'insertNew=1&id=' + params.publicationId + '&pubType=forward',
				success: getPublicationItemHtmlCallback
			});			
			
			if ( params.isUpdate ) {
				$('.img-publications-update[data-detailsid="' + params.detailsId + '"]').remove();
			}
		}
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert( params.message )
	}
}

function saveAdvisoryForward ( action, form, callback ) {
	
	$(":button:contains('Save'), :button:contains('Cancel'), :button:contains('Ready for review')")
		.prop('disabled', true)
		.addClass('ui-state-disabled');
	
	var formData = new FormData(),
		undefined;
	
	$('.publication-files-input').each( function (i) {
		if ( $(this)[0].files[0] ) {
			formData.append('publicationFiles', $(this)[0].files[0] );
		}
	});
	
	var paramsObj = form.find('.include-in-form').serializeHash();
	formData.append('params', JSON.stringify(paramsObj) );

	// disable all fields because file uploading and/or creating screenshots can take a while
	$('input, select, textarea', form).each( function (index) {
		$(this).prop('disabled', true);
	});

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

	$.main.taranisSpinner.start();

	$.ajax({
		url: $.main.scriptroot + '/load/write/forward/' + action,
		data: formData,
		processData: false,
		type: 'POST',
		contentType: false,
		headers: {
			'X-Taranis-CSRF-Token': $.main.csrfToken,
		},
		dataType: 'JSON'
	}).always(function() {
		$.main.taranisSpinner.stop();
	}).done(function (result) {
		if ( callback != undefined ) {
			callback( result.page.params );
		}
	}).fail(function () {
		alert('Oh dear...');
	});
}
