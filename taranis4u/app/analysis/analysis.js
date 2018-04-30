define([
	'angular',
	'ui.router',
	'app/analysis/analysis-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('analysis', [
		'ui.router',
		'analysis-controllers'
	])
	.config( function ($stateProvider) {

		var analysisDetailsState = {
			name: 'analyses',
			url: '/analyses/{analysisId}',
			templateUrl: 'app/analysis/analysis_details.html',
			controller: 'AnalysisDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};

		var pendingAnalyses = {
			name: 'Pending Analyses',
			parent: 'two rows',
			url: '/pendinganalyses',
			data: {
				isMenuItem: true,
				reloadPage: true,
				analysisStatus: 'pending'
			},
			views: {
				'page-title@': {
					template: 'Pending Analyses'
				},
				'row1': {
					templateUrl: 'app/analysis/analysis_count.html',
					controller: 'AnalysesCountCtrl'
				},
				'row2': {
					templateUrl: 'app/analysis/analyses_table.html',
					controller: 'AnalysisListCtrl'
				}
			}
		};
		
		$stateProvider.state( analysisDetailsState );
		$stateProvider.state( pendingAnalyses );

	});
});