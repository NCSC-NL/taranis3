/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 *
 * This script takes care of the following:
 * - set configuration variables to $.main which can be used globally
 * - handle F5 key press
 * - initialize a spinner
 * - handle pagination button click
 * - create wrapper for jQuery UI Dialog
 * - create wrapper for jQuery UI Tabs (is not needed anymore)
 * - create wrapper for jQuery serialize()
 * - handle link <a> click
 * - show/hide for a 'hover-block'
 * - handle first page load of '/taranis/' and '/taranis/goto/...' shortcuts
 * - fix browser back button usage using history API
 * - create wrapper for jQuery ajax request ($.ajax). Does all content loading and JS file inclusion.
*/

$.main = {};

function initMain ( webroot, scriptroot, userid, fullname, csrfToken, shortcut) {
	$.main.webroot = webroot;
	$.main.scriptroot = scriptroot;
	$.main.userid = userid;
	$.main.fullname = fullname;
	$.main.csrfToken = csrfToken;
	$.main.shortcut = shortcut;
	$.main.loadedScripts = new Array();
	$.main.activeDialog = null;
	$.main.lastRequest = null;
	$.main.reEmailAddress = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
	$.main.taranisSpinner = new TaranisSpinner();
}

$( function () {
	//TODO: move F5 handling to Mousetrap plugin
	// catch F5 key (page refresh)
	$(document).keydown( function (e) {

		var characterCode;
		try {
			if (e && e.which) {
				e = e;
				characterCode = e.which;
			} else {
				e = event;
				characterCode = e.keyCode;
			}
			if(characterCode == 116){
				e.preventDefault();
				history.state.triggeredByPopstate = true;
				$.main.ajaxRequest( history.state );
				return false;
			}
			return true;
		}
		catch (err) {
			return true;
		}
	});

	// Clicking on a pagination button will relocate the hidden input field 'hidden-page-number'
	// after the specified data-filterbutton, which should be in the same form as the filter input fields.
	$.fn.pagebar = function () {
		var pagebarButtons = $(this);

		$.each( pagebarButtons, function(i, pagebarButton) {
			$(pagebarButton).click( function () {

				var filterButton = $(this).parent('#pagination').attr('data-filterbutton');
				if ( $('#' + filterButton).siblings('#hidden-page-number').length > 0 ) {
					$('#hidden-page-number').val( $(this).attr('data-pagenumber') );
				} else {
					$('<input type="hidden" id="hidden-page-number" name="hidden-page-number">')
						.val( $(this).attr('data-pagenumber') )
						.insertAfter('#' + filterButton);
				}
				// The extra pagination parameter is used to tell what origin the click (search) event is.
				// The bound click event for the filterbutton should set the value of the hidden-page-number
				// to 1 if the origin is not 'pagination'.
				$('#' + filterButton).trigger('click', 'pagination');
			});
		});
	};

	// create new dialogs with jQuery UI dialog wrapper
	$.fn.newDialog = function () {
		var dialog = $(this)
			.html('<fieldset>loading...</fieldset>')
			.addClass('dialogs')
			.dialog({
				autoOpen: false,
				title: 'Loading...',
				modal: false,
				position: 'top',
				resizable: false,
				open: function (event, ui) {
					if ( $('#screen-overlay').is(':visible') == false ) {
						$('#screen-overlay').show();
					}
					Mousetrap.pause();
				},
				close: function (event,ui) {

					if ( $('.ui-dialog:visible').length == 0 ) {
						$('#screen-overlay').hide();
					} else {
						// set focus to the last opened dialog
						$( $('.ui-dialog:visible')[ $('.ui-dialog:visible').length -1]).children('.ui-dialog-content').trigger('dialogfocus');
					}
					if ( $('mousetrap').length > 0 ) {
						Mousetrap.unpause();
					}
					// completely remove created dialog.
					$(this).remove();
				},
			})
			.on( 'dialogfocus', function( event, ui ) {
				// 'move' other dialog to background
				if ( $.main.activeDialog ) {
					$.main.activeDialog.parent().css('opacity', '0.7');
				}

				$.main.activeDialog = $(this);

				// 'move' focussed dialog to foreground
				$.main.activeDialog.parent().css('opacity', '1');

				$('#screen-overlay').show();
			})
			.appendTo('#diaglog');

		return $(this);
	};

	$.fn.newTabs = function () {
		var tabs = $(this).tabs({
			activate: function (event, ui) {
				$.main.activeDialog.trigger('dialogfocus');
			}
		});
		return $(this);
	};

	// serialize forms with jQuery serialize, but keep the spaces.
	$.fn.serializeWithSpaces = function () {
		var serialized = $(this).serialize();
		return serialized.replace(/\+/g, ' ');
	};

	// serialize forms with jQuery serializeArray, but into a hash structure instead.
	$.fn.serializeHash = function () {
		"use strict";

		var paramsObj = {};

		$.each( $(this).serializeArray(), function (i, field) {
			if ( field.name in paramsObj ) {
				if ( typeof paramsObj[field.name] === 'object' ) {
					paramsObj[field.name].push(field.value);
				} else {
					paramsObj[field.name] = [field.value, paramsObj[field.name]];	
				}
			} else {
				paramsObj[field.name] = field.value;
			}
		});

		return paramsObj;
	};

	// clicking on a link (or triggering a click on the 'super-secret-link') will do a AJAX request to index.pl
	$(document).on('click', 'a', function(event) {

		if ( $(this).attr('href') == undefined || $(this).attr('href').charAt(0) == '#' ) {
			event.preventDefault();
			return false;
		} else if ( $(this).attr('href').indexOf('http') == 0 || $(this).attr('href').indexOf('mailto') == 0) {
			return true;
		} else {
			event.preventDefault();

			// strip off last slash if present
			var url = $(this).attr('href').replace( /\/$/, '' );

			var url_arr = url.split('/');

			var modName = url_arr[0];
			var pageName = url_arr[1];
			var action = url_arr[2];
			var queryString = url_arr[3];

			var linkCallback = null;
			if ( $(this).attr('data-callback') ) {
				linkCallback = $(this).attr('data-callback');
				if ( $(this).attr('id') == 'super-secret-link' ) {
					$(this).removeAttr('data-callback');
				}
			}

			if ( pageName == 'logout' ) {
				$('#main-wrapper').toggle('drop');
				$('#dashboard-minified').hide();
			}

			$.main.ajaxRequest({
				modName: modName,
				pageName: pageName,
				action: action,
				queryString: queryString,
				success: linkCallback
			});
		}
	});

	// hover block show
	$('#content').on('mouseenter', '.hover-block', function () {
		$('.hover-block-content', this).show();
	});

	// hover block hide
	$('#content').on('mouseleave', '.hover-block', function () {
		$('.hover-block-content', this).hide();
	});

	// first page load of main, show the dashboard
	if ( $('#content').html() == '' ) {

		if ( $.main.shortcut ) {

			var shortcut = JSON.parse( $.main.shortcut )

			// TODO: use setMenu() for below
			if ( shortcut.menuitem ) {
				$('.selected-menu').removeClass('hover-submenu');
				$('.selected-menu').removeClass('selected-menu');
				$('.selected-submenu').removeClass('selected-submenu');

				$('#' + shortcut.menuitem + '-menu').addClass('selected-menu');
				$('#' + shortcut.menuitem + '-submenu').addClass('selected-submenu');
				$('title').text('Taranis - ' + firstLetterToUpper( shortcut.menuitem) );
			}

			$.main.ajaxRequest({
				modName: shortcut.modname,
				pageName: shortcut.scriptname,
				action: shortcut.action,
				queryString: shortcut.parameters,
				success: shortcut.action + 'Callback',
				isInitialPage: true
			}, false);

		} else {
			$.main.ajaxRequest({
				modName: 'dashboard',
				pageName: 'dashboard',
				action: 'getDashboardData',
				success: 'getDashboardDataCallback'
			}, true);
		}

		$.main.ajaxRequest({
			modName: 'dashboard',
			pageName: 'dashboard',
			action: 'getMinifiedDashboardData',
			success: null
		}, true);

	}
});

