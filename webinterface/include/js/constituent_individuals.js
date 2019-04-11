/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view constituent individual details
	$('#content').on( 'click', '.btn-edit-constituent-individual, .btn-view-constituent-individual', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_individuals',
			action: 'openDialogConstituentIndividualDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogConstituentIndividualDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Constituent individual details');
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
	
	// delete a constituent individual
	$('#content').on( 'click', '.btn-delete-constituent-individual', function () {
		if ( confirm('Are you sure you want to delete the constituent individual?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_individuals',
				action: 'deleteConstituentIndividual',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new constituent individual
	$('#filters').on( 'click', '#btn-add-constituent-individual', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_individuals',
			action: 'openDialogNewConstituentIndividual',
			success: openDialogNewConstituentIndividualCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new constituent individual');
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

	// search constituent individuals
	$('#filters').on('click', '#btn-constituent-individual-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_individuals',
			action: 'searchConstituentIndividuals',
			queryString: $('#form-constituent-individual-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do constituent individual search on ENTER
	$('#filters').on('keypress', '#constituent-individual-filters-firstname, #constituent-individual-filters-lastname', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-constituent-individual-search').trigger('click');
		}
	});
	
});

function openDialogNewConstituentIndividualCallback ( params ) {
	var context = $('#constituent-individual-details-form[data-id="NEW"]');
	$('#constituent-individual-details-tabs', context).newTabs();
	if ( params.writeRight == 1 ) { 

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#constituent-individual-details-firstname", context).val() == "" ) {
						alert("Please specify first name.");
					} else if (	$("#constituent-individual-details-lastname", context).val() == "") {
						alert("Please specify last name.");
					} else if ( $('input[name="call247"]:checked', context).length == 0 ) {
						alert("Please specify if constituent is available 24/7.");
					} else if ( $('input[name="call_hh"]:checked', context).length == 0  ) {
						alert("Please specify if constituent wishes to be called in case of a High/High incident.");		
					} else {
					
						$('#constituent-individual-details-membership-groups option, #constituent-individual-details-selected-types option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_individuals',
							action: 'saveNewConstituentIndividual',
							queryString: $(context).serializeWithSpaces(),
							success: saveConstituentIndividualCallback
						});					
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
		
		// perform check if new member is also member of other groups
		$('.btn-add-member, .btn-remove-member', context).click( function (event) {

			var arrNewGroups = new Array();
			$('#constituent-individual-details-membership-groups option', context).each( function (i) {
				arrNewGroups.push( $(this).val() );
			});
			
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_individuals',
				action: 'checkPublicationTypes',
				queryString: 'id=' + $(context).attr('data-id') + '&groups=' + encodeURIComponent( JSON.stringify( arrNewGroups ) ),
				success: checkPublicationTypesCallback
			});			
		});		
	}
}

function openDialogConstituentIndividualDetailsCallback ( params ) {
	var context = $('#constituent-individual-details-form[data-id="' + params.id + '"]');
	$('#constituent-individual-details-tabs', context).newTabs();
	
	if ( params.writeRight == 1 ) { 

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#constituent-individual-details-firstname", context).val() == "" ) {
						alert("Please specify first name.");
					} else if (	$("#constituent-individual-details-lastname", context).val() == "") {
						alert("Please specify last name.");
					} else if ( $('input[name="call247"]:checked', context).length == 0 ) {
						alert("Please specify if constituent is available 24/7.");
					} else if ( $('input[name="call_hh"]:checked', context).length == 0  ) {
						alert("Please specify if constituent wishes to be called in case of a High/High incident.");		
					} else {
					
						$('#constituent-individual-details-membership-groups option, #constituent-individual-details-selected-types option', context).each( function (i){
							$(this).prop('selected', true);
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'constituent_individuals',
							action: 'saveConstituentIndividualDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveConstituentIndividualCallback
						});					
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
		
		// perform check if new member is also member of other groups
		$('.btn-add-member, .btn-remove-member', context).click( function (event) {

			var arrNewGroups = new Array();
			$('#constituent-individual-details-membership-groups option', context).each( function (i) {
				arrNewGroups.push( $(this).val() );
			});
			
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'constituent_individuals',
				action: 'checkPublicationTypes',
				queryString: 'id=' + $(context).attr('data-id') + '&groups=' + encodeURIComponent( JSON.stringify( arrNewGroups ) ),
				success: checkPublicationTypesCallback
			});			
		});		
		
	} else {
	
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveConstituentIndividualCallback ( params ) {
	
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_individuals',
			action: 'getConstituentIndividualItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function checkPublicationTypesCallback ( params ) {

	var allowed_types = params.publicationTypes;
	
	var types_left = document.getElementById('constituent-individual-details-selected-types'); // currently selected types in "Selected publication types"
	var types_right = document.getElementById('constituent-individual-details-all-types'); // currently selected type in "All publication types"

	var allowed_types_ids = new Array();

	// create an array with id's of the allowed pubication types
	for ( var j = 0; j < allowed_types.length; j++ ) {
		allowed_types_ids.push(allowed_types[j].id);
	}
	
    // remove items in "Selected publication types" which are no longer allowed
    for ( var i = 0; i < types_left.length ; i++ ) {
		var arr_pos = allowed_types_ids.find( types_left.options[i].value );

		if ( arr_pos === false ) {
			types_left.options[i] = null;
			i--;
		} else {

		    for ( type in allowed_types ) {
		        if ( $(types_left.options[i]).val() == allowed_types[type].id ) {		    	

				    if ( $(types_left.options[i]).hasClass('strikethrough') && allowed_types[type].group_status == "0" ) {
				        $(types_left.options[i]).removeClass('strikethrough');
				        
				    } else if ( !$(types_left.options[i]).hasClass('strikethrough') && allowed_types[type].group_status != "0" ) {
				    	$(types_left.options[i]).addClass('strikethrough');
				    }
				    break;
		        }
		    }
			
			allowed_types_ids.splice( arr_pos, 1 );
		}
	}

	// remove items in "All publication types" which are no longer allowed
	for ( var i = 0; i < types_right.length ; i++ ) {
		var arr_pos = allowed_types_ids.find( types_right.options[i].value );
		if ( arr_pos === false ) {
			types_right.options[i] = null;
			i--;
		} else {

            for ( type in allowed_types ) {
            	if ( $(types_right.options[i]).val() == allowed_types[type].id ) {

            		if ( $(types_right.options[i]).hasClass('strikethrough') && allowed_types[type].group_status == "0" ) {
	                    $(types_right.options[i]).removeClass('strikethrough');

		            } else if ( !$(types_right.options[i]).hasClass('strikethrough') && allowed_types[type].group_status != "0" ) {
	                    $(types_right.options[i]).addClass('strikethrough');
	                }
	                break;
            	}
            }
			
			allowed_types_ids.splice( arr_pos, 1 );
		}
	}

	// add new items in "All publication types" which can be used because of added membership
	for ( var i = 0; i < allowed_types.length; i++ ) {
				
		if ( allowed_types_ids.find( allowed_types[i].id ) !== false ) { 
			var type_option = new Option( allowed_types[i].title, allowed_types[i].id );

			if ( allowed_types[i].group_status != "0" ) { 
			    type_option.className = "strikethrough";
			}
			types_right.options[types_right.length] = type_option;
		} 
	}

	sortOptions(types_right);
}
