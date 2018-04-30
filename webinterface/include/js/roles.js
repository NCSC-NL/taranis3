/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view role details
	$('#content').on( 'click', '.btn-edit-role, .btn-view-role', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'roles',
			action: 'openDialogRoleDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogRoleDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Role details');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
	});
	
	// delete a role
	$('#content').on( 'click', '.btn-delete-role', function () {
		if ( confirm('Are you sure you want to delete the role?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'roles',
				action: 'deleteRole',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new role
	$('#filters').on( 'click', '#btn-add-role', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'roles',
			action: 'openDialogNewRole',
			success: openDialogNewRoleCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new role');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});

	// search role
	$('#filters').on('click', '#btn-roles-search', function () {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'roles',
			action: 'searchRoles',
			queryString: $('#form-roles-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do constituent individual search on ENTER
	$('#filters').on('keypress', '#roles-filters-name', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-roles-search').trigger('click');
		}
	});
	
});

function openDialogNewRoleCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#role-details-form[data-id="NEW"]');

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#role-details-name", context).val() == "" ) {
						alert("Please specify a role name.");
					} else if (	$("#role-details-description", context).val() == "") {
						alert("Please specify a description.");
					} else {

						var oParticularizations = new Object();
						
						$('.selected-particularization', context ).each( function (i) {
							var id = $(this).attr('data-id');
							if ( oParticularizations[id] == undefined ) {
								oParticularizations[id] = new Array();
							}
							oParticularizations[id].push( $(this).attr('data-particularization') );
						}); 
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'roles',
							action: 'saveNewRole',
							queryString: $(context).serializeWithSpaces() + '&particularizations=' + encodeURIComponent( JSON.stringify( oParticularizations ) ),
							success: saveRoleCallback
						});					
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		setRoleUIBehavior( context );
	}
}

function openDialogRoleDetailsCallback ( params ) {
	var context = $('#role-details-form[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 

		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( $("#role-details-name", context).val() == "" ) {
						alert("Please specify a role name.");
					} else if (	$("#role-details-description", context).val() == "") {
						alert("Please specify a description.");
					} else {

						var oParticularizations = new Object();
						
						$('.selected-particularization', context ).each( function (i) {
							var id = $(this).attr('data-id');
							if ( oParticularizations[id] == undefined ) {
								oParticularizations[id] = new Array();
							}
							oParticularizations[id].push( $(this).attr('data-particularization') );
						}); 
						
						$('.selected-particularizations', context ).each( function (i) {
							if ( $(this).children('.selected-particularization').length == 0 ) {
								var id = $(this).attr('data-id');
								oParticularizations[id] = new Array();
							}
						});
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'roles',
							action: 'saveRoleDetails',
							queryString: $(context).serializeWithSpaces() + '&particularizations=' + encodeURIComponent( JSON.stringify( oParticularizations ) ) + '&id=' + params.id,
							success: saveRoleCallback
						});					
					}
				}
		    },			                                                 
			{
				text: 'Cancel',
				click: function () { $(this).dialog('close') }
			}
		]);
		
		setRoleUIBehavior( context );

	} else {
		$('#role-details-tabs', context).newTabs();
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveRoleCallback ( params ) {
	
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'roles',
			action: 'getRoleItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function setRoleUIBehavior ( context ) {
	$('input[type="text"]', context).keypress( function (event) {
		return checkEnter(event);
	});
	
	$('.role-details-rwx-right', context).click( function () {
		if ( $('#' + $(this).attr('for'), context).is(':checked') ) {
			$(this).removeClass('role-details-rwx-right-checked');
		} else {
			$(this).addClass('role-details-rwx-right-checked');
		}
	});
	
	$('#role-details-tabs', context).newTabs();	

	$('.btn-remove-particularization', context).click( function () {
		var particularizationText = $(this).parent().text().replace( /(.*?)X$/, "$1" );
		var entitlementId = $(this).parent().parent().attr('data-id');
		$('.select-particularizations[data-id="' + entitlementId + '"] option[value="' + particularizationText + '"]', context).removeClass('hidden');
		
		$(this).parent().remove();

		if ( $('.selected-particularizations[data-id="' + entitlementId + '"]', context).children().length == 0 ) {
			$('.selected-particularizations[data-id="' + entitlementId + '"]', context).append('<span class="all-particularizations" data-id="' + entitlementId + '">All particularizations</span>');
		}
	});
	
	$('.btn-add-particularization', context).click( function () {
		var id = $(this).attr('data-id'); 
	
		if ( $('.select-particularizations[data-id="' + id + '"]', context).val() == '' ) { return false }
		
		$('.all-particularizations[data-id="' + id + '"]', context).remove();
		
		var particularization = $('.select-particularizations[data-id="' + id + '"]', context).val();
		
		$('<span/>')
			.html( particularization )
			.addClass('selected-particularization')
			.append(
				$('<div />')
					.text('X')
					.addClass('btn-remove-particularization pointer')
					.click( function () {
						var particularizationText = $(this).parent().text().replace( /(.*?)X$/, "$1" );
						$('.select-particularizations[data-id="' + id + '"] option[value="' + particularizationText + '"]', context).show();
						
						$(this).parent().remove();
	
						if ( $('.selected-particularizations[data-id="' + id + '"]', context).children().length == 0 ) {
							$('.selected-particularizations[data-id="' + id + '"]', context).append('<span class="all-particularizations" data-id="' + id + '">All particularizations</span>');
						}
					})
			)
			.attr({'data-id': id, 'data-particularization': particularization })
			.appendTo('.selected-particularizations[data-id="' + id + '"]');
	
		$('.select-particularizations[data-id="' + id + '"] option:selected', context)
			.hide()
			.prop('selected', false);
		
		$('.select-particularizations[data-id="' + id + '"] option:first-child', context).prop('selected', true);
		
	});
}
