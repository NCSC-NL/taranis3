'use strict';

define([
	'angular'
],function(ng){
	ng.module( 'filters', [])
	
	.filter('substring', function() {
		return function(str, start, end) {
			if ( str != '' && str !== undefined ) {
				return str.substring(start, end);
			} else {
				return '';
			}
		};
	})
	
	.filter('date_from_unix_time', function (){
		return function(time) {
			if ( ng.isNumber( time ) ) {
				var date = new Date(time*1000);
				return date.getDate() + '-' + date.getMonth() + '-' + date.getFullYear();
			} else {
				return '';
			}
		}
	})
	
	.filter('round', function (){
		return function(number) {
			if ( ng.isNumber( number ) ) {
				return Math.round( number * 10 ) / 10;
			} else {
				return '';
			}
		}
	});
});