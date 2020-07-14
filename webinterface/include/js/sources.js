/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view source details
	$('#content').on( 'click', '.btn-edit-source, .btn-view-source', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: 'openDialogSourceDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: openDialogSourceDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Source details');
		dialog.dialog('option', 'width', '850px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a source
	$('#content').on( 'click', '.btn-delete-source', function () {
		if ( confirm('Are you sure you want to delete the source?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'sources',
				action: 'deleteSource',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteConfigurationItemCallback
			});
		}
	});
	
	// enable/disable source
	$('#content').on( 'click', 'label.sources-item-enabled-label', function () {
		
		var enable = ( $(this).hasClass('sources-item-enabled-label-checked') ) ? 0 : 1;
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: 'enableDisableSource',
			queryString: 'id=' + $(this).attr('data-id') + '&enable=' + enable,
			success: enableDisableSourceCallback
		}, true);		
	});
	
	// add a new source
	$('#filters').on( 'click', '#btn-add-source', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: 'openDialogNewSource',
			success: openDialogNewSourceCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new source');
		dialog.dialog('option', 'width', '850px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// search source
	$('#filters').on('click', '#btn-sources-search', function (event, origin) {
		if ( origin != 'pagination' && $('#hidden-page-number').length > 0) {
			$('#hidden-page-number').val('1');
		}

		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: 'searchSources',
			queryString: $('#form-sources-search').serializeWithSpaces(),
			success: null
		});
	});

	// do sources search on ENTER
	$('#filters').on('keypress', '#sources-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-sources-search').trigger('click');
		}
	});
	
});

function openDialogNewSourceCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#sources-details-form[data-id="NEW"]');
		
		setSourcesUIBehavior( context );
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Test source',
				click: function () {
					
					$('.dialog-highlight')
						.text('Testing connection settings...')
						.removeClass('hidden');
	
					$(":button:contains('Save'), :button:contains('Test source')")
						.prop('disabled', true)
						.addClass('ui-state-disabled');
					
					if ( $('#sources-details-protocol', context).val().match( /^(imap|pop3)/ ) ) {
					
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'sources',
							action: 'testMailServerConnection',
							queryString: $(context).find('.source-mail-settings').serializeWithSpaces() + '&testOnly=1',
							success: testConnectionCallback
						});
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'sources',
							action: 'testSourceConnection',
							queryString: $(context).find('.source-connection-settings').serializeWithSpaces() + '&testOnly=1',
							success: testConnectionCallback
						});
					}					
				}
			},
			{
				text: 'Save',
				click: function () {

					var selectedProtocol = $('#sources-details-protocol', context).val();
					
					if ( selectedProtocol == "" ) {
						alert("Please select a protocol.");
					} else if ( $('#sources-details-host', context).val() == "" ) {
						alert("Please specify the ip-address or hostname of the host.");
					} else if ( $('#sources-details-port', context).val() == "" ) {
						alert("Please specify the portnumber of the host.");
					} else if ( $('#sources-details-url', context).val() == "" && selectedProtocol.match( /^http/ ) ) {
						alert("Please specify the URL.");
					} else if ( $('#sources-details-parser', context).val() == "" && selectedProtocol.match( /^http/ ) ) {
						alert("Please specify the parser to be used.");
					} else if ( $('#sources-details-username', context).val() == "" && selectedProtocol.match( /^(imap|pop3)/ ) ) {
						alert("Please specify a username.");
					} else if ( $('#sources-details-password', context).val() == "" && selectedProtocol.match( /^(imap|pop3)/ ) ) {
						alert("Please specify a password.");
					} else if ( $('#sources-details-mailbox', context).val() == "" && selectedProtocol.match( /^imap/ ) ) {
						alert("Please specify a mailbox.");
					} else if ( $('#sources-details-archive-mailbox', context).val() == "" && selectedProtocol.match( /^imap/ ) ) {
						alert("Please specify a archive mailbox.");
					} else if ( !$("#sources-details-keep-mail-yes", context).is(':checked') && !$("#sources-details-keep-mail-no", context).is(':checked') && selectedProtocol.match( /^pop3/ ) ) {
						alert("Please check one of the options at 'Keep mail on server'.");
				 	} else if ( $("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-new-sourcename', context).val() == '' ) {
						alert("Please specify a name for the source.");
				 	} else if ( $("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-new-icon', context).val() == '' ) {
						alert("Please choose an icon image of 72 by 30 pixels.");
				 	} else if ( !$("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-sourcename', context).val() == '' ) {
						alert("Please select a source.");
					} else if ( $("#sources-details-category", context).val() == "" ) {
						alert("Please select a category.");
					} else if ( !$('#sources-details-checkid-yes', context).is(':checked') && !$('#sources-details-checkid-no', context).is(':checked') && selectedProtocol.match( /^http/ ) && $('#sources-details-parser', context).val() != 'twitter' ) {
						alert("Please check one of the options at 'check id'.");
					} else if ( $("#sources-details-mtbc", context).val() == "" ) {
						alert("Please specify the 'Minimum Time Between Checks' (mtbc).");
					} else if ( $("#sources-details-mtbc-use-random-delay", context).is(':checked') && !$.isNumeric($('#sources-details-mtbc-random-delay-max', context).val()) ) {
						alert("Please specify a valid maximum random delay.");
					} else if ( !$("#sources-details-contains-advisory-yes", context).is(':checked') && !$('#sources-details-contains-advisory-no', context).is(':checked') && selectedProtocol.match( /^imap/ ) ) {
						alert("Please check Advisory import settings.");
					} else if ( $("#sources-details-contains-advisory-yes", context).is(':checked') 
							&& selectedProtocol.match( /^imap/ )
							&& ( 
								( !$('#source-details-create-advisory-yes', context).is(':checked') && !$('#source-details-create-advisory-no', context).is(':checked') ) 
								|| $('#source-details-advisory-handler', context).val() == '' 
								) 
					) {
						alert("Please check Advisory import settings.");
					} else if ( !$("#sources-details-use-keyword-matching-yes", context).is(':checked') && !$('#sources-details-use-keyword-matching-no', context).is(':checked') ) {
						alert("Please check keyword filtering setting.");
					} else {
						
						if ( selectedProtocol.match( /^(imap|pop3)/ ) ) {
						
							$('.dialog-highlight')
								.text('Testing mailserver settings...')
								.removeClass('hidden');
	
							$(":button:contains('Save'), :button:contains('Test source')")
								.prop('disabled', true)
								.addClass('ui-state-disabled');
							
							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'sources',
								action: 'testMailServerConnection',
								queryString: $(context).find('.source-mail-settings').serializeWithSpaces() + '&testOnly=0&id=NEW',
								success: testConnectionCallback
							});
							
						} else {
							saveSource(context);
						}
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
		
		$('#sources-details-tabs', context).newTabs();

		$('#sources-details-use-keyword-matching-no', context).trigger('click');
		
	}
}

function openDialogSourceDetailsCallback ( params ) {
	var context = $('#sources-details-form[data-id="' + params.id + '"]');
	$('#sources-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) { 
		
		setSourcesUIBehavior( context );
		$('#sources-details-protocol', context).triggerHandler('change');
		$('input[name="use_keyword_matching"]', context).triggerHandler('change');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Test source',
				click: function () {
					$('.dialog-highlight')
						.text('Testing connection settings...')
						.removeClass('hidden');
	
					$(":button:contains('Save'), :button:contains('Test source')")
						.prop('disabled', true)
						.addClass('ui-state-disabled');
					
					if ( $('#sources-details-protocol', context).val().match( /^(imap|pop3)/ ) ) {
					
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'sources',
							action: 'testMailServerConnection',
							queryString: $(context).find('.source-mail-settings').serializeWithSpaces() + '&testOnly=1',
							success: testConnectionCallback
						});
					} else {
					
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'sources',
							action: 'testSourceConnection',
							queryString: $(context).find('.source-connection-settings').serializeWithSpaces() + '&testOnly=1',
							success: testConnectionCallback
						});
					}
				}
			},
			{
				text: 'Save',
				click: function () {

					var selectedProtocol = $('#sources-details-protocol', context).val();
					
					if ( selectedProtocol == "" ) {
						alert("Please select a protocol.");
					} else if ( $('#sources-details-host', context).val() == "" ) {
						alert("Please specify the ip-address or hostname of the host.");
					} else if ( $('#sources-details-port', context).val() == "" ) {
						alert("Please specify the portnumber of the host.");
					} else if ( $('#sources-details-url', context).val() == "" && selectedProtocol.match( /^http/ ) ) {
						alert("Please specify the URL.");
					} else if ( $('#sources-details-parser', context).val() == "" && selectedProtocol.match( /^http/ ) ) {
						alert("Please specify the parser to be used.");
					} else if ( $('#sources-details-username', context).val() == "" && selectedProtocol.match( /^(imap|pop3)/ ) ) {
						alert("Please specify a username.");
					} else if ( $('#sources-details-password', context).val() == "" && selectedProtocol.match( /^(imap|pop3)/ ) ) {
						alert("Please specify a password.");
					} else if ( $('#sources-details-mailbox', context).val() == "" && selectedProtocol.match( /^imap/ ) ) {
						alert("Please specify a mailbox.");
					} else if ( $('#sources-details-archive-mailbox', context).val() == "" && selectedProtocol.match( /^imap/ ) ) {
						alert("Please specify an archive mailbox.");
					} else if ( !$("#sources-details-keep-mail-yes", context).is(':checked') && !$("#sources-details-keep-mail-no", context).is(':checked') && selectedProtocol.match( /^pop3/ ) ) {
						alert("Please check one of the options at 'Keep mail on server'.");
				 	} else if ( $("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-new-sourcename', context).val() == '' ) {
						alert("Please specify a name for the source.");
				 	} else if ( $("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-new-icon', context).val() == '' ) {
						alert("Please choose an icon image of 72 by 30 pixels.");
				 	} else if ( !$("#sources-details-use-new-source", context).is(':checked') && $('#sources-details-sourcename', context).val() == '' ) {
						alert("Please select a source.");
					} else if ( $("#sources-details-category", context).val() == "" ) {
						alert("Please select a category.");
					} else if ( !$('#sources-details-checkid-yes', context).is(':checked') && !$('#sources-details-checkid-no', context).is(':checked') && selectedProtocol.match( /^http/ ) && $('#sources-details-parser', context).val() != 'twitter' ) {
						alert("Please check one of the options at 'check id'.");
					} else if ( $("#sources-details-mtbc", context).val() == "" ) {
						alert("Please specify the 'Minimum Time Between Checks' (mtbc).");
					} else if ( $("#sources-details-mtbc-use-random-delay", context).is(':checked') && !$.isNumeric($('#sources-details-mtbc-random-delay-max', context).val()) ) {
						alert("Please specify a valid maximum random delay.");
					} else if ( !$("#sources-details-contains-advisory-yes", context).is(':checked') && !$('#sources-details-contains-advisory-no', context).is(':checked') && selectedProtocol.match( /^imap/ ) ) {
						alert("Please check Advisory import settings.");
					} else if ( !$("#sources-details-use-keyword-matching-yes", context).is(':checked') && !$('#sources-details-use-keyword-matching-no', context).is(':checked') ) {
						alert("Please check keyword filtering setting.");
					} else {
						
						if ( selectedProtocol.match( /^(imap|pop3)/ ) ) {
							$('.dialog-highlight')
								.text('Testing mailserver settings...')
								.removeClass('hidden');
	
							$(":button:contains('Save'), :button:contains('Test source')")
								.prop('disabled', true)
								.addClass('ui-state-disabled');
							
							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'sources',
								action: 'testMailServerConnection',
								queryString: $(context).find('.source-mail-settings').serializeWithSpaces() + '&testOnly=0&id=' + params.id,
								success: testConnectionCallback
							});

						} else {
							saveSource(context);
						}
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

function saveSourceCallback ( params ) {
	
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: 'getSourceItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
	} else if ( params.digestAlreadyExists ) {
		
		if ( confirm( params.message ) ) {
			$('#sources-details-form').attr('data-id', params.id);
			$('#sources-details-digest', $('#sources-details-form ') ).val( params.digestAlreadyExists );
			saveSource( $('#sources-details-form') );
		}
		
	} else {
		alert(params.message)
	}
}

function enableDisableSourceCallback ( params ) {
	if ( params.enableOk == 1 ) {
		if ( params.enable == 1 ) {
			$('.sources-item-enabled-label[data-id="' + params.id + '"]').addClass('sources-item-enabled-label-checked');
			$('.sources-item-enabled-label[data-id="' + params.id + '"] span').text('enabled');
		} else {
			$('.sources-item-enabled-label[data-id="' + params.id + '"]').removeClass('sources-item-enabled-label-checked');
			$('.sources-item-enabled-label[data-id="' + params.id + '"] span').text('disabled');
		}
	} else {
		alert(params.message)
	}
}

function setSourcesUIBehavior ( context ) {
	
	// show protocol dependent input fields when changing the protocol setting
	$('#sources-details-protocol', context).change( function () {
		var selectedProtocol = $(this).val();
		
		$('.sources-protocol-dependent', context).hide();

		switch ( selectedProtocol ) {
		case 'http://': case 'https://':
			if ( $('#sources-details-parser', context).val() == 'twitter' ) {
				$('#sources-details-url-block, #sources-details-parser-block, #sources-details-screenshot-block', context).show();
			} else {
				$('#sources-details-url-block, #sources-details-parser-block, #sources-details-screenshot-block, #sources-details-checkid-block', context).show();
			}
			$('a[href="#sources-details-tabs-advisory-import"]', context).parent().hide();
			break;
		case 'imap': case 'imaps':
			$('#sources-details-username-block, #sources-details-password-block, #sources-details-mailbox-block, #sources-details-archive-mailbox-block, #sources-details-use-starttls-block', context).show();
			$('a[href="#sources-details-tabs-advisory-import"]', context).parent().show();
			break;
		case 'pop3': case 'pop3s':
			$('#sources-details-username-block, #sources-details-password-block, #sources-details-keep-mail-block', context).show();
			$('a[href="#sources-details-tabs-advisory-import"]', context).parent().show();
			break;
		}
	});

	$('#sources-details-parser', context).change( function () {
		$('#sources-details-protocol', context).triggerHandler('change');
	});
	
	$('input[name="source-icon"]', context).change( function () {
		if ( $(this).val() == '1' ) {
			$('#sources-details-use-new-source-block', context).show();
			$('#sources-details-use-existing-source-block', context).hide();
		} else {
			$('#sources-details-use-new-source-block', context).hide();
			$('#sources-details-use-existing-source-block', context).show();
		}
	});

	$('input[name="contains_advisory"]', context).change( function () {
		if ( $(this).val() == '1' ) {
			$('.sources-details-advisory-import', context)
				.removeClass('hidden')
				.show();
		} else {
			$('.sources-details-advisory-import', context).hide();
		}
	});
	
	// changing the custom collector module setting will show/hide the additional config input fields
	$('#sources-details-additional-collector-module', context).change( function () {
		$('.sources-details-additional-config', context)
			.removeClass('hidden')
			.hide();
		$('.sources-details-additional-config[data-collectormodule="' + $(this).val() + '"]', context).show();
	});
	
	// add wordlist setting
	$('#btn-add-more-source-wordlist', context).click( function () {
		
		var newTR = $('<tr>')
			.html( $('#tr-wordlist-default', context).html() )
			.addClass('border-dashed tr-wordlist-selection')
			.insertBefore( $('#tr-add-wordlist', context) );
		
		newTR.find('.select-source-details-wordlist2').prop('disabled', true);
		
	});
	
	// delete wordlist setting
	$(context).on('click', '.btn-delete-source-wordlist', function () {
		$(this).parents('tr').remove();
	})
	
	// disabled wordlist options when 'Use keyword filtering' is set to 'No'
	$('input[name="use_keyword_matching"]', context).change( function () {
		if ( $('#sources-details-use-keyword-matching-yes', context).is(':checked') ) {
			$('#table-source-details-wordlists select, #table-source-details-wordlists input, .btn-delete-source-wordlist', context).prop('disabled', false);

			$('.select-source-details-wordlist1', context).each( function () {
				if ( $(this).val() == '' ) {
					$(this).parents('tr').find('.select-source-details-wordlist2').prop('disabled', true);
				}
			});
			
		} else {
			$('#table-source-details-wordlists select, #table-source-details-wordlists input, .btn-delete-source-wordlist', context).prop('disabled', true);
		}
	});
	
	// actions after changing wordlist 1 selection
	$(context).on('change', '.select-source-details-wordlist1', function () {

		// disabled same select option in wordlist2 as is selected in wordlist1  
		$(this).parents('tr').find('.select-source-details-wordlist2 option').prop('disabled', false);
		$(this).parents('tr').find('.select-source-details-wordlist2 option[value="' + $(this).val() + '"]').prop('disabled', true);
		
		if ( $(this).val() != '' ) {
			$(this).parents('tr').find('.select-source-details-wordlist2').prop('disabled', false);
		} else {
			$(this).parents('tr').find('.select-source-details-wordlist2').prop('disabled', true);
		}
		
		if ( $(this).parents('tr').find('.select-source-details-wordlist2 option[value="' + $(this).val() + '"]').is(':selected') ) {
			$(this).parents('tr').find('.select-source-details-wordlist2 option[value="' + $(this).val() + '"]').prop('selected', false);
			$(this).parents('tr').find('.select-source-details-wordlist2 option[value=""]').prop('selected', true);
		}
	});
	
	// actions when using rating slider
	$(context).on('input', '#sources-details-rating', function () {
		$('#sources-details-rating-view', context).text( $(this).val() );
	});

	// toggling the 'mtbc-use-random-delay' checkbox should enable/disable the related elements
	$('#sources-details-mtbc-use-random-delay', context).change( function () {
		var checked = this.checked;
		$(context).find(
			"[data-depends-on='sources-details-mtbc-use-random-delay']"
		).each(function(i, element) {
			if (checked) {
				$(element).removeClass('ui-state-disabled').prop('disabled', false);
			} else {
				$(element).addClass('ui-state-disabled').prop('disabled', true);
			}
		});
	});
	$('#sources-details-mtbc-use-random-delay').trigger('change');
	
}

function saveSource ( context ) {
	
	var sourceId = $(context).attr('data-id');
	var action = ( $(context).attr('data-id') == 'NEW' ) ? 'saveNewSource' : 'saveSourceDetails';
	
	if ( $("#sources-details-use-new-source", context).is(':checked') ) {
		
		$('.select-source-details-wordlist2, .select-source-details-wordlist1', context).prop('disabled', false);
		
		var sourceData = new FormData( document.getElementById('sources-details-form') );
		var paramsObj = $(context).find('.include-in-form').serializeHash();

		if ( sourceId != 'NEW' ) {
			paramsObj.id = sourceId;
		}

		sourceData.append('params', JSON.stringify(paramsObj) );
		
		$.ajax({
			url: $.main.scriptroot + '/load/configuration/sources/' + action,
			data: sourceData,
			processData: false,
			type: 'POST',
			contentType: false,
			headers: {
				'X-Taranis-CSRF-Token': $.main.csrfToken,
			},
			dataType: 'JSON'
		}).done(function (result) {
			saveSourceCallback(result.page.params);
		});
		
	} else {
		
		$('.select-source-details-wordlist2, .select-source-details-wordlist1', context).prop('disabled', false);
		
		var queryString = $(context).find('.include-in-form').serializeWithSpaces() 
		if ( sourceId != 'NEW' ) {
			queryString += '&id=' + sourceId;
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'sources',
			action: action,
			queryString: queryString,
			success: saveSourceCallback
		});
	}
}

function testConnectionCallback ( params ) {

	$('.dialog-highlight').text(params.message);
	if ( params.checkOk == 1 ) {
		if ( params.testOnly == 0 ) {
			var context = ( params.id != '' ) ? $('#sources-details-form[data-id="' + params.id + '"]') : $('#sources-details-form[data-id="NEW"]');
			saveSource(context)
		}
	}
	$(":button:contains('Save'), :button:contains('Test source')")
		.prop('disabled', false)
		.removeClass('ui-state-disabled');
}
