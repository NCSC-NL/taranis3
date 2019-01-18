define([
	'angular',
	'ui.router',
	'app/assess/assess-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('assess', [
		'ui.router',
		'assess-controllers'
	])
	.config( function ($stateProvider) {
		
		var latestHeadlinesState = {
			name: 'Latest Headlines',
			parent: 'one row',
			url: '/latestheadlines/:category',
			data: {
				isMenuItem: true,
				reloadPage: true,
				assessCount: 15,
				assessCategory: 'news'
			},
			views: {
				'page-title@': {
					template: 'Latest Headlines'
				},
				'row1': {
					templateUrl: 'app/assess/assess_items_title.html',
					controller: 'AssessItemListCtrl'
				}
			}
		};
		
		var linkedToAnalysisState = {
			name: 'News in waitingroom',
			parent: 'one row',
			url: '/linkedtoanalysis',
			data: {
				isMenuItem: true,
				reloadPage: true,
				assessCount: 13,
				assessStatus: 'waitingroom'
			},
			views: {
				'page-title@': {
					template: 'News in waitingroom'
				},
				'row1': {
					templateUrl: 'app/assess/assess_items_title.html',
					controller: 'AssessItemListCtrl'
				}
			}
		};
		
		var assessTagCloud = {
			name: 'Assess News TagCloud',
			parent: 'one row',
			url: '/assesstagcloud',
			data: {
				isMenuItem: true,
				reloadPage: true,
				assessCategory: 'news'
			},
			views: {
				'page-title@': {
					template: 'Assess News Tag Cloud'
				},
				'row1': {
					templateUrl: 'app/assess/assess_tagcloud.html',
					controller: 'AssessTagCloudCtrl'
				}
			}
		};

//		var searchSomething = {
//			name: '... in het nieuws',
//			parent: 'one row',
//			url: '/searchSomething',
//			data: {
//				isMenuItem: true,
//				reloadPage: true,
//				assessCount: 15,
//				assessSearch: '...',
//				assessCategory: 'news',
//			},
//			views: {
//				'page-title@': {
//					template: '... in het nieuws'
//				},
//				'row1': {
//					templateUrl: 'app/assess/assess_items_title.html',
//					controller: 'AssessItemListCtrl'
//				}
//			}
//		};
		
		$stateProvider.state( latestHeadlinesState );
		$stateProvider.state( linkedToAnalysisState );
		$stateProvider.state( assessTagCloud );
//		$stateProvider.state( searchSomething );
	});
});