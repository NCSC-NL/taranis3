define([
	'angular',
	'ui.router',
	'app/assess/assess-controllers',
	'app/analysis/analysis-controllers',
	'app/advisory/advisory-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('numbers-overview', [
		'ui.router',
		'assess-controllers',
		'analysis-controllers',
		'advisory-controllers'
	])
	.config( function ($stateProvider) {

		var numbersOverviewState = {
			name: 'It\'s all about numbers',
			url: '/numbers',
			data: {
				isMenuItem: true,
				reloadPage: true
			},
			templateUrl: 'app/mashups/numbers_overview.html'
		};
		
		$stateProvider.state( numbersOverviewState );

	});
});


