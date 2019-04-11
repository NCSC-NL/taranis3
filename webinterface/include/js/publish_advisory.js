/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogPublishAdvisoryCallback ( params ) {
	var context =  $('#advisory-publish-sh-selection-form[data-publicationid="' + params.publicationId + '"]');
	
	if ( params.lockOk == 1 ) {
	
		// setup dialog buttons
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Use AND selection',
				click: function () {
					
					if ( $(":button:contains('Use AND selection')").length > 0 ) {
						$('.publish-advisory-or-selection', context).addClass('hidden');
						$('.publish-advisory-and-selection', context).removeClass('hidden');
						$(":button:contains('Use AND selection') span").text( 'Use OR selection' );
	
						if ( $('.publish-and-selection-item', context).length == 0 ) {
							$(":button:contains('Select')")
								.prop('disabled', true)
								.addClass('ui-state-disabled');
						} else {
							$(":button:contains('Select')")
								.prop('disabled', false)
								.removeClass('ui-state-disabled');
						}
					} else {
						$('.publish-advisory-or-selection', context).removeClass('hidden');
						$('.publish-advisory-and-selection', context).addClass('hidden');
						$(":button:contains('Use OR selection') span").text( 'Use AND selection' );
						$('input[name="sh"]', context).triggerHandler('change');
					}
				}
			},
			{
				text: 'Select',
				click: function () {
					
					if ( $(":button:contains('Use AND selection')").length > 0 ) {
						
						if ( $('input[name="sh"]', context).length > 0 ) {
							$.main.ajaxRequest({
								modName: 'publish',
								pageName: 'publish_advisory',
								action: 'getConstituentList',
								queryString: $(context).find('input[name="sh"]').serializeWithSpaces() + '&id=' + params.publicationId + '&selectionType=OR',
								success: getConstituentListCallback
							});								
	
						} else {
							alert('At least one platform or product has to be selected to continue.');
						}
					} else {
	
						var andSelectionList = new Array(); 
						$('.publish-and-selection-item').each( function () {
							var andSelection = new Array();
							
							$(this).find( 'input[type="hidden"]' ).each( function () {
								andSelection.push( $(this).val() );
							});
							andSelectionList.push( andSelection );
						}); 
	
						if ( !andSelectionList[0]  ) {
							alert('At least one combination of platform and product has to be made to continue.');
						} else {
	
							$.main.activeDialog.dialog('option', 'buttons', []);
							$.main.activeDialog.html('<fieldset>loading constituents list...</fieldset>');
							
							$.main.ajaxRequest({
								modName: 'publish',
								pageName: 'publish_advisory',
								action: 'getConstituentList',
								queryString: 'id=' + params.publicationId + '&selectionType=AND&shList=' + encodeURIComponent( JSON.stringify( andSelectionList ) ),
								success: getConstituentListCallback
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
	
		// change close event for this dialog, so it will include clearing the opened_by of the advisory
		$.main.activeDialog.bind( "dialogclose", function(event, ui) {
	
			if ( 
				$.main.lastRequest.action != 'displayPublish' 
				&& $.main.lastRequest.action != 'closeAdvisoryPublication' 
				&& $.main.lastRequest.action != 'publishAdvisory'
			) {

				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish_advisory',
					action: 'closeAdvisoryPublication',
					queryString: 'id=' + params.publicationId,
					success: refreshPublicationList
				});			
			}
			if ( $('.dialogs:visible').length == 0 ) {
				$('#screen-overlay').hide();
			}
		});
		
		// click on button AND
		$('#btn-publish-platform-and-product', context).click( function () {
			
			if ( $('#publish-sh-platforms option:selected', context).length != 0 && $('#publish-sh-products option:selected', context).length != 0 ) {
	
				var platform = $('#publish-sh-platforms option:selected'),
					product  = $('#publish-sh-products option:selected'),
					is_duplicate = false,
					duplicate_tr = null;
				
				$('.publish-and-selection-item', context).each( function (i) {
					if ( 
						$('.publish-and-selection-platform[value="' + platform.val() + '"]', $(this)).length > 0 
						&& $('.publish-and-selection-product[value="' + product.val() + '"]', $(this)).length > 0 
					) {
						is_duplicate = true;
						duplicate_tr = $(this);
					}
					
				});
	
				if ( !is_duplicate ) {
					$('<tr/>')
						.addClass('publish-and-selection-item')
						.append(
							$('<td/>')
								.text( platform.html() )
								.append( 
									$('<input />')
										.attr({'type': 'hidden'})
										.addClass('publish-and-selection-platform')
										.val( platform.val() )
										
								)
						)
						.append('<td class="bold">AND</td>') 
						.append(
							$('<td/>')
								.text( product.html() )
								.append( 
									$('<input />')
										.attr({'type': 'hidden' })
										.addClass('publish-and-selection-product')										
										.val( product.val() )
								)
						)
						.append(
							$('<td/>')
								.css('width', '60px')
								.append(
									$('<input type="button" class="button" value="remove">')
										.click( function () {
											$(this).parent().parent().remove();
											if ( $('.publish-and-selection-item', context).length == 0 ) {
												$(":button:contains('Select')")
													.prop('disabled', true)
													.addClass('ui-state-disabled');
											} else {
												$(":button:contains('Select')")
													.prop('disabled', false)
													.removeClass('ui-state-disabled');
											}										
										})
								)
						)
						.appendTo('#publish-sh-and-selection-result');
				} else {
					$(duplicate_tr).effect("pulsate", { times:2 }, 100);
				}
			}
			
			$(":button:contains('Select')")
				.prop('disabled', false)
				.removeClass('ui-state-disabled');
		});
		
		// Platform(s), Select: All
		$('#span-select-all-platforms', context).click( function () {
			$(this).siblings('input').prop('checked', true);
	
			if ( $('input[name="sh"]:checked', context).length != 0 ) {
				$(":button:contains('Select')")
					.prop('disabled', false)
					.removeClass('ui-state-disabled');
			}		
		});
	
		// Platform(s), Select: None
		$('#span-select-none-platforms', context).click( function () {
			$(this).siblings('input').prop('checked', false);
	
			if ( $('input[name="sh"]:checked', context).length == 0 ) {
				$(":button:contains('Select')")
					.prop('disabled', true)
					.addClass('ui-state-disabled');
			}
		});
	
		// Product(s), Select: All
		$('#span-select-all-products', context).click( function () {
			$(this).siblings('input').prop('checked', true);
	
			if ( $('input[name="sh"]:checked').length != 0 ) {
				$(":button:contains('Select')")
					.prop('disabled', false)
					.removeClass('ui-state-disabled');
			}			
		});
	
		// Product(s), Select: None	
		$('#span-select-none-products', context).click( function () {
			$(this).siblings('input').prop('checked', false);
	
			if ( $('input[name="sh"]:checked').length == 0 ) {
				$(":button:contains('Select')")
					.prop('disabled', true)
					.addClass('ui-state-disabled');
			}		
		});
		
		// clicking on one of the options in AND selection
		$('#publish-sh-platforms, #publish-sh-products', context).change( function () {
			if ( $('#publish-sh-platforms option:selected', context).val() == 'X' ) {
				$('#publish-sh-products option[value="X"]', context).prop( 'disabled', true );
			} else if ( $('#publish-sh-products option:selected', context).val() == 'X' ) {
				$('#publish-sh-platforms option[value="X"]', context).prop( 'disabled', true );
			} else {
				$('#publish-sh-products option[value="X"]', context).prop( 'disabled', false);
				$('#publish-sh-platforms option[value="X"]', context).prop( 'disabled', false );
			}
		});
	
		// (un)check on of the option in OR selection
		$('input[name="sh"]', context).change( function () {
			if ( $('input[name="sh"]:checked', context).length == 0 ) {
				$(":button:contains('Select')")
					.prop('disabled', true)
					.addClass('ui-state-disabled');
			} else {
				$(":button:contains('Select')")
					.prop('disabled', false)
					.removeClass('ui-state-disabled');
			}
		});	
	} else {

		// change close event for this dialog
		$.main.activeDialog.bind( "dialogclose", function(event, ui) {
			$('#screen-overlay').hide();
			refreshPublicationList(null);
		});
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Close',
				click: function () { $(this).dialog('close'); }
			}
		]);
	}	
}

