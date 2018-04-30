/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view special interest details
	$('#content').on( 'click', '.btn-edit-report-special-interest, .btn-view-report-special-interest', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'special_interest',
			action: 'openDialogSpecialInterestDetails',
			queryString: 'id=' + $(this).attr('data-id'),
			success: function ( params ) {
				var context = $('#form-report-special-interest[data-id="' + params.id + '"]');

				$('#report-special-interest-date-start', context).change( function () {
					$('#report-special-interest-date-end', context).val( addTwoWeeksToDate( $('#report-special-interest-date-start', context).val() ) );
				});
				
				if ( params.writeRight == 1 ) {
				
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
								if ( $.trim( $('#report-special-interest-topic', context).val() ) == '' ) {
									alert("Please specify a topic.");
								} else if ( $('#report-special-interest-requestor', context).val() == '' || !$.main.reEmailAddress.test( $('#report-special-interest-requestor', context).val() ) ) {
									alert("Please specify a valid requestor emailaddress.");
								} else if ( validateForm(['report-special-interest-date-start', 'report-special-interest-date-end']) ) {
									if ( isLessThanFourWeeks( $('#report-special-interest-date-start').val(), $('#report-special-interest-date-end').val() ) ) {
										$.main.ajaxRequest({
											modName: 'report',
											pageName: 'special_interest',
											action: 'saveSpecialInterestDetails',
											queryString: $(context).serializeWithSpaces() + '&id=' + params.id,
											success: saveSpecialInterestCallback
										});
									} else {
										alert("Start and end date may be 4 weeks apart maximum.");
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
		});
		
		dialog.dialog('option', 'title', 'Special interest details');
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
	
	// delete a special-interest
	$('#content').on( 'click', '.btn-delete-report-special-interest', function () {
		if ( confirm('Are you sure you want to delete the special interest?') ) { 
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'special_interest',
				action: 'deleteSpecialInterest',
				queryString: 'id=' + $(this).attr('data-id'),
				success: deleteReportItemCallback
			});
		}
	});
	
	// add a new special-interest
	$(document).on( 'click', '#btn-add-report-special-interest, #add-report-special-interest-link', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
	
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'special_interest',
			action: 'openDialogNewSpecialInterest',
			success: function ( params ) {
				if ( params.writeRight == 1 ) { 
					var context = $('#form-report-special-interest[data-id="NEW"]');
					
					$('#report-special-interest-date-start', context).change( function () {
						$('#report-special-interest-date-end', context).val( addTwoWeeksToDate( $('#report-special-interest-date-start', context).val() ) );
					});
					
					$.main.activeDialog.dialog('option', 'buttons', [
						{
							text: 'Save',
							click: function () {
			
								if ( $.trim( $('#report-special-interest-topic', context).val() ) == '' ) {
									alert("Please specify a topic.");
								} else if ( $('#report-special-interest-requestor', context).val() == '' || !$.main.reEmailAddress.test( $('#report-special-interest-requestor', context).val() ) ) {
									alert("Please specify a valid requestor emailaddress.");
								} else if (	validateForm(['report-special-interest-date-start', 'report-special-interest-date-end']) ) {
									if ( isLessThanFourWeeks( $('#report-special-interest-date-start').val(), $('#report-special-interest-date-end').val() ) ) {
										$.main.ajaxRequest({
											modName: 'report',
											pageName: 'special_interest',
											action: 'saveNewSpecialInterest',
											queryString: $('#form-report-special-interest[data-id="NEW"]').serializeWithSpaces(),
											success: saveSpecialInterestCallback
										});
									} else {
										alert("Start and end date may be 4 weeks apart maximum.");
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
				}
			}
		});
		
		dialog.dialog('option', 'title', 'Add new special interest');
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

	// search special interests
	$('#filters').on('click', '#btn-report-special-interest-search', function () {
		$.main.ajaxRequest({
			modName: 'report',
			pageName: 'special_interest',
			action: 'searchSpecialInterest',
			queryString: $('#form-report-special-interest-search').serializeWithSpaces(),
			success: null
		});
	});
	
	// do special interest search on ENTER
	$('#filters').on('keypress', '#report-special-interest-filters-search', function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-report-special-interest-search').trigger('click');
		}
	});
});

function saveSpecialInterestCallback ( params ) {
	if ( params.saveOk ) {
		if ( $('#report-special-interest-content-heading').length > 0 ) {
			var queryString = 'id=' + params.id;
			
			if ( params.insertNew == 1 ) {
				queryString += '&insertNew=1';
			}		
			
			$.main.ajaxRequest({
				modName: 'report',
				pageName: 'special_interest',
				action: 'getSpecialInterestItemHtml',
				queryString: queryString,
				success: getReportItemHtmlCallback
			});
			
			$.main.activeDialog.dialog('close');
		} else {
			$.main.activeDialog.dialog('close');

			var e = jQuery.Event("keydown");
			e.which = 116;
			$(document).trigger(e);
		}
	} else {
		alert(params.message)
	}
}

function addTwoWeeksToDate (stDate) {
	var arDate = stDate.split('-');
	var dtDate = new Date(arDate[2],arDate[1]-1, arDate[0]);
	dtDate.setDate( dtDate.getDate() + 14 );
	return dtDate.getDate() + '-' + ( dtDate.getMonth() + 1) + '-' + dtDate.getFullYear();
}

function isLessThanFourWeeks (stStartDate, stEndDate) {
	var dtStartDate = new Date(stStartDate.split('-')[2],stStartDate.split('-')[1]-1, stStartDate.split('-')[0]);
	var dtEndDate = new Date(stEndDate.split('-')[2],stEndDate.split('-')[1]-1, stEndDate.split('-')[0]);
	var dtStartDateCopy = new Date(dtStartDate.getTime());
	dtStartDateCopy.setDate( dtStartDate.getDate() + 28 );
	return ( ( dtStartDateCopy.getTime() >= dtEndDate.getTime() ) && ( dtStartDate.getTime() < dtEndDate.getTime() ) );
}
