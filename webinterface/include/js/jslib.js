/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

Array.prototype.find = function(searchStr) {
  var returnArray = false;
  for (i=0; i<this.length; i++) {
    if (typeof(searchStr) == 'function') {
      if (searchStr.test(this[i])) {
        if (!returnArray) { returnArray = [] }
        returnArray.push(i);
      }
    } else {
      if (this[i]===searchStr) {
        if (!returnArray) { returnArray = [] }
        returnArray.push(i);
      }
    }
  }
  return returnArray;
}

/***************************** sorting dropdownlistboxes  *******************/
function compareOptionText(a,b) {
	/*
	 * return >0 if a>b
	 * 0 if a=b
	 * <0 if a<b
	 */

	// textual comparison
	return a.text!=b.text ? a.text<b.text ? -1 : 1 : 0;
	// numerical comparison
	// return a.text - b.text;
}

function sortOptions(list) {
	var items = list.options.length;

	// create array and make copies of options in list
	var tmpArray = new Array(items);
	for ( i=0; i < items; i++ ) {
		tmpArray[i] = list.options[i];
	}

	// sort options using given function
	tmpArray.sort(compareOptionText);

	// make copies of sorted options back to list
	for ( i=0; i<items; i++ ){
		list.options[i] = tmpArray[i];
	}
}
/*****************************************************************************/

/********** moving options from left to right and vice versa *****************/
function moveOptionToLeft($pair) {
	var rightColumn = $pair.find('.select-right');
	var leftColumn  = $pair.find('.select-left');

	rightColumn.children('option:selected').each( function(index) {
		$(this).off('dblclick').on('dblclick', function () {
			 $('.btn-option-to-right', $pair).trigger('click') } );
		leftColumn.append( $(this) );
	});

	sortOptions(leftColumn[0]);
}

function moveOptionToRight($pair) {
	var rightColumn = $pair.find('.select-right');
	var leftColumn  = $pair.find('.select-left');

	leftColumn.children('option:selected').each( function(index) {
		$(this).off('dblclick').on('dblclick', function () {
			$('.btn-option-to-left', $pair).trigger('click') } );
		rightColumn.append( $(this) );
	});
	
	sortOptions(rightColumn[0])
}

//function addOption (left_column_name, right_column_name) {
//	var right_column = document.getElementById(right_column_name);
//	var left_column = document.getElementById(left_column_name);
//	for ( var i = 0; i < right_column.length; i++ ) {
//		if ( right_column.options[i].selected == true) {
//			var new_option = right_column.options[right_column.selectedIndex];
//			var index = left_column.length;
//			left_column.options[index] = new_option;
//			i--;
//		}
//	}
//	sortOptions(left_column);
//	return true;
//}
//
//function removeOption (left_column_name, right_column_name) {
//	var left_column = document.getElementById(left_column_name);
//	var right_column = document.getElementById(right_column_name);
//	for ( var i = 0; i < left_column.length; i++ ) {		
//		if ( left_column.options[i].selected == true) {			
//			var del_option = left_column.options[left_column.selectedIndex];
//			var index = right_column.length;
//			right_column.options[index] = del_option;
//			i--;
//		}
//	}
//	sortOptions(right_column);
//	return true;
//}
/*****************************************************************************/

function showOptionsText ( text, div_destination_id ) {
	document.getElementById(div_destination_id).innerHTML = text;
}

 //checkRightColumnOptions will remove the options that are already in the left column
function checkRightColumnOptions( leftColumn, rightColumn ) {
	leftColumn.children('option').each( function (i) {
		var leftColumnOption = $(this);
	
		rightColumn.children('option').each( function (i) {
			var rightColumnOption = $(this);
			
			if ( leftColumnOption.val() == rightColumnOption.val() ) {
				rightColumnOption.remove();
			}
		});
	});
}


function checkSearchLength (search_field_id, search_length) {
	if ( document.getElementById(search_field_id).textLength < search_length ) {
		alert('Search must be at least ' + search_length + ' characters of length.');
		return false;
	} else {
		return true;
	};
}

