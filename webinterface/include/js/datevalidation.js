/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

// Check if date fields are all okay.
function validateForm(field_ids){
	for (var i = 0; i < field_ids.length; i++) {
		var input = document.getElementById(field_ids[i]);

		if (input.value != '') {
			if (_isDate(input.value)) {
				input.value = _padDate(input.value);
			} else {
				alert("Please enter a valid date: dd-mm-yyyy");
				input.focus();
				return false;
			}
		}
	}

	return true;
}

// Does dmy_string specify a valid date in dd-mm-yyyy format?
function _isDate(dmy_string) {
	try {
		dmy_string = _padDate(dmy_string);
	} catch (e) {
		return false;
	}

	var ymd_string = dmy_string.split('-').reverse().join('-');
	return !!Date.parse(ymd_string);
}

// 1-1-2015 => 01-01-2015
function _padDate(date_string) {
	function zeroPad(number) {
		return String(number).length >= 2 ? number : '0' + number;
	}

	var bits = date_string.match(/^(\d?\d)-(\d?\d)-(\d\d\d\d)$/);
	if (bits) {
		return zeroPad(bits[1]) + "-" + zeroPad(bits[2]) + "-" + bits[3];
	}
	else {
		throw "can't pad invalid date " + date_string;
	}
}
