/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

/****** functions for printing the preview  *********/
function printInput( inputElement, windowTitle ){
	var ifr = window.frames['printFrame'];
	if ( windowTitle === undefined ) {
		windowTitle = 'TARANIS';
	}
	
	if (ifr){ //print the content of the invisible iframe
		if ( $('#content', ifr.document ).length == 0 ) {
			$( '#body_preview', ifr.document ).empty();
			$( '#body_preview', ifr.document ).append( '<pre id="content"></pre>');
		}
		
		var textToPrint = inputElement.val();
		if ( inputElement.is('[data-printbefore]') ) {
			textToPrint = inputElement.attr('data-printbefore') + "\n" + textToPrint;
		}
		if ( inputElement.is('[data-printafter]') ) {
			textToPrint += "\n" + inputElement.attr('data-printafter');
		}
		
		$('#content', ifr.document ).text( textToPrint );
		$('title', ifr.document).text( windowTitle );

		ifr.focus();
		ifr.print();
	} else { //print by opening a new window and then closing it
		var textElement = $('<textarea>').val( inputElement.val() );
		textElement.text( textElement.val() );

		var textToPrint = textElement.html();
		if ( inputElement.is('[data-printbefore]') ) {
			textToPrint = inputElement.attr('data-printbefore') + "\n" + textToPrint;
		}
		if ( inputElement.is('[data-printafter]') ) {
			textToPrint += "\n" + inputElement.attr('data-printafter');
		}		
		
		var html='<html><head><title>' + windowTitle + '</title><style type="text/css">pre{font:normal 11px Courier;}</style></head><body onload="window.print();window.close()"><pre>' + textToPrint + '</pre></body></html>';
 
		var win = window.open('','_blank','menubar,scrollbars,resizable');
		win.document.open();
		win.document.write(html);
		win.document.close();
	}
}

function printHtmlInput( html ){
	
	var ifr = window.frames['printFrame'];
	if (ifr){ //print the content of the invisible iframe
		$('title', ifr.document).text( 'TARANIS' );
		$('#body_preview', ifr.document).html( html );
		$('#body_preview', ifr.document).html( $('#body_preview', ifr.document).text() );

		ifr.focus();
		ifr.print();
	} else { //print by opening a new window and then closing it
		var html='<html><head><style type="text/css">pre{font:normal 11px Courier;}</style></head><body onload="window.print();window.close()">' + html + '</body></html>'
		var win = window.open('','_blank','menubar,scrollbars,resizable');
		win.document.open();
		win.document.write(html);
		win.document.close();
	}
}

function writeContent(objIframe){
	var html='<html><head><title></title><style type="text/css" media="print">div{font:normal 12px Courier; white-space: pre-wrap}</style></head><body id="body_preview"><div id="content"></div></body></html>';
	objIframe.document.write(html);
	objIframe.document.close();
}
