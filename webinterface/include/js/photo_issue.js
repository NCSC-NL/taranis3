/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {
	
	// edit/view photo issue details
	$(document).on( 'click', '.btn-edit-issue, .btn-view-issue-details, #link-followup-on-issue, .photo-issue-link', function () {
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'openDialogPhotoIssueDetails',
			queryString: 'id=' + $(this).attr('data-id'),				
			success: openDialogPhotoIssueDetailsCallback
		});
		
		dialog.dialog('option', 'title', 'Photo issue details');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog('close');
				}
			}
		});

		dialog.dialog('open');		
	});
});


function openDialogPhotoIssueDetailsCallback ( params ) {

	var context = $('#photo-issues-details-tabs[data-id="' + params.id + '"]');
	
	$(context).newTabs();
	// create dialog buttons
	var resolveButton = { 
				text: 'Resolve issue',
				click: function () {

					var issueType = ( $('input[name="duplicate_option"]', context).length > 0 ) ? 2 : 3;
					
					if ( issueType == 2 && $('input[name="duplicate_option"]:checked', context).length == 0 ) {
						alert('Please choose one of the duplicates to use');
					} else if ( issueType == 3 && $('#photo-issues-selected-software-hardware', context).text() == '' ) {
						alert('No software or hardware selected.');
					} else {

						var softHardId = ( issueType == 2 ) ? $('input[name="duplicate_option"]:checked', context).val() : $('#photo-issues-selected-software-hardware-id', context).val();

						var createNewIssue = (
								( issueType == 2 && $('#createIssue_' + $('input[name="duplicate_option"]:checked', context).val(), context ).is(':checked') )
								|| ( issueType == 3 && $('#photo-issues-create-issue', context).is(':checked:visible') )
							) 
							? '1'
							: '0';
						
						var otherIds = new Array();

						$('input[name="duplicate_option"]:not(:checked)', context).each( function () {
							otherIds.push( $(this).val() );
						});

						var queryString = 'soft_hard_id=' + softHardId 
										+ '&issueNr=' + params.id 
										+ '&create_new_issue=' + createNewIssue 
										+ '&type=' + issueType
										+ '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() )
										+ '&other_sh_ids=' + encodeURIComponent( JSON.stringify( otherIds ) );
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'photo_management',
							action: 'resolveIssue',
							queryString: queryString,				
							success: issueActionCallback
						});						
					}
				}
			},
		readyForReviewButton = { 
				text: 'Ready for review',
				click: function () {

					if ( $('#photo-issues-details-comments', context).val() == "" ) {
						alert('No solution given.');
					} else {
						
						$.main.ajaxRequest({
							modName: 'configuration',
							pageName: 'photo_management',
							action: 'issueReadyForReview',
							queryString: 'issueNr=' + params.id + '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() ),				
							success: issueActionCallback
						});
					}
				}
			}, 
		acceptButton = { 
				text: 'Accept & resolve',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'acceptIssue',
						queryString: 'issueNr=' + params.id + '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() ),				
						success: issueActionCallback
					});
				}
			},
		rejectButton = { 
				text: 'Reject',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'rejectIssue',
						queryString: 'issueNr=' + params.id + '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() ),				
						success: issueActionCallback
					});					
				}
			}, 
		closeIssueButton = { 
				text: 'Resolve issue',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'closeIssue',
						queryString: 'issueNr=' + params.id + '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() ),				
						success: issueActionCallback
					});
				}
			}, 
		saveButton = { 
				text: 'Save',
				click: function () {
					var softHardId = '';
					var createNewIssue = '0';
					
					if ( $('input[name="duplicate_option"]', context).length > 0 ) {
						softHardId = $('input[name="duplicate_option"]:checked', context).val();
						createNewIssue = ( $('#createIssue_' + $('input[name="duplicate_option"]:checked', context).val(), context ).is(':checked') ) ? '1' : '0'; 
						
					} else if ( $('#photo-issues-selected-software-hardware', context).text() != '' ) {
						softHardId = $('#photo-issues-selected-software-hardware-id', context).val();
						createNewIssue = ( $('#photo-issues-create-issue', context).is(':checked:visible') ) ? '1' : '0';
					} 
					
					var queryString = 'soft_hard_id=' + softHardId
									+ '&issueNr=' + params.id
									+ '&comments=' + encodeURIComponent( $('#photo-issues-details-comments', context).val() )
									+ '&create_new_issue=' + createNewIssue;
					
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'saveIssue',
						queryString: queryString,				
						success: savePhotoIssueCallback
					});
				}
			},
		deleteIssueButton = {
				text: 'Delete issue',
				click: function () {
					$.main.ajaxRequest({
						modName: 'configuration',
						pageName: 'photo_management',
						action: 'deleteIssue',
						queryString: 'issueNr=' + params.id,
						success: deleteIssueCallback
					});
				}
			}, 			
		cancelButton = {
				text: 'Cancel',
				click: function () {
					$.main.activeDialog.dialog('close');
				}
			}, 
		closeButton = {
				text: 'Close',
				click: function () {
					$.main.activeDialog.dialog('close');
				}
			};

	// create a list of the buttons depending on issue type and issue status
	var buttons = new Array();
	if ( ( params.issuetype == 2 || params.issuetype == 3 ) && params.status == 0 && params.executeRight ) {
		if ( !params.isFollowupIssue ) {
			buttons.push( deleteIssueButton );
		}
		buttons.push( resolveButton );
	} else if ( params.issuetype == 1 && params.status == 0 ) {
		if ( !params.isFollowupIssue ) {
			buttons.push( deleteIssueButton );
		}
		buttons.push( readyForReviewButton );
	} else if ( params.status == 1 && params.executeRight ) {
		buttons.push( acceptButton );
		buttons.push( rejectButton );
	} else if ( 
			( 
					( params.issuetype != 2 && params.issuetype != 3 ) 
				|| ( 
							( params.issuetype == 4 || params.issuetype == 5 ) 
							&& params.status == 0 
					)
			) && params.executeRight
			&& params.status != 3
	) {
		buttons.push( closeIssueButton );
	}
	
	if ( params.status != 3 ) {
		buttons.push( saveButton );
		buttons.push( cancelButton );
	} else {
		buttons.push( closeButton );
	}
	
	// add buttons to dialog
	$.main.activeDialog.dialog('option', 'buttons', buttons);
	
	// search software/hardware
	$('#btn-photo-issues-search-software-hardware', context).click( function () {
		if ( $('#photo-issues-search-software-hardware', context).val().length > 1 ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'searchSoftwareHardwarePhotoManagement',
				queryString: 'search=' + encodeURIComponent( $('#photo-issues-search-software-hardware',context).val() ) + '&id=' + params.id,				
				success: searchSoftwareHardwarePhotoIssueCallback
			});
		} else {
			alert('Minimum of two characters required for search.');
		}
	});

	// search software/hardwar on ENTER
	$('#photo-issues-search-software-hardware', context).keypress( function (event) {
		if ( !checkEnter(event) ) {
			event.preventDefault();
			$('#btn-photo-issues-search-software-hardware', context).trigger('click');
		}
	});
	
	// select software/hardware
	$('#btn-photo-issues-no-match-found-select', context).click( function () {
		if ( $('#photo-issues-software-hardware-list option:selected', context).length > 0 ) {

			$('#photo-issues-selected-software-hardware', context).text( $('#photo-issues-software-hardware-list option:selected', context).text() );
			$('#photo-issues-selected-software-hardware-id', context).val( $('#photo-issues-software-hardware-list', context).val() );
			
			if ( !$('#photo-issues-software-hardware-list option:selected', context).hasClass( 'option-sh-in-use' ) ) {
				$('#photo-issues-create-issue-block', context)
					.show()
					.removeClass('hidden');
				$('#photo-issues-create-issue', context).prop('checked', true);
			} else {
				$('#photo-issues-create-issue-block', context).hide();
			}
		}		
	});

	// reset software/hardware selection
	$('#btn-photo-issues-reset-selection', context).click( function () {
		$('#photo-issues-selected-software-hardware', context).text('');
		$('#photo-issues-selected-software-hardware-id', context).val('');
		$('#photo-issues-create-issue-block', context).hide();
	});

	// view constituent list
	$('.link-view-photo-issues-constituent-list', context).click( function () {
		var dialog = $('<div>').newDialog(),
			constituentList = $(this).siblings('.photo-issues-constituent-list').clone();
		
		dialog.html('<fieldset class="align-text-left"><span class="dialog-input-label">Constituent list for duplicate option ' + $(this).attr('data-duplicateoption') + '</span><ul>' + constituentList.html() + '</ul></fieldset>');
		
		dialog.dialog('option', 'title', 'Constituent list');
		dialog.dialog('option', 'width', '400px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog('close');
				}
			}
		});

		dialog.dialog('open');			
	});
	
	// changing duplicate selection
	$('input[name="duplicate_option"]', context).change( function () {
		var duplicateUsageCount = 0;
		$('input[name="duplicate_option"]:not(:checked)', context).each( function () {
			var sh_id = $(this).val();
			var usageCount = parseInt( $('#duplicateUsageCount_' + sh_id, context).text() );
			
			if ( usageCount == 0 ) {
				$('#createIssue_' + sh_id, context).prop('disabled', true);
			}
			duplicateUsageCount += usageCount;	
		});
		
		if ( $('input[name="duplicate_option"]:checked', context).length > 0 ) {
			var selectedShId = $('input[name="duplicate_option"]:checked', context).val();
		
			if ( parseInt( $('#duplicateUsageCount_' + selectedShId, context).text() ) == 0 ) {
				$('#createIssue_' + selectedShId, context).prop('disabled', false);
			}
		}
		
		if ( duplicateUsageCount > 0 ) {
			$('#photo-issues-duplicate-warning-block', context).text( 'When resolving this issue, the selected software/hardware will be set for all constituents which have one of the duplicates in use.' );
			$('#photo-issues-duplicate-warning-text', context)
				.show()
				.removeClass('hidden');
		} else {
			$('#photo-issues-duplicate-warning-block', context).text( '' );
			$('#photo-issues-duplicate-warning-text', context).hide();
		}		
	});
	
	if ( $('input[name="duplicate_option"]', context).length > 0 ) {
		$('input[name="duplicate_option"]', context).triggerHandler('change');
	}	

	$('#photo-issues-search-software-hardware', context).keypress( function (event) {
		$(this).removeClass('not-found');
	});
	
	$('input[type="text"]', context).keypress( function (event) {
		return checkEnter(event);
	});
}

