/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function oneUp () {
	$('<img>')
		.attr({
			src : $.main.webroot + '/images/super_mario_mushroom_one_up.png'
		})
		.css({
			position: 'fixed',
			top: screen.height / 2 + 'px',
			left: screen.width / 2 + 'px'
		})
		.appendTo('body')
		.animate({'top': '200px', 'opacity' : '0'}, 1000);
}
