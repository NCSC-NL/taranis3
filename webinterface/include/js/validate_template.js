/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function validateTemplate() {
	try {
		// code for IE
		if (window.ActiveXObject) {
			var xmlDoc = new ActiveXObject("Microsoft.XMLDOM");
			xmlDoc.async = "false";
			xmlDoc.loadXML(document.all("template").value);
	
			if (xmlDoc.parseError.errorCode != 0) {
				var txt = "Error Code: " + xmlDoc.parseError.errorCode + "\n";
				txt = txt + "Error Reason: " + xmlDoc.parseError.reason;
				txt = txt + "Error Line: " + xmlDoc.parseError.line;
				throw txt;
				//alert(txt);
			} else {
				throw "No errors found";
				//				alert("No errors found");
			}
		}
		// code for Mozilla, Firefox, Opera, etc.
		else if (document.implementation && document.implementation.createDocument) {
			var parser = new DOMParser();
			var text = document.getElementById("publication-template-details-template").value;
			var xmlDoc = parser.parseFromString(text, "text/xml");
			text = text.replace(/\n/gi, "");
			var manditory_fields_pattern = new RegExp("^<publication>.*<template>.*<fields>");
			if (xmlDoc.documentElement.nodeName == "parsererror") {
				throw xmlDoc.documentElement.childNodes[0].nodeValue;
				//alert(xmlDoc.documentElement.childNodes[0].nodeValue);
			} else if ( !manditory_fields_pattern.test(text) ) {
				throw "Fields are not properly defined. \nThe following are manditory: \n\n - <publication> \n - <template> \n - <fields>  ";
				//alert("Fields are not properly defined. \nThe following are manditory: \n\n - <publication> \n - <template> \n - <fields>  ");
			} else {
				throw "No errors found.";
				//alert("No errors found");
			}
		} else {
			throw "Your browser cannot handle this script.";
			//alert('Your browser cannot handle this script');
		}
	}
	catch ( err ) {
		alert( err );
		return true;
	}
}
