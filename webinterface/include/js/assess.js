/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function() {
	
	// Add to Publication action
	$('#content').on('click', '.addToPublicationOption', function () { 
		var itemClicked = $(this);
		
		var queryString = 'publicationTypeId=' + itemClicked.attr('data-publicationId') 
			+ '&digest=' + itemClicked.attr('data-digest') 
			+ '&publicationSpecifics=' + itemClicked.attr('data-specifics');
		
		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess',
			action: 'addToPublication',
			queryString: queryString,
			success: addToPublicationCallback
		}, true);
	});

	// Clipboard icon; reformat item text into a nice clipboard entry, pastable in an other
	// application, like OneNote
	// https://github.com/lgarron/clipboard-polyfill

	$('#content').on('click', '.clipboard', function () {
		$('.clipboard').removeClass('in-clipboard');  // unselect any
		var $item = $(this).parents('.assess-item');

		var dt    = new clipboard.DT();
		var title = $item.find('.assess-item-title span').text();
		var descr = $item.find('.assess-item-description').text();
		var link  = $item.find('.assess-item-title a').attr('href');

		dt.setData('text/plain', title + "\n" + descr + "\n" + link + "\n");
		dt.setData('text/html', "<h1>" + title + "</h1>\n<p>" + descr + "</p><br>\n"
			+ "<a href='" + link + "'>" + link + "</a><br>\n");

		clipboard.write(dt);
		$(this).addClass('in-clipboard');
	});

	// email icon; opens dialog for sending mail.
	$('#content').on('click', '.img-assess-item-mail', function () {
		
		var itemDigest = $(this).attr('data-digest');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'mail',
			action: 'displayMailAction',
			queryString: 'digest=' + itemDigest,
			success: mailItemOpenDialogCallback
		});			
		
		dialog.dialog('option', 'title', 'Email item');
		dialog.dialog('option', 'width', '730px');
		dialog.dialog({
			buttons: {
				'Send mail': function () {

					if ( $('#assess-mail-to option:selected').length == 0 ) {
						alert('Please select one or more email addresses.');
					} else if ( $('#subject').val() == '' ) {
						alert('Please fill out a subject.');
					} else if ( $('#description').val() == '' ) {
						alert('Please fill out a text to send.');					
					} else {
						$.main.ajaxRequest({
							modName: 'assess',
							pageName: 'mail',
							action: 'mailItem',
							queryString: $('#form-assess-mail-item').serializeWithSpaces(),
							success: mailItemCallback
						});							
					}
				},
				'Cancel': function () {
					$(this).dialog( 'close' );
				}
			}
		});

		dialog.dialog('open');
		
		$('.item-arrow:visible').hide();
		$('#' + itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();
		
		// Continue with mailItemOpenDialogCallback() after AJAX request is done.
	});
	
	// show / hide clustered items
	$('#content').on( 'click', '.item-clustering-toggle-items', function () {

		var clusterId = $(this).attr('data-clusterid');
		if ( $('.item-cluster-row[data-clusterid="' + clusterId + '"]:visible').length > 0 ) {
			
			if ( $('.item-cluster-row[data-clusterid="' + clusterId + '"] .item-arrow').is(':visible') ) {
				$('.item-arrow:visible').hide();
				$('.item-top-cluster-row[data-clusterid="' + clusterId + '"] .item-arrow').show();
			}
			
			$('.item-cluster-row[data-clusterid="' + clusterId + '"]').hide();
		} else {
			$('.item-cluster-row[data-clusterid="' + clusterId + '"]').show();
		}
	});
	
	// unlink assess item from cluster (by setting the cluster_enabled to false)
	$('#content').on( 'click', '.btn-unlink-from-cluster', function () {
		if ( confirm('Are you sure you want unlink item from cluster?') ) {
			
			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess',
				action: 'disableClustering',
				queryString: 'id=' + $(this).attr('data-digest') + '&clusterId=' + $(this).attr('data-clusterid') + '&seedDigest=' + $(this).attr('data-seeddigest'),
				success: disableClusteringCallback
			});
		}
	});
	
	$('#content').on( 'click', '#btn-show-more-items', function () {
		stopAssessTimer();

		var lastInBatch = $('.assess-item:last').attr('id') ;
		
		var firstInBatch = $('.assess-item:first').attr('id');
		if ( $('div[id="' + firstInBatch + '"]').hasClass('item-top-cluster-row') == true ) {
			var clusterId = $('div[id="' + firstInBatch + '"]').attr('data-clusterid');
			firstInBatch = $('.item-cluster-row[data-clusterid="' + clusterId + '"]:first').attr('id');
		}

		var queryString = ( $('#btn-assess-search').is(':visible') )
			? $('#form-assess-standard-search').serializeWithSpaces()
			: $('#form-assess-custom-search').serializeWithSpaces() + '&isCustomSearch=1';
		
		var action = ( $('#btn-assess-search').is(':visible') )
			? 'search'
			: 'customSearch';
			
		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess',
			action: action,
			queryString: queryString + '&lastInBatch=' + lastInBatch + '&firstInBatch=' + firstInBatch,
			success: function (params) {
				$('.assess-item:last').after(params.newItemsHtml);
				if ( $('.assess-item').length == parseInt( $('#assess-result-count').text() ) ) {
					$('#btn-show-more-items').hide();
				}

				var counter_text = $('#content #assess-count').text();
				$('#filters #assess-count').text(counter_text);
				startAssessTimer();
			}
		});
	});
	
	// set arrow selection to clicked item
	$('#content').on('mouseup', '.assess-item-select-input', function () {
		$('.item-arrow:visible').hide();
		$(this).parentsUntil('.assess-item').siblings('.item-arrow').show();
	});
	
});

