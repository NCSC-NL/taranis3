define([
	'angular',
	'ui.router',
	'app/endofshift/endofshift-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('endofshift', [
		'ui.router',
		'endofshift-controllers'
	])
	.config( function ($stateProvider) {
		
		var endOfShiftDetailsState = {
			name: 'endofshift',
			url: '/endofshift/lastsent',
			templateUrl: 'app/endofshift/endofshift_details.html',
			controller: 'EndOfShiftDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};
		
		var endOfShiftStatus = {
			name: 'End-Of-Shift Status',
			url: '/endofshift/status',
			templateUrl: 'app/endofshift/endofshift_status.html',
			controller: 'EndOfShiftStatusCtrl',
			data: {
				isMenuItem: true,
				reloadPage: true
			}
		}
		
		$stateProvider.state( endOfShiftDetailsState );
		$stateProvider.state( endOfShiftStatus );
	})
});