/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view constituent group details
	$(document).on( 'click', '.constituent-group-details-link, .btn-edit-constituent-group, .btn-view-constituent-group', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'openDialogConstituentGroupDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogConstituentGroupDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Constituent group details');
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
	
	// delete a constituent group
	$('#content').on( 'click', '.btn-delete-constituent-group', function () {
		if ( confirm('Are you sure you want to delete the constituent group?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_group',
				action: 'deleteConstituentGroup',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});

	// view constituent group details summary
	$('#content').on( 'click', '.btn-constituent-group-overview', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'openDialogConstituentGroupSummary',
			queryString: 'id=' + $(this).attr('data-id'),
			success: null
		});		
		
		dialog.dialog('option', 'title', 'Constituent group details summary');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Print summary': function () {
					printInput( $('#constituent-group-summary') );
				},
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});	
	
	// add a new constituent group
	$('#filters').on( 'click', '#btn-add-constituent-group', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'openDialogNewConstituentGroup',
			success: openDialogNewConstituentGroupCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new constituent group');
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

	// search constituent groups
	$('#filters').on('click', '#btn-constituent-group-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'searchConstituentGroups',
			queryString: $('#form-constituent-group-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do constituent group search on ENTER
	$('#filters').on('keypress', '#constituent-group-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-constituent-group-search').trigger('click');
		}
	});
	
});


function openDialogNewConstituentGroupCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#constituent-group-details-form[data-id="NEW"]');

		setConstituentGroupUIBehavior(context);
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {
					
					if ($("#constituent-group-details-name", context).val() == "") {
						alert("Please specify constituent name.");	
					} else {

						$('#constituent-group-members option, #constituent-group-software-hardware-left-column option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_group',
							action: 'saveNewConstituentGroup',
							queryString: $(context).serializeWithSpaces(),
							success: saveConstituentGroupCallback
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
}

function openDialogConstituentGroupDetailsCallback ( params ) {
	var context = $('#constituent-group-details-form[data-id="' + params.id + '"]');

	if ( params.writeRight == 1 ) { 

		setConstituentGroupUIBehavior(context);	
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( 
							$('.constituent-group-type-selected', context).val() != $('#constituent-group-details-type', context).val() 
							&& !confirm( 'Changing the Constituent Type will result in changes for all the members of this group. \n\nDo you wish to proceed?') 
					){
						return false;
					} else if ($("#constituent-group-details-name", context).val() == "") {
						alert("Please specify constituent name.");	
					} else {

						$('#constituent-group-members option, #constituent-group-software-hardware-left-column option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_group',
							action: 'saveConstituentGroupDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveConstituentGroupCallback
						});					
					}

				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
	} else {
		$('#constituent-group-details-tabs', context).newTabs();
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveConstituentGroupCallback ( params ) {
	
	if ( params.saveOk ) {
	
		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'getConstituentGroupItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function searchSoftwareHardwareConstituentGroupCallback ( params ) {

	var context = $('#constituent-group-details-form[data-id="' + params.id + '"]');
	
	// clear former searchresults
	$('#constituent-group-software-hardware-right-column option', context).each( function (i) {
		$(this).remove();
	});

	var rightColumn = $('#constituent-group-software-hardware-right-column', context);
	
	if ( params.softwareHardware.length > 0 ) {
		$.each( params.softwareHardware, function (i, sh) {
			
			//create option element and add to rightcolumn
			var searchResult = $('<option>')
				.html( sh.producer.substr(0,1).toUpperCase() + sh.producer.substr(1) + ' ' + sh.name + sh.version + ' (' + sh.description + ')' )
				.val( sh.id )
				.attr({
					'data-producer': sh.producer,
					'data-name': sh.name,
					'data-version': sh.version
				})
				.on('dblclick', function () { $('.btn-option-to-left').trigger('click') } )
				.appendTo( rightColumn );
			
			// mark all the options which are in use by constituents
			if ( sh.in_use > 0 ) {
				searchResult.addClass('option-sh-in-use');
			}
		});
		
	} else {
		// give the search inputfield a red border when no results are found
		$('#constituent-group-software-hardware-search', context)
			.css('border', '1px solid red')
			.keyup( function () {
				$(this).css('border', '1px solid #bbb');
			});
	}

	checkRightColumnOptions($('#constituent-group-software-hardware-left-column', context ), $('#constituent-group-software-hardware-right-column', context));
}

function checkMembershipCallback ( params ) {
	var context = $('#constituent-group-details-form[data-id="' + params.id + '"]');
	
	var count = 0;
	var confirmText = 'The following individuals are also member of another group: \n\r';
	$.each( params.individual, function ( individualId, groups ) {

		count++;
		var individualName = $('#constituent-group-all-individuals option[value="' + individualId + '"]').text();
		confirmText += '- ' + individualName + ' [';

		$.each( groups, function ( index ) {
			confirmText += groups[index] + ', ';
		});

		confirmText = confirmText.replace( /(.*?), $/, "$1" ) + ']\n\r';
	});

	if ( ( count > 0 && confirm( confirmText + '\n\rDo you wish to add selected individuals?' ) ) || count == 0 ) {
		$('#constituent-group-all-individuals option:selected', context).each( function(index) { 
			$('#constituent-group-members', context).append( $(this) );
		});

		sortOptions( $('#constituent-group-members', context)[0] );
	}
}

function setConstituentGroupUIBehavior (context) {
	$('#constituent-group-details-tabs', context).newTabs();
	
	// search software/hardware
	$('#btn-constituent-group-software-hardware-search', context).click( function () {
		if ( $('#constituent-group-software-hardware-search', context).val() != '' ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_group',
				action: 'searchSoftwareHardwareConstituentGroup',
				queryString: 'id=' + $(context).attr('data-id') + '&search=' + $('#constituent-group-software-hardware-search', context).val(),
				success: searchSoftwareHardwareConstituentGroupCallback
			});
		}
	});
	
	// perform check if new member is also member of other groups
	$('#btn-add-member', context).click( function (event) {

		var arrNewMembers = new Array();
		$('#constituent-group-all-individuals option:selected', context).each( function (i) {
			arrNewMembers.push( $(this).val() );
		});
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'checkMembership',
			queryString: 'id=' + $(context).attr('data-id') + '&members=' + encodeURIComponent( JSON.stringify( arrNewMembers ) ),
			success: checkMembershipCallback
		});			
	});
	
	// reset border of search input field 
	$('#constituent-group-software-hardware-search', context).keyup( function () {
		$(this).css({'border': '1px solid #B6B7B8', 'background-color': '#FFF'});
	});	

	// do software/hardware search on ENTER
	$('#constituent-group-software-hardware-search', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			$('#btn-constituent-group-software-hardware-search', context).trigger('click');
		}
	});
	
	$('input[type="text"]', context).keypress( function (event) {
		return checkEnter(event);
	});

	$('#constituent-group-details-shwh-use').click( function () {
		var use = $(this).is(':checked');
		//console.log('clicked_use: '+use);
		if(use) {
			$("#constituent-group-details-shwh-not-using").hide();
			$("#constituent-group-details-shwh-using").show();
		} else {
			$("#constituent-group-details-shwh-using").hide();
			$("#constituent-group-details-shwh-not-using").show();
		}
		return true;
	}).triggerHandler('click');

}
