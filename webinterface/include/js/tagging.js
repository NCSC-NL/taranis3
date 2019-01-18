/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

$( function () {

	$('#content').on('click', '.img-edit-tags', function () {
		var itemID = $(this).attr('data-itemid'),
			tName = $(this).attr('data-tname');
		
		var dialog = $('<div>').newDialog();
		dialog.html('<fieldset>loading...</fieldset>');
		
		$.main.ajaxRequest({
			modName: 'tagging',
			pageName: 'tag',
			action: 'openDialogTagsDetails',
			queryString: 'id=' + itemID + '&t_name=' + tName,
			success: function ( params ) {
				$('#tags-input')
					.newAutocomplete()
					.focus()
					.keypress(function(event) {
						if(event.keyCode == $.ui.keyCode.ENTER) {
							event.preventDefault();
							var buttons = dialog.dialog('option', 'buttons');
							buttons[0].click();
						}
					});
				
				$('#dossier-quick-reference-link').click( function () {
					if ( $('#dossier-quick-reference').hasClass('hidden') || $('#dossier-quick-reference').is(':hidden') ) {
						$('#dossier-quick-reference')
							.show()
							.removeClass('hidden');
					} else {
						$('#dossier-quick-reference').hide();
					}
				});
				
				dialog.dialog('option', 'buttons',[
					{
						text: 'Save',
						click: function () {

							$.main.ajaxRequest({
								modName: 'tagging',
								pageName: 'tag',
								action: 'setTags',
								queryString: 'tags=' + encodeURIComponent( $('#tags-input').val() ) + '&item_id=' + itemID + '&t_name=' + tName,
								success: function (saveParams) {
									if ( saveParams.message == '' ) {

										var p = /^publication_.*/;
										var $where = p.test(tName)
										? $('.publications-item[data-detailsid="' + itemID.replace(/%/g, '\\%') + '"]' + ' .tags-wrapper')
										: $('#' + itemID.replace(/%/g, '\\%') + ' .tags-wrapper');

console.log("tags save " + saveParams.tagsHTML);
console.log(saveParams);
										$where.removeClass('block')
										$where.html( saveParams.tagsHTML );

										$.main.activeDialog.dialog('close');
									} else {
										alert( saveParams.message );
									}
								}
							});
						}
					},
					{
						text: 'Cancel',
						click: function () { $(this).dialog('close') }
					}
				]);
				
			}
		});
		
		dialog.dialog('open');
		
		dialog.dialog('option', 'title', 'Tags');
		dialog.dialog('option', 'width', '800px');
		dialog.dialog({
			buttons: {
				'Close': function () {
					$(this).dialog( 'close' );
				}
			}
		});
		
	});
	
});

function getTagsForItems ( itemClass, tagType ) {

	var getTagsQueryString = '';
	var idAttribute = ( itemClass == 'publications-item' ) ? 'data-detailsid' : 'id';

	$('.' + itemClass).each( function (i) {
		getTagsQueryString += '&ids=' + $(this).attr(idAttribute);
	});
	
	$.main.ajaxRequest({
		modName: 'tagging',
		pageName: 'tag',
		action: 'getTags',
		queryString: getTagsQueryString + '&t_name=' + tagType,
		success: function ( params ) {
			$.each( params.tags, function (itemID,tags) {
				$.each( tags, function (i,tag) {
					$('<li>')
						.appendTo('.' + itemClass + '[' + idAttribute + '="' + itemID.replace(/%/g, '\\%') + '"]' + ' .tags-list')
						.attr('title', 'tag: ' + tag)
						.html(tag)
						.addClass('tags-list-item block');
				});
				$('.' + itemClass + '[' + idAttribute + '="' + itemID.replace(/%/g, '\\%') + '"]' + ' .tags-wrapper').removeClass('block');
			});
		}
	});
}

function getTagsForAnalyzePage () {
	getTagsForItems('analyze-item', 'analysis');
}

function getTagsForAdvisoryPage () {
	getTagsForItems('publications-item', 'publication_advisory');
}

function getTagsForForwardPage () {
	getTagsForItems('publications-item', 'publication_advisory_forward');
}

function getTagsForEndOfShiftPage () {
	getTagsForItems('publications-item', 'publication_endofshift');
}

function getTagsForEndOfDayPage () {
	getTagsForItems('publications-item', 'publication_endofday');
}

function getTagsForEndOfWeekPage () {
	getTagsForItems('publications-item', 'publication_endofweek');
}

// jQuery UI autocomplete wrapper for tagging
$.fn.newAutocomplete = function (idElement, type, inputElement) {
		
	function split( val ) {
		return val.split( /,\s*/ );
	}
	function extractLast( term ) {
		return split( term ).pop();
	}

	$(this)
		// don't navigate away from the field on TAB-key when selecting an item
		.bind( "keydown", function( event ) {
			if ( event.keyCode === $.ui.keyCode.TAB ) {
				event.preventDefault();
			}
		})
		.autocomplete({
			source: function( request, response ) {
				$.getJSON( 'loadfile/tagging/tag/getList', {
					term: extractLast( request.term )
				}, response );
			},
			search: function() {
				// custom minLength
				var term = $.trim( extractLast( this.value ) );
				if ( term.length < 1 ) {
					return false;
				}
			},
			focus: function() {
				// prevent value inserted on focus
				return false;
			},
			select: function( event, ui ) {
				var terms = split( this.value );
				// remove the current input
				terms.pop();
				// add the selected item
				terms.push( ui.item.value );
				// add placeholder to get the comma-and-space at the end
				terms.push( "" );
				this.value = terms.join( ", " );
				return false;
			}
		})
		.data( "ui-autocomplete" )._renderItem = function( ul, item ) {
			if ( item.label != '' ) {
				return $( "<li>" )
					.append( "<a>" + item.value + "<br><span class=\"italic grey-font\">dossier: " + item.label + "</a>" )
					.appendTo( ul );
			} else {
				return $( "<li>" )
				.append( "<a>" + item.value + "</a>" )
				.appendTo( ul );
			}
		};
	return $(this);
}