function savePhotoIssueCallback ( params ) {
	if ( params.saveOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'getIssueItemHtml',
			queryString: queryString,
			success: getIssueItemHtmlCallback
		});
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function issueActionCallback ( params ) {
	if ( params.actionOk ) {

		var queryString = 'id=' + params.id;
		
		if ( params.insertNew == 1 ) {
			queryString += '&insertNew=1';
		}		
		
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'getIssueItemHtml',
			queryString: queryString,
			success: getIssueItemHtmlCallback
		});

		if ( params.newIssueNr ) {
			$.main.ajaxRequest({
				modName: 'configuration',
				pageName: 'photo_management',
				action: 'getIssueItemHtml',
				queryString: 'id=' + params.newIssueNr + '&insertNew=1',
				success: getIssueItemHtmlCallback
			});
		}		
		
		$.main.activeDialog.dialog('close');
		
	} else {
		alert(params.message)
	}
}

function searchSoftwareHardwarePhotoIssueCallback ( params ) {
	var context = $('#photo-issues-details-tabs[data-id="' + params.id + '"]');
	
	$('#photo-issues-software-hardware-list option', context).remove();
	
	if ( params.data.length > 0 ) {
	
		$.each( params.data, function(i) {

			var optionText = params.data[i].producer.substr(0,1).toUpperCase() 
							+ params.data[i].producer.substr(1) + " "
							+ params.data[i].name + " " 
							+ params.data[i].version + " (" 
							+ params.data[i].description + ")";

			var textColor = 'inherit';
			if ( params.data[i].cpe_id == '' || !params.data[i].cpe_id ) {									
				textColor = '#F20909';
			} 
			
			var optionClass = '';
			if ( params.data[i].in_use > 0 ) {									
				optionClass = 'option-sh-in-use';
			} 
			
			$('<option />')
				.html( optionText )
				.attr('title', optionText )
				.val( params.data[i].id )
				.addClass( optionClass )
				.css({ 'color' : textColor })
				.dblclick( function () {
					$('#btn-photo-issues-no-match-found-select', context).trigger('click');
				})
				.appendTo('#photo-issues-software-hardware-list', context);
		});
		 
	} else {
		$('#photo-issues-search-software-hardware', context).addClass('not-found');
	}
}

function getIssueItemHtmlCallback ( params ) {
	if ( params.insertNew == 1 ) {
		$('#empty-row').remove();
		$('.content-heading').after( params.itemHtml );
	} else {
		$('#' + params.id)
			.html( params.itemHtml )
			.removeClass( 'photo-issues-pending photo-issues-readyforreview photo-issues-done' )
			.addClass( 'photo-issues-' + params.issueStatus );
	}
}

function deleteIssueCallback ( params ) {
	if ( params.deleteOk ) {
		$.main.ajaxRequest({
			modName: 'configuration',
			pageName: 'photo_management',
			action: 'displayPhotoIssues',
			queryString: 'no_filters=1',
			success: null
		});

		$.main.activeDialog.dialog('close');
		
	} else {
		alert( params.message );
	}
}
