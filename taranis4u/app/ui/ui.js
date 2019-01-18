define([
	'angular',
	'ui.router'
], function (ng) {
	'use strict';
	
	return ng.module('ui', [
		'ui.router'
	])
	.config( function ($stateProvider) {

		var stateNotFound = {
			name: 'notfound',
			url: '/notfound',
			templateUrl: 'app/ui/notfound.html',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};
		
		$stateProvider.state( stateNotFound );

	});
});