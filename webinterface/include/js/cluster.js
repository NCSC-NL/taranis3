/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view cluster details
	$('#content').on( 'click', '.btn-edit-cluster, .btn-view-cluster', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cluster',
			action: 'openDialogClusterDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogClusterDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Cluster details');
		dialog.dialog('option', 'width', '500px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');		
	});
	
	// delete a cluster
	$('#content').on( 'click', '.btn-delete-cluster', function () {
		if ( confirm('Are you sure you want to delete the cluster?') ) { 
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'cluster',
				action: 'deleteCluster',
				queryString: 'id=' + $(this).attr('data-id'),				
				success: deleteConfigurationItemCallback
			});		
		}		
	});
	
	// add a new cluster
	$('#filters').on( 'click', '#btn-add-cluster', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cluster',
			action: 'openDialogNewCluster',
			success: openDialogNewClusterCallback
		});		
		
		dialog.dialog('option', 'title', 'Add new cluster');
		dialog.dialog('option', 'width', '500px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
		dialog.dialog('open');
	});
	
});


function openDialogNewClusterCallback ( params ) {
	if ( params.writeRight == 1 ) { 
		var context = $('#form-cluster[data-id="NEW"]');
		
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( 
						$('#cluster-details-threshold', context).val() == '' 
						|| $.isNumeric( $('#cluster-details-threshold', context).val() ) == false 
					) {
						alert("Please specify a numeric value for cluster threshold.");
					} else if ( 
						$('#cluster-details-timeframe', context).val() == '' 
						|| $.isNumeric( $('#cluster-details-timeframe', context).val() ) == false
					) {
						alert("Please specify a numeric value for cluster timeframe.");
					} else {

						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'cluster',
							action: 'saveNewCluster',
							queryString: $('#form-cluster[data-id="NEW"]').serializeWithSpaces(),
							success: saveClusterCallback
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
		
	}
}

function openDialogClusterDetailsCallback ( params ) {
	var context = $('#form-cluster[data-id="' + params.id + '"]');
	
	if ( params.writeRight == 1 ) { 
	
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Save',
				click: function () {

					if ( 
						$('#cluster-details-threshold', context).val() == '' 
						|| $.isNumeric( $('#cluster-details-threshold', context).val() ) == false 
					) {
						alert("Please specify a numeric value for cluster threshold.");
					} else if ( 
						$('#cluster-details-timeframe', context).val() == '' 
						|| $.isNumeric( $('#cluster-details-timeframe', context).val() ) == false 
					) {
						alert("Please specify a numeric value for cluster timeframe.");
					} else {
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'cluster',
							action: 'saveClusterDetails',
							queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
							success: saveClusterCallback
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
		
	} else {
		$('input, select, textarea', context).each( function (index) {
			$(this).prop('disabled', true);
		});
	}
}

function saveClusterCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'cluster',
			action: 'getClusterItemHtml',
			queryString: queryString,
			success: getConfigurationItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}
