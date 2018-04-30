/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view pattern details
	$('#content').on( 'click', '.btn-edit-pattern, .btn-view-pattern', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'id_patterns',
			action: 'openDialogIDPatternDetails',
			queryString: 'id=' + encodeURIComponent( $(this).attr('data-id') ),				
			success: openDialogIDPatternDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'ID Pattern details');
		dialog.dialog('option', 'width', '600px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');		
	});
	
	// delete pattern
	$('#content').on( 'click', '.btn-delete-pattern', function () {
		if ( confirm('Are you sure you want to delete this pattern?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'id_patterns',
				action: 'deleteIDPattern',
				queryString: 'id=' + encodeURIComponent( $(this).attr('data-id') ),				
				success: deleteIDPatternCallback
			});		
		}		
	});
	
	// add a new pattern
	$('#filters').on( 'click', '#btn-add-pattern', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'id_patterns',
			action: 'openDialogNewIDPattern',
			success: openDialogNewIDPatternCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new ID Pattern');
		dialog.dialog('option', 'width', '600px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// search patterns
	$('#filters').on('click', '#btn-patterns-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'id_patterns',
			action: 'searchIDPatterns',
			queryString: $('#form-patterns-search').serializeWithSpaces(),
			success: null
		});
	});	
	
	// do patterns search on ENTER
	$('#filters').on('keypress', '#patterns-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-patterns-search').trigger('click');
		}
	});	
	
});


function openDialogNewIDPatternCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-patterns[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {
					if (
						validateRegexp( $('#patterns-details-pattern', context).val() )
						&& validateRegexp( $('#patterns-details-substitute', context).val() )
					) {
						if ( $.trim( $("#patterns-details-idname", context).val() ) == "" ) {
							alert("Please specify a name for the pattern.");
						} else if ( $.trim( $("#patterns-details-pattern", context).val() ) == "" ) {
							alert("Please specify the pattern.");
						} else {
							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'id_patterns',
								action: 'saveNewIDPattern',
								queryString: $('#form-patterns[data-id="NEW"]').serializeWithSpaces(),
								success: saveNewIDPatternCallback
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
		
		$('#btn-patterns-details-validate-pattern, #btn-patterns-details-validate-substitute', context).click( function () {
			if ( validateRegexp( $(this).siblings('input').val() ) ) {
				alert('The regular expression is valid.');
			}
		});
		
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});
	}
}

function openDialogIDPatternDetailsCallback ( params ) {
	var context = $('#form-patterns[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if (
						validateRegexp( $('#patterns-details-pattern', context).val() )
						&& validateRegexp( $('#patterns-details-substitute', context).val() )
					) {
					
						if ( $.trim( $("#patterns-details-idname", context).val() ) == "" ) {
							alert("Please specify a name for the pattern.");
						} else if ( $.trim( $("#patterns-details-pattern", context).val() ) == "" ) {
							alert("Please specify the pattern.");
						} else {
	
							$.main.ajaxRequest({
								modName: 'configuration',
								pageName: 'id_patterns',
								action: 'saveIDPatternDetails',
								queryString: $(context).serializeWithSpaces() + '&originalId=' + encodeURIComponent( params.id),
								success: saveIDPatternDetailsCallback
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

		$('#btn-patterns-details-validate-pattern, #btn-patterns-details-validate-substitute', context).click( function () {
			if ( validateRegexp( $(this).siblings('input').val() ) ) {
				alert('The regular expression is valid.');
			}
		});
		
		$('input[type="text"]', context).keypress( function (event) {
			return checkEnter(event);
		});
		
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveNewIDPatternCallback ( params ) {
	
	if ( params.saveOk ) {
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'id_patterns',
			action: 'getIDPatternItemHtml',
			queryString: 'insertNew=1&id=' + encodeURIComponent( params.id ),
			success: getIDPatternItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function saveIDPatternDetailsCallback ( params ) {
	if ( params.saveOk ) {
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'id_patterns',
			action: 'getIDPatternItemHtml',
			queryString: 'originalId=' + encodeURIComponent( params.originalId) + '&id=' + encodeURIComponent( params.id ),
			success: getIDPatternItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function getIDPatternItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('#patterns-content-heading').after( params.itemHtml );
	} else {
		var patternsIdentifier = encodeURIComponent( params.originalId );
		patternsIdentifier = patternsIdentifier.replace( /%/g, '\\%' )
		patternsIdentifier = patternsIdentifier.replace( /\./g, '\\.' )
		patternsIdentifier = patternsIdentifier.replace( /\:/g, '\\:' )
		
		$('#' + patternsIdentifier )
			.html( params.itemHtml )
			.attr('id', encodeURIComponent( params.id ) );
	}
}

function deleteIDPatternCallback ( params ) {
	if ( params.deleteOk == 1 ) {
		var patternsIdentifier = encodeURIComponent( params.id );
		patternsIdentifier = patternsIdentifier.replace( /%/g, '\\%' );
		patternsIdentifier = patternsIdentifier.replace( /\./g, '\\.' );
		patternsIdentifier = patternsIdentifier.replace( /\:/g, '\\\:' );

		$('#' + patternsIdentifier ).remove();
	} else {
		alert(params.message);
	}
}

function validateRegexp (regex) {
	
	if ( regex == '' ) {
		return true;
	}
	
	try {
		var re = new RegExp( regex, "g");
		var result = re.test("test");
	}
	catch (err) {
		var error = true;
		alert(err);
		return false;
	}
	
	return true;
}