// mechanism for correct working of browser Back button
window.onpopstate = function ( event ) {
	if ( event.state == null ) {
		return;
	}
	event.state.triggeredByPopstate = true;
	$.main.ajaxRequest( event.state );
};

/*
 * @param {Object} request - consists of the following properties:
 * - modName STRING
 * - pageName STRING
 * - action STRING
 * - queryString STRING (optional)
 * - success FUNCTION, STRING or null
 * - isAutoRefresh BOOLEAN (optional)
 * - triggeredByPopstate BOOLEAN (optional) - whether this request was triggered by window.onpopstate
 * - isInitialPage BOOLEAN (optional)
 * @param {Boolean} noSpinner - prevents the spinner and overlay from showing, default is false
 */
$.main.ajaxRequest = function ( request, noSpinner ) {
	$('#error').html('');

	if (!noSpinner) {
		$.main.taranisSpinner.start();
	}

	var params = new Object();
	if ( request.queryString !== undefined ) {
		// if query starts with '&', remove it.
		if ( request.queryString.indexOf('&') == 0 ) {
			request.queryString = request.queryString.substr(1);
		}

		// create key/value datastructure of input parameters
		$.each( request.queryString.split('&'), function (i, kvPair) {
			var k = kvPair.substr(0, kvPair.indexOf('='));
			var v = kvPair.substr(kvPair.indexOf('=') +1);
			v = decodeURIComponent(v);
			if ( k in params ) {
				if ( typeof params[k] === 'object' ) {
					params[k].push(v);
				} else {
					params[k] = [params[k], v];
				}
			} else {
				params[k] = v;
			}
		});
	}

	if (request.triggeredByPopstate) {
		params.triggeredByPopstate = true;
	}

	$.ajaxSetup({ cache: false });

	var call_url = $.main.scriptroot + '/load/' + request.modName + '/' + request.pageName + '/' + request.action;

	$.ajax({
		url: call_url,
		method: 'POST',
		data: {
			params: JSON.stringify(params)
		},
		headers: {
			'X-Taranis-CSRF-Token': $.main.csrfToken,
		},
		dataType: 'json'
	}).always(function (result) {
		if (!noSpinner) {
			$.main.taranisSpinner.stop();
		}
	}).done(function (result) {
		// load page filters html
		if ( result.page.filters ) {
			$('#filters').html( result.page.filters );
			// rebind the datepicker to .date-picker elements
			$('.date-picker').datepicker({dateFormat: "dd-mm-yy"});

			$('.btn-option-to-left').on('click', moveOptionToLeft);
			$('.btn-option-to-right').on('click', moveOptionToRight);

			if ( $('mousetrap').length > 0 ) {
				Mousetrap.unpause();
				$('#icon-keyboard-shortcuts').show();
			} else {
				Mousetrap.pause();
				$('#icon-keyboard-shortcuts').hide();
			}
		}

		// load page content html
		if ( result.page.content ) {
			$('#content').html( result.page.content );
			$('.btn-pagebar').pagebar();

			// If the browser Back/Forward button is not pushed and request is not an auto refresh, then add request to
			// history.
			if ( history.pushState && !request.triggeredByPopstate && !request.isAutoRefresh ) {
				if ( typeof request.success === 'function'  ) {
					//XXX weird.  Why?
					var functionName = request.success.toString().replace( /^function (.*?)\((.|\n)+$/m, '$1');
					window[functionName] = request.success;
					request.success = functionName;
				}

				if ( request.isInitialPage ) {
					history.replaceState( request, null, location.href );
				} else {
					history.pushState( request, null, '/taranis/' );
				}
			}
		}

		// load dashboard html
		if ( result.page.mini_dashboard ) {
			$('#dashboard-minified-content').html( result.page.mini_dashboard.html );

			// update unread counts per category
			var context = $('#assess-submenu');
			var unread  = result.page.unread_counts;
			for(var key in unread) {
				var where = $('.count-display[data-category='+key+']', context);
				var count = unread[key];
				where.html(count);
				where.attr('data-count', count);
			}
		}

		// force close dialog, because we decided (too) late that the
		// created dialog is not needed.
		if ( result.page.close_dialog ) {
			$.main.activeDialog.dialog('close');
			oneUp();
		}

		// load dialog html
		if ( result.page.dialog ) {

			$.main.activeDialog.html( result.page.dialog );

			// rebind the datepicker to .date-picker elements
			$('.date-picker').datepicker({dateFormat: "dd-mm-yy"});

			$('.btn-option-to-left').on('click', moveOptionToLeft);
			$('.btn-option-to-right').on('click', moveOptionToRight);

			$('.select-left option').on('dblclick', function () { $('.btn-option-to-right').trigger('click') } );
			$('.select-right option').on('dblclick', function () { $('.btn-option-to-left').trigger('click') } );
		}

		// load js scripts (once)
		if ( result.page.js ) {
			$.each( result.page.js, function( index, jsScript ) {
				if ( $.inArray( jsScript, $.main.loadedScripts ) == -1 ) {
					$.getScript( $.main.webroot + '/include/' + jsScript )
						.done(function(script, textStatus) {
							console.log("loaded js "+jsScript+": "+textStatus);
						})
						.fail(function(jqxhr, settings, exception) {
							console.log("failed "+jsScript+": '"+exception
							+ "' on line "+ exception.lineNumber);
						});

					$.main.loadedScripts.push( jsScript );
				}
			});
		}

		// run callback function if present
		if ( typeof request.success === 'function' ) {
			var resultParams = ( result.page.params ) ? result.page.params : [];
			request.success(resultParams);
		} else if ( typeof request.success === 'string' && typeof window[request.success] === 'function' ) {
			var resultParams = ( result.page.params ) ? result.page.params : [];
			window[request.success](resultParams);
		}
	}).fail(function (jqXHR, textStatus, errorThrown) {
		function getQuote() {
			var quotes = [
				"I think you know what the problem is just as well as I do.",
				"I know I've made some very poor decisions recently, but I can give you my complete assurance that my work will be back to normal. I've still got the greatest enthusiasm and confidence in the mission. And I want to help you.",
				"We all go a little mad sometimes.",
				"Great Scott!",
				"Okay. Time circuit's on. Flux capacitor, fluxing. Engine running.",
				"Your mother was a hamster and your father smelt of elderberries.",
				"All I see now is blonde, brunette, redhead.",
				"None shall pass!",
				"What... is the air-speed velocity of an unladen swallow?",
				"When danger reared its ugly head, he bravely turned his tail and fled.",
				"Explain again how sheep's bladders may be employed to prevent earthquakes.",
				"Consult the Book of Armaments.",
				"You want a toe? I can get you a toe, believe me. There are ways, dude. You don't wanna know about it, believe me.",
				"You mark that frame an 8, and you're entering a world of pain.",
				"Mark it zero!",
				"Darkness warshed over the dude - darker'n a black steer's tookus on a moonless prairie night. There was no bottom.",
				"How ya gonna keep 'em down on the farm once they've seen Karl Hungus.",
				"Sometimes you eat the bear, and sometimes, well, he eats you.",
				"Computer says no.",
				"You know why they put oxygen masks on planes?",
				"I am Jack's smirking revenge.",
				"Hamburgers! The cornerstone of any nutritious breakfast."
			];
			return quotes[Math.floor(Math.random() * quotes.length)];
		}

		if (!request.isAutoRefresh) {
			// Show user the error.
			var errmsg = textStatus;
			if (errorThrown) errmsg += ' - ' + errorThrown;
			if (jqXHR.status) errmsg += ' (' + jqXHR.status + ')';
			$('#content').html(
				'<p class="red-font bold italic padding-default">' + getQuote() + '</p>' +
				'<blockquote class="bold">[' + errmsg + ']</blockquote>' +
				'<p class="red-font bold italic padding-default">...anyways, check logs for details!</p>' +
				'<p>Ajax call for <tt>'+call_url+'</tt></p>'
			);
		}

		// Check if the reason for failure is that we're not logged in anymore (e.g. because of session expiry). If so,
		// redirect the user to the login page.
		$.main.gotoLoginIfSessionDead();
	});

	$.main.lastRequest = request;
};

$.main.gotoLoginIfSessionDead = function() {
	// Check if we're still logged in. If not, redirect the user to the login page.
	$.ajax({
		url: $.main.scriptroot + '/session_ok',
		dataType: 'json'
	}).done(function (data) {
		if (data.session_ok === false) {
			window.location = 'login/';
		}
	});
};