function checkEnter(e){
	var characterCode 
	try {
		if (e && e.which) { 
			e = e
			characterCode = e.which
		} else {
			e = event
			characterCode = e.keyCode 
		}
		if(characterCode == 13){ //if generated character code is equal to ascii 13 (if enter key)
			return false
		}	else {
			return true
		}
	}
	catch (err) {
		return true;
	}
}

//function reloadParent(goto_anchor) {
//	try {	
//		if ( goto_anchor == 1 ) {
//			window.opener.document.forms[0].action = window.opener.location;
//			window.opener.document.forms[0].submit();
//		} else {
//			window.opener.document.forms[0].submit();
//		}
//	}
//	catch (err) {
//		return true;
//	}	
//}

//function reloadWindow ( myWindow ) {
//	try {
//		if ( myWindow.confirm( 'Do you wish to reload this window?' ) ) {
//			
//		//myWindow.location.reload();
//			myWindow.document.forms[0].submit();
//		}
//	} catch ( err ) {
//		return true;
//	}
//}

	//reloadParentAndClose() possibly not in use!
//function reloadParentAndClose() {
//    opener.document.location.reload();
//    self.close();	
//}

/*function openChild( file,window,width,height ) {
	leftval = (screen.width - width) / 2;
	topval = (screen.height - height) / 2;
	
	var windowHash = $.sha256( file );
	
	childWindow = open(file, windowHash, 'resizable=no,width='+width+',height='+height+',screenX='+leftval+',screenY='+topval+',scrollbars=yes');
	if (childWindow.opener == null) childWindow.opener = self;
	childWindow.focus();
}*/

//function submitForm() {
//	document.forms[0].submit();
//}

//function deleteAndSubmitForm(id) {
//	document.getElementById("del").value = id;
//	document.forms[0].submit();
//}

//function checkStatusAndSubmitForm (status_field_id) {
//    var check_status = false;
//	for ( var j = 0; j < document.getElementsByName(status_field_id).length; j++ ) {
//		if ( document.getElementsByName(status_field_id)[j].checked == true ) {
//			check_status = true;
//		}
//	}
//
//	if ( check_status ) {
//		submitForm();
//	} else {
//		alert("At least one option in the searchbar must be checked to perform search.");
//	}
//}  

function submitWithEnter(e) { 
	var characterCode
	try {
		if (e && e.which) { 
			e = e
			characterCode = e.which
		} else {
			e = event
			characterCode = e.keyCode
		}
		if(characterCode == 13) { 
			submitForm();
		}	else {
			return true
		}
	}
	catch (err) {
		return true;
	}
}

function disableFields (fields) {
	for (var i = 0; i < fields.length; i++) {
		document.getElementById(fields[i]).disabled = true;
	}
}

function disableAllFields () {
	var input_fields = document.getElementsByTagName('input');
	var textarea_fields = document.getElementsByTagName('textarea');
	var select_fields = document.getElementsByTagName('select');
	var button_fields = document.getElementsByTagName('button');

	var all_fields = new Array( input_fields, textarea_fields, select_fields, button_fields );
	
	for ( var j = 0; j < all_fields.length; j++ ) {
		for ( var i = 0; i < all_fields[j].length; i++ ) {
			all_fields[j][i].disabled = true;
		}
	}
}
/********* FOR LOCKING advisories ******************/
function releaseAndClose (set_to_pending) {
	if ( set_to_pending ) {
		setToPending(['pub_id', 'adv_id'], [refreshParent]);
	} else {
		releaseLock(['pub_id', 'adv_id'],[refreshParent]);
	}
	alert('The advisory ID has been removed from advisory.');	
	window.close();	
}
/****************************************************/

function setFontToOS ( fields ) {
	var os = navigator.platform.toLowerCase();
	var font = ( os.indexOf('win') != -1  ) ? 'courier new' : 'courier';
	
	for ( var i = 0; i < fields.length; i++ ) {
		try {
			document.getElementById(fields[i]).style.fontFamily = font;
		}
		catch (e) { }
	}
}

function changeStatus (status) {
	$('#change_status').val( status );
	document.forms[0].submit();	
}

function firstLetterToUpper (someText) {
	return someText.substr(0,1).toUpperCase() + someText.substr(1);
}