function getConstituentListCallback ( params ) {
	var context =  $('#advisory-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Set to Pending',
			click: function () {
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish_advisory',
					action: 'closeAdvisoryPublication',
					queryString: 'id=' + params.publicationId + '&setToPending=1',
					success: refreshPublicationList
				});
				
				$('#screen-overlay').hide();
				$(this).dialog('close');
			}
		},
		{
			text: 'Publish',
			id: 'button-publish-advisory',
			click: function () {
				$('#button-publish-advisory').button('disable');
				if ( 
					params.isHighHigh == '0' 
					|| confirm('The advisory has been scaled as HIGH propability and HIGH damage.\nAre you sure this is an High/High advisory?') 
				) {
					var publicationText = encodeURIComponent( $('#advisory-preview-text', context).val() );

					$.main.ajaxRequest({
						modName: 'publish',
						pageName: 'publish',
						action: 'checkPGPSigning',
						queryString: 'id=' + params.publicationId + '&publicationType=advisory&publicationText=' + publicationText,
						success: publishAdvisory,
						error: function() {
							$('#button-publish-advisory').button('enable');
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

function publishAdvisory ( params ) {
	
	var context =  $('#advisory-publish-form[data-publicationid="' + params.publicationId + '"]');

	if ( params.pgpSigningOk == 1 ) {

		$.main.activeDialog.dialog('option', 'buttons', []);
		$.main.activeDialog.html('Publishing Advisory...');
		
		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_advisory',
			action: 'publishAdvisory',
			queryString: $(context).serializeWithSpaces() + '&id=' + params.publicationId,
			success: publishAdvisoryCallback
		});
		
	} else {
		$(context).siblings('#dialog-error')
			.removeClass('hidden')
			.text(params.message);
		$('#button-publish-advisory').button('enable');
	}
}

function publishAdvisoryCallback ( params ) {

	// change close event for this dialog
	$.main.activeDialog.bind( "dialogclose", function(event, ui) {
		refreshPublicationList(null);
	});
	
	var buttons = new Array();

	if ( params.isHighHigh == 1 ) {
		buttons.push({
			text: 'Print calling list',
			click: function () {
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish_advisory',
					action: 'printCallingList',
					queryString: 'id=' + params.publicationId,
					success: printCallingListCallback
				});
			}
		});
		
		buttons.push({
			text: 'Download calling list',
			click: function () {
				var callingListParams = new Object();
				callingListParams.id = params.publicationId;
				$('#downloadFrame').attr( 'src', 'loadfile/publish/publish_advisory/saveCallingList?params=' + JSON.stringify(callingListParams) );
			}
		});
	}
	
	buttons.push({
		text: 'Close',
		click: function () { $(this).dialog('close') }
	});
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', buttons);	

}

function printCallingListCallback ( params ) {
	printHtmlInput( params.callingList );
}
