/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	// check the item checkboxes
	$('#content-wrapper').on('click', '#checkAllTop, #checkAllBottom', function () {
		$('.assess-item-select-input:visible').prop('checked', true); 
	});

	// uncheck the item checkboxes	
	$('#content-wrapper').on('click', '#unCheckAllTop, #unCheckAllBottom', function () {
		$('.assess-item-select-input:visible').prop('checked', false); 
	});

	function assessSearchCallback() {
		var counter_text = $('#content #assess-count').text();
		$('#filters #assess-count').text(counter_text);
		startAssessTimer();
	}

	// do search
	$('#filters').on('click', '#btn-assess-search', function (event, origin) {
		stopAssessTimer();
		if ( ( origin != 'pagination' && $('#hidden-page-number').length > 0 ) || origin == 'autoRefresh' ) {
			$('#hidden-page-number').val('1');
		}

		if ( validateForm(['assess-start-date', 'assess-end-date']) ){
			if ($("input:checkbox:checked[name='item_status']").length > 0) {

				$.main.ajaxRequest({
					modName: 'assess',
					pageName: 'assess',
					action: 'search',
					queryString: $('#form-assess-standard-search').serializeWithSpaces(),
					success: assessSearchCallback
				});
			} else {
				alert("At least one option in the searchbar must be checked to perform search.");    		  
			}
		}
	});

	// click on button 'Reset filters and search' 
	$('#filters').on('click', '#btn-default-search', function () {

		if ( $('#assess-category option:selected').val() != '' ) {
			$('#assess-category option:selected').prop('selected', false);
			$('#assess-category option[value=""]').prop('selected', true);
		}

		$('#assess-search').val('');

		var today = new Date();
		var month = today.getMonth() + 1;

		$('#assess-start-date, #assess-end-date').val( today.getDate() + '-' + month + '-' + today.getFullYear() );

		$('#unread, #read, #important, #waitingroom').prop('checked', true);

		if ( $('#assess-source option:selected').val() != '' ) {
			$('#assess-source option:selected').prop('selected', false);
			$('#assess-source option[value=""]').prop('selected', true);
		}

		$('#assess-sorting option:selected').prop('selected', false);
		$('#assess-sorting option:first').prop('selected', true);

		$('#assess-hitsperpage').val('100');

		$('#btn-assess-search').trigger('click');
	});

	// pressing enter in searchfield of filters section will trigger clicking the search button
	$('#filters').on( 'keypress', '#assess-search', function (event) {
	   if ( !checkEnter(event) ) {
		   if ( validateForm(['assess-start-date', 'assess-end-date']) ) {
			   $('#btn-assess-search').trigger('click', 'searchOnEnter');
		   }
	   }
	});

	// button add custom search opens a dialog window with a form to add a search
	$('#filters').on( 'click', '#btn_addSearch', function () {

		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');

		$.main.ajaxRequest({
			modName: 'assess',
			pageName: 'assess_custom_search',
			action: 'displayCustomSearch',
			success: null
		});

		dialog.dialog('option', 'title', 'New custom search');
		dialog.dialog('option', 'width', '600px');
		dialog.dialog({
			buttons: {
				'Add custom search': function () {

					if ( $('#custom-search-description').val() == '' ) {
						alert('Please enter a description.');
					} else if ( validateForm(['custom-search-start-date', 'custom-search-end-date']) ) {

						$('#sources_left_column option, #categories_left_column option').each( function(index) {
							$(this).prop('selected', true)
						});

						$('#sources_right_column option, #categories_right_column option').each( function(index) {
							$(this).prop('selected', false);
						});

						$.main.ajaxRequest({
							modName: 'assess',
							pageName: 'assess_custom_search',
							action: 'addSearch',
							queryString: $('#form-assess-custom-search-add').serializeWithSpaces(),
							success: addCustomSearchCallback
						});
					}
				},
				'Cancel': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		dialog.dialog('open');		

	});

	// switch between standard and custom (preset) searchmethods
	$('#filters').on('click', '#btn_toggleSearchMode', function () {
		if ( $('#assess-custom-search-wrapper').is(':hidden') ) {
			$('#assess-standard-search-wrapper').hide();
			$('#assess-custom-search-wrapper').show();
			$(this).val('Switch to standard searches');
		} else {
			$('#assess-standard-search-wrapper').show();
			$('#assess-custom-search-wrapper').hide();
			$(this).val('Switch to custom searches');
		}
	});

	// do a custom search
	$('#filters').on('click', '#btn-custom-search', function (event, origin) {
		if ( $('#assess-custom-search').val() == '' ) {
			alert('Please select a preset search');
		} else {

			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess',
				action: 'customSearch',
				queryString: $('#form-assess-custom-search').serializeWithSpaces(),
				success: assessSearchCallback
			});
		}
	});

	// click on buttons 'Bulk analysis' or 'Multiple analysis' will show a status selection dialog

	function collect_assess_titles($from, $select) {
		$from.each( function (index) {
			var id     = $(this).data('id');
			var $item  = $('.assess-item[data-id="' + id + '"]');
			var clid   = $item.data('clusterid');
			if( clid ) {
				$item = $('.assess-item[data-clusterid="' + clid + '"]');
			}
	
			$item.find('.assess-item-title').each( function () {
				var title  = $.trim($(this).text());
				$select.append($('<option>').val(id).text(title).attr('title', title));
			});
		});
	}

	$('#content-wrapper').on('click', '#btn_bulkAnalysis, #btn_bulkAnalysisBottom, #btn_multipleAnalyses, #btn_multipleAnalysesBottom', function () {
		if ( $('.assess-item-select-input:checked').length > 1 ) {

			var hasClusteredItems = ( $('.assess-item-select-input[data-iscluster="1"]:checked').length > 0 ) ? 1 : 0
			var action = $(this).attr('id').replace(/^btn_(bulk|multiple).*$/, '$1' );

			var dialog = $('<div>').newDialog();
			dialog.html('<fieldset>loading...</fieldset>');

			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess_bulk',
				action: 'displayBulkAnalysis',
				queryString: 'action=' + action + '&hasClusteredItems=' + hasClusteredItems,
				success: function () {
					if ( action == 'bulk' ) {
						var $items = $('.assess-item-select-input:checked');
						collect_assess_titles($items, $('#bulk-analysis-title'));
					}
				}
			});

			dialog.dialog('option', 'title', 'Bulk analysis');
			dialog.dialog('option', 'width', '800px');
			dialog.dialog({
				buttons: {
					'Create analysis': function () {

						var lastSelectedItemId = 0;
						var clusterItemMapping = new Object();
						var queryString = $('#form-assess-bulk-analysis').serializeWithSpaces();

						$('.assess-item-select-input:checked').each( function (index) {
							if ( $(this).is(':visible') ) {

								if ( $('#include-clustered-items-yes').length > 0 ) {

									var itemDigest = $(this).val();

									if ( $(this).attr('data-iscluster') == 1 ) {
										var clusterId = $('div[id="' + itemDigest +'"]').attr('data-clusterid');
										var $items    = $('.item-cluster-row[data-clusterid="' + clusterId + '"]');

										if ( $('#include-clustered-items-yes:checked').length == 1  ) {

											if ( action == 'multiple' ) {
												$items.each( function (index) {

													if ( itemDigest in clusterItemMapping ) {
														clusterItemMapping[itemDigest].push( $(this).attr('id') );
													} else {
														clusterItemMapping[itemDigest] = [ $(this).attr('id') ];
													}
												});
											} else {
												$items.each( function (index) {
													queryString += '&id=' + $(this).attr('id');
												});
											}
										} else {
											// mark all clustered items as read

											var statusReadQueryString = 'status=read'
											$items.each( function (index) {
												statusReadQueryString += '&id=' + $(this).attr('id');
											});

											$.main.ajaxRequest({
												modName: 'assess',
												pageName: 'assess_status',
												action: 'setStatus',
												queryString: statusReadQueryString,
												success: setStatusCallback
											});
										}
									}
								} 

								queryString += '&id=' + $(this).val();
								lastSelectedItemId = $(this).val();
							}
						});

						queryString += '&action=' + action;

						if ( $.isEmptyObject( clusterItemMapping ) == false ) {
							queryString += '&clusterItemMapping=' + encodeURIComponent( JSON.stringify( clusterItemMapping ) )
						}

						$('.item-arrow:visible').hide();
						$('#' + lastSelectedItemId.replace(/%/g, '\\%') + ' .item-arrow').show();						

						$.main.ajaxRequest({
							modName: 'assess',
							pageName: 'assess_bulk',
							action: 'addAnalysis',
							queryString: queryString,
							success: bulkAnalysisCallback
						});							
					},
					'Cancel': function () {
						$(this).dialog( 'close' );
					}
				}
			});
			dialog.dialog('open');

		} else {
			alert("You need to check at least 2 items!");
		}
	});

	// buttons clicked to set the status of items to 'Read' or 'Important'
	$('#content-wrapper').on('click', '#btn_markRead, #btn_markImportant, #btn_markReadBottom, #btn_markImportantBottom', function () {

		if ( $('.assess-item-select-input:checked').length > 0 ) {
			var lastSelectedItemId = '';
			var queryString = 'status=' + $(this).attr('id').replace(/^btn_mark(important|read).*$/i, '$1');

			$('.assess-item-select-input:checked').each( function (index) {

				if ( $(this).is(':visible') ) {
					var itemDigest = $(this).val();

					if ( $(this).attr('data-iscluster') == 1 ) {
						var clusterId = $('div[id="' + itemDigest +'"]').attr('data-clusterid');

						$('.item-cluster-row[data-clusterid="' + clusterId + '"]').each( function (index) {
							queryString += '&id=' + $(this).attr('id');
						});
					}

					queryString += '&id=' + $(this).val();
					lastSelectedItemId = $(this).val();
				}
			});

			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'assess_status',
				action: 'setStatus',
				queryString: queryString,
				success: setStatusCallback
			});	

			$('.item-arrow:visible').hide();
			$('#' + lastSelectedItemId.replace(/%/g, '\\%') + ' .item-arrow').show();

		} else {
			alert("You need to check at least 1 item!!");
		}
	});

	// send multiple emails 
	$('#content-wrapper').on('click', '#btn-mail-assess-items, #btn-mail-assess-items-bottom', function () {
		if ( $('.assess-item-select-input:checked').length > 0 ) {
			var lastSelectedItemId;
			var queryString = '';
			$('.assess-item-select-input:checked').each( function (index) {
				if ( $(this).is(':visible') ) {
					queryString += '&id=' + $(this).val();
					lastSelectedItemId = $(this).val();
				}
			});

			var dialog = $('<div>').newDialog();
			dialog.html('<fieldset>loading...</fieldset>');

			$.main.ajaxRequest({
				modName: 'assess',
				pageName: 'mail',
				action: 'displayMailMultipleItems',
				queryString: queryString,
				success: function (params) {
					$(dialog).on('click', '.assess-multiple-mail-toggle-message', function () {
						var descriptionBlock = $(this).parent().siblings('.assess-multiple-mail-description-block');
						if ( descriptionBlock.hasClass('hidden') ) {
							descriptionBlock.removeClass('hidden')
						} else {
							descriptionBlock.toggle()
						}
					});

					var re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
					$('#btn-assess-multiple-mail-add-address').click( function () {
						var emailAddress = $('#assess-multiple-mail-extra-address').val(); 
						if ( emailAddress != '' && re.test( emailAddress ) ) {
							$('<option>')
								.val( emailAddress )
								.text( emailAddress )
								.appendTo('#assess-multiple-mail-to')
								.prop('selected', true);
							$('#assess-multiple-mail-extra-address').val('')
						} else {
							alert ("Please enter a valid e-mail address!");	
						}
					});
				}
			});

			dialog.dialog('option', 'title', 'Send multiple emails');
			dialog.dialog('option', 'width', '730px');
			dialog.dialog({
				buttons: {
					'Send emails': function () {

						if ( $('#assess-multiple-mail-to option:selected').length == 0 ) {
							alert('Please select one or more email addresses.');
						} else {

							var mailItems = new Array(),
								mailAddresses = new Array();

							$('.assess-multiple-mail-item').each( function (index) {
								var mailItem = new Object(),
									mailId = $(this).attr('data-id');
								mailItem.subject = $('.assess-multiple-mail-subject[data-id="' + mailId + '"]').val();
								mailItem.body = $('.assess-multiple-mail-description[data-id="' + mailId + '"]').val();
								mailItem.id = mailId;
								mailItems.push( mailItem );
							});

							$.main.ajaxRequest({
								modName: 'assess',
								pageName: 'mail',
								action: 'mailMultipleItems',
								queryString: 'items=' + encodeURIComponent( JSON.stringify( mailItems ) ) + '&addresses=' + $('#assess-multiple-mail-to').val(),
								success: function (params) {

									// replace all buttons with a Close button 
									$.main.activeDialog.dialog('option', 'buttons', [
										{
											text: 'Close',
											click: function () { $(this).dialog('close') }
										}
									]);

								}
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
			$('#' + lastSelectedItemId.replace(/%/g, '\\%') + ' .item-arrow').show();

		} else {
			alert("You need to check at least 1 item!!");
		}
	});

});

function addCustomSearchCallback ( params ) {
	if ( params.search_is_added == 1 ) {
		var option = $('<option>');
		option.val(params.search_id);
		option.text(params.search_description)

		$('#assess-custom-search').append(option);

		$.main.activeDialog.dialog('close');
	} else {
		$('#dialog-error')
			.text(params.message)
			.show();
	}
}

function bulkAnalysisCallback (params ) { 
	if ( params.analysis_is_added == 1 ) {

		$.each( params.ids, function(i,id) {
			id = encodeURIComponent( id );
			// set item visualy to watitingroom 
			$('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title')
				.addClass('assess-waitingroom')
				.removeClass('assess-read assess-unread assess-important');

			// if the status waitingroom in the filter is unchecked, hide the selected items
			if ( $('#waitingroom').is(':checked') == false ) {
				$('div[id="' + id + '"]').fadeOut('slow', function () {
					if ( $('.item-arrow:visible').length == 0 ) {
						selectNextItem( $('div[id="' + id + '"]') );
					}
				});
			}

			// unchecked selected items
			$('div[id="' + id + '"] .assess-item-select-input').prop('checked', false);
		});

		$.main.activeDialog.dialog('close');
	} else {
		$('#dialog-error')
			.text(params.message)
			.removeClass('hidden');
	}	
}

function setStatusCallback ( params ) {
	if ( params.status_is_set == 1 ) {

		$.each( params.ids, function(i,id) {
			id = encodeURIComponent( id );

			if ( $('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').hasClass('assess-waitingroom') == false ) {
				// set item visualy to status 'read' or 'important'
				$('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').removeClass('assess-unread assess-read assess-important');

				$('div[id="' + id + '"] .assess-item-title, div[id="' + id + '"] .assess-item-title').addClass('assess-' + params.status);

				// if the status in the filter is unchecked, hide the selected items
				if ( $('#' + params.status).is(':checked') == false ) {

					var unreadItemsCount = $('.assess-unread:visible' ).length;
					$('div[id="' + id + '"]').fadeOut('slow', function() {

						if ( 
							$('.assess-item:visible').length == 0 
							|| ( params.status == 'read' && unreadItemsCount == 1 ) 
						) {
							if ( $('#btn-assess-search').is(':visible') ) {
								$('#btn-assess-search').trigger('click');
							} else {
								$('#btn-custom-search').trigger('click');
							}
						} else {
							if ( $('.item-arrow:visible').length == 0 ) {
								selectNextItem( $('div[id="' + id + '"]') );
							}
						}
					});
				}
			}			
			// uncheck selected items
			$('div[id="' + id + '"] .assess-item-select-input').prop('checked', false);
		});
	} else {
		alert( params.message );
	}
}