function mailItemOpenDialogCallback ( params ) {
	
	$('#assess-mail-to').focus();
	
	var re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
	$('#btn-assess-mail-add-address').click( function () {
		var emailAddress = $('#assess-mail-extra-address').val(); 
		if ( emailAddress != '' && re.test( emailAddress ) ) {
			$('<option>')
				.val( emailAddress )
				.text( emailAddress )
				.appendTo('#assess-mail-to')
				.prop('selected', true);
			$('#assess-mail-extra-address').val('')
		} else {
			alert ("Please enter a valid e-mail address!");	
		}
	});
}

function mailItemCallback ( params ) {
	if ( params.isMailed == 0 ) { 
		// replace all buttons with a Close button
		$.main.activeDialog.dialog('option', 'buttons', [
			{
				text: 'Close',
				click: function () { $(this).dialog('close') }
			}
		]);
	} else {
		$.main.activeDialog.dialog('close');
		if ( typeof window['oneUp'] === 'function' ) {
			window['oneUp']();
		}
	}
}


function addToPublicationCallback ( params ) {

	if ( params.isAddedToPublication == 1 ) {
		var itemClicked = $('li[data-digest="' + params.itemDigest + '"][data-publicationId="' + params.publicationTypeId + '"][data-specifics="' + params.publicationSpecifics + '"]');
		if ( params.action == 'addToPublication' ) {
			itemClicked.addClass('isAddedToPublication');
		} else {
			itemClicked.removeClass('isAddedToPublication');
		}
	} else {
		alert( params.message );
	}
}

function refreshAssessPageCallback ( params ) {
	
	if ( params.newItemsCount > 0 ) {
		if ( $('#assess-new-items-message').length > 0 ) {
			$('#assess-new-items-message-number').text( params.newItemsCount );
		} else {
			$('<div>')
				.attr('id', 'assess-new-items-message')
				.addClass('center pointer')
				.html('<span id="assess-new-items-message-text"><span class="bold" id="assess-new-items-message-number">' + params.newItemsCount + '</span><span> new items collected</span></span><span id="assess-new-items-message-refresh">Reload</span>')
				.mouseover( function () {
					$('#assess-new-items-message-text').hide();
					$('#assess-new-items-message-refresh').show();
				})
				.mouseout( function () {
					$('#assess-new-items-message-text').show();
					$('#assess-new-items-message-refresh').hide();
				})
				.click( function () {
					if ( $('#btn-assess-search').is(':visible') ) {
						$('#btn-assess-search').trigger('click', 'autoRefresh');
					} else {
						$('#btn-custom-search').trigger('click', 'autoRefresh');
					}
				})
				.prependTo('.assess-items');
		}
	}
	
	if ( params.id ) {
		$('#' + params.id.replace(/%/g, '\\%') + ' .item-arrow').show();
		var currentItemPosition = $('#' + params.id.replace(/%/g, '\\%') ).position();

		if ( $('.ui-dialog:visible').length == 0 && currentItemPosition ) {
			$(document).scrollTop( currentItemPosition.top );
		}
	}

}

function disableClusteringCallback ( params ) {

	if ( params.message ) {
		alert( params.message );
	} else {
		$('div[id="' + params.itemDigest + '"]').remove()

		var numberOfClusterItemsElement = $('.item-clustering-toggle-items[data-clusterid="' + params.clusterId + '"] span');
		var numberOfClusterItems = parseInt( numberOfClusterItemsElement.text() );
		if ( numberOfClusterItems > 2 ) {
			numberOfClusterItemsElement.text( numberOfClusterItems - 1 );
		} else {
			// Re-render parent item (seed).
			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess',
				action: 'getAssessItemHtml',
				queryString: 'insertNew=0&id=' + params.seedDigest,
				success: getAssessItemHtmlCallback
			});
		}

		// Render child as new separate item.
		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess',
			action: 'getAssessItemHtml',
			queryString: 'insertNew=1&id=' + params.itemDigest,
			success: getAssessItemHtmlCallback
		});
	}
}

function getAssessItemHtmlCallback( params ) {
	if ( params.insertNew == 1 ) {
		$('.assess-items').prepend( params.itemHtml );
	} else {
		$('div[id="' + params.itemDigest + '"]').html( params.itemHtml );
		
		$('.item-arrow:visible').hide();
		$('#' + params.itemDigest.replace(/%/g, '\\%') + ' .item-arrow').show();						
	}	
}

function selectNextItem ( currentItem ) {
	var nextItem = currentItem.nextAll('.assess-item:visible').first();
	
	if ( nextItem.hasClass('assess-item') ) {
		$('.item-arrow:visible').hide();
		nextItem.children('.item-arrow').show();
		
		var currentItemPosition = currentItem.position();
		if ( currentItemPosition ) {
			$(document).scrollTop( currentItemPosition.top );
		}
	}
}
