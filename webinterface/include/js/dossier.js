/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// button 'Create a new dossier'
	$('#filters').on('click', '.btn-dossier-new', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier',
			action: 'openDialogNewDossier',
			success: function (params) {

				if ( params.writeRight == 1 ) { 
					var context = $('#form-dossier[data-id="NEW"]');
					
					dialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								var reOnlyNumbers = /^\d+$/;
								
								if ( $('#dossier-details-description', context).val() == '' ) {
									alert("Please specify a dossier description.");
								} else if ( $('#dossier-details-tags', context).val().replace(/(,|\s)/, '') == '' ) {
									alert("At least one tag is needed.");
								} else if ( $('.dossier-details-contributors-item', context).length == 0 ) {
									alert("At least one contributor has to be added.");
								} else if ( reOnlyNumbers.test( $('#dossier-reminder-time-amount').val() ) == false ) {
									alert("Please specify a valid number of days or months.");
								} else {
									var contributorsList = new Array();

									$('.dossier-details-contributors-item', context).each( function (i) {
										var contributor = new Object(),
											isOwner = ( $('.dossier-details-contributors-item[data-username="' + $(this).attr('data-username') + '"] .cell:first input').is(':checked') ) ? 1 : 0;
										contributor.username = $(this).attr('data-username');
										contributor.is_owner = isOwner;
										
										contributorsList.push(contributor);
									});

									$.main.ajaxRequest({
										modName: 'dossier',
										pageName: 'dossier',
										action: 'saveNewDossier',
										queryString: $('#form-dossier[data-id="NEW"]').serializeWithSpaces() + '&contributors=' + encodeURIComponent( JSON.stringify( contributorsList ) ),
										success: saveDossierCallback
									});
								}
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);

					$('#dossier-details-tags', context).newAutocomplete();

					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Create new dossier');
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
	
	// edit/view dossier settings
	$('#content').on( 'click', '.btn-edit-dossier, .btn-view-dossier', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		var dossierID = $(this).attr('data-id');
		
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier',
			action: 'openDialogDossierDetails',
			queryString: 'id=' + dossierID,
			success: function (params) {
				var context = $('#form-dossier[data-id="' + dossierID + '"]');

				if ( params.writeRight == 1 ) {
					
					dialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								var reOnlyNumbers = /^\d+$/;
								
								if ( $('#dossier-details-description', context).val() == '' ) {
									alert("Please specify a dossier description.");
								} else if ( $('#dossier-details-tags', context).val().replace(/(,|\s)/, '') == '' ) {
									alert("At least one tag is needed.");
								} else if ( $('.dossier-details-contributors-item', context).length == 0 ) {
									alert("At least one contributor has to be added.");
								} else if ( reOnlyNumbers.test( $('#dossier-reminder-time-amount').val() ) == false ) {
									alert("Please specify a valid number of days or months.");
								} else {
									var contributorsList = new Array();

									$('.dossier-details-contributors-item', context).each( function (i) {
										var contributor = new Object(),
											isOwner = ( $('.dossier-details-contributors-item[data-username="' + $(this).attr('data-username') + '"] .cell:first input').is(':checked') ) ? 1 : 0;
										contributor.username = $(this).attr('data-username');
										contributor.is_owner = isOwner;
										
										contributorsList.push(contributor);
									});

									$.main.ajaxRequest({
										modName: 'dossier',
										pageName: 'dossier',
										action: 'saveDossierDetails',
										queryString: $('#form-dossier[data-id="' + dossierID + '"]').serializeWithSpaces() + '&contributors=' + encodeURIComponent( JSON.stringify( contributorsList ) ) + '&id=' + dossierID,
										success: saveDossierCallback
									});
								}
							}
						},
						{
							text: 'Cancel',
							click: function () { $(this).dialog('close') }
						}
					]);

					$('#dossier-details-tags', context).newAutocomplete();

					$('input[type="text"]', context).keypress( function (event) {
						return checkEnter(event);
					});

				} else {
					$('input, select, textarea', context).each( function (index) {
						$(this).prop('disabled', true);
					});
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Dossier details');
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
	
	// join two or more dossiers into one new dossier
	$('#filters').on('click', '#btn-dossier-join', function () {

		if ( $('.dossier-item-select-input:checked').length < 2 ) {
		    alert ("You need to check at least 2 dossiers!");
		} else {

			var queryString = '';
			$('.dossier-item-select-input:checked').each( function (i) {
				queryString += '&ids=' + $(this).val();
			});	
		
			var dialog = $('<div>').newDialog();
			dialog.html('<fieldset>loading...</fieldset>');
		
			$.main.ajaxRequest({
				modName: 'dossier',
				pageName: 'dossier',
				action: 'openDialogJoinDossiers',
				queryString: queryString,
				success: function (params) {
	
					if ( params.writeRight == 1 ) {
						$('#dossier-join-tags').newAutocomplete();
						
						dialog.dialog('option', 'buttons', [
							{
								text: 'Save',
								click: function () {
									var reOnlyNumbers = /^\d+$/;
									
									if ( $('#dossier-join-tags').val().replace(/(,|\s)/, '') == '' ) {
										alert("At least one tag is needed.");
									} else if ( $('.dossier-details-contributors-item').length == 0 ) {
										alert("At least one contributor has to be added.");
									} else if ( reOnlyNumbers.test( $('#dossier-reminder-time-amount').val() ) == false ) {
										alert("Please specify a valid number of days or months.");
									} else {
										var contributorsList = new Array();
	
										$('.dossier-details-contributors-item').each( function (i) {
											var contributor = new Object(),
												isOwner = ( $('.dossier-details-contributors-item[data-username="' + $(this).attr('data-username') + '"] .cell:first input').is(':checked') ) ? 1 : 0;
											contributor.username = $(this).attr('data-username');
											contributor.is_owner = isOwner;
											
											contributorsList.push(contributor);
										});
	
										var ids = ''
										$('.dossier-item-select-input:checked').each( function (i) {
											ids += '&ids=' + $(this).val();
										});	
										
										$.main.ajaxRequest({
											modName: 'dossier',
											pageName: 'dossier',
											action: 'joinDossiers',
											queryString: $('#form-dossier-join').serializeWithSpaces() + '&contributors=' + encodeURIComponent( JSON.stringify( contributorsList ) ) + ids,
											success: function ( joinDossiersParams ) {
												if ( joinDossiersParams.saveOk == 1 ) {
													$('#dossier-menu').trigger('click');
													$.main.activeDialog.dialog('close');
												} else {
													alert( joinDossiersParams.message );
												}
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
				}
			});
			
			dialog.dialog('option', 'title', 'Join dossier');
			dialog.dialog('option', 'width', '700px');
			dialog.dialog({
				buttons: {
					'Close': function () {
						$(this).dialog( 'close' );
					}
				}
			});
	
			dialog.dialog('open');
		}
	});
	
	// add contributor to contributor list
	$(document).on('click', '#btn-dossier-add-contributor', function () {
		if ( $('#dossier-details-contributor-username').val() != undefined ) {
			var contributorText = $('#dossier-details-contributor-username option:selected').html(),
				removeContributorButton = '<input type="button" class="button btn-dossier-remove-contributor" value="remove" data-username="' + $('#dossier-details-contributor-username').val() + '">',
				nextItemNumber = 1;
			
			if ( $('input[id^="dossier-details-contributor-is-owner-"]:last').length > 0 ) {
				nextItemNumber = parseInt( $('input[id^="dossier-details-contributor-is-owner-"]:last').attr('id').replace( /dossier-details-contributor-is-owner-(\d+)/, "$1" ) ) + 1;
			}

			contributorText += '<br><input type="checkbox" class="align-middle" id="dossier-details-contributor-is-owner-' + nextItemNumber + '" checked> <label for="dossier-details-contributor-is-owner-' + nextItemNumber + '"> is dossier owner</label>'
			
			$('<li>')
				.addClass('dossier-details-contributors-item')
				.attr( 'data-username', $('#dossier-details-contributor-username').val() )
				.html( '<span class="cell">' + contributorText + '</span>' + '<span class="cell block">' + removeContributorButton + '</span>' )
				.appendTo('#dossier-details-contributors-list');
			
			$('#dossier-details-contributor-username option:selected').remove();
			$('#dossier-details-contributor-is-owner').prop('checked', true);
		}
	});	
	
	// remove contributor from contributor list
	$(document).on('click', '.btn-dossier-remove-contributor', function () {
		var removeUsername = $(this).attr('data-username');
		$('<option>')
			.val( removeUsername )
			.html( $('.dossier-details-contributors-item[data-username="' + removeUsername + '"] span:first').html().replace(/(.*?)<br>.*/, "$1"))
			.appendTo('#dossier-details-contributor-username');
		$('.dossier-details-contributors-item[data-username="' + removeUsername + '"]').remove()
	});
	
	// view publication contents of advisories, end-of-week, etc.
	$('#content').on('click', '.publications-dossier-link', function () {
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier',
			action: 'openDialogDossierPublicationDetails',
			queryString: 'publicationid=' + $(this).attr('data-publicationid') + '&pubtype=' + $(this).attr('data-pubtype'),
			success: function (params) {}
		});
		
		dialog.dialog('option', 'title', 'Publication details');
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
	
	// open dossier timeline
	$('#content').on('click', '.dossier-item-link', function () {
		var dossierID = $(this).attr('data-dossierid');
		
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier_timeline',
			action: 'displayDossierTimeline',
			queryString: 'id=' + dossierID,
			success: null
		});
		
	});
	
	$(document).on('click', '.dossier-constituent-individual-link', function () {
		var individualID = $(this).attr('data-individualid');
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_individuals',
			action: 'openDialogConstituentIndividualSummary',
			queryString: 'id=' + individualID,
			success: null
		});
		
		dialog.dialog('option', 'title', 'Constituent individual summary');
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

	$(document).on('click', '.dossier-constituent-group-link', function () {
		var groupID = $(this).attr('data-groupid');
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'constituent_group',
			action: 'openDialogConstituentGroupSummary',
			queryString: 'id=' + groupID,
			success: null
		});
		
		dialog.dialog('option', 'title', 'Constituent group summary');
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
});

function saveDossierCallback ( params ) {
	if ( params.saveOk == 1 ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'dossier',
			pageName: 'dossier',
			action: 'getDossierItemHtml',
			queryString: queryString,
			success: function (itemHtmlParams) {
				if ( itemHtmlParams.insertNew == 1 ) {
					$('#empty-row').remove();
					$('.content-heading').after( itemHtmlParams.itemHtml );
				} else {
					$('#' + itemHtmlParams.id).html( itemHtmlParams.itemHtml );
				}				
			}
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}	
}

