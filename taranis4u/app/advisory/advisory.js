define([
	'angular',
	'ui.router',
	'app/advisory/advisory-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('advisory', [
		'ui.router',
		'advisory-controllers'
	])
	.config( function ($stateProvider) {
		
		var advisoryDetailsState = {
			name: 'advisories',
			url: '/advisories/{advisoryId}',
			templateUrl: 'app/advisory/advisory_details.html',
			controller: 'AdvisoryDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};
		
		var readyforreviewAdvisoriesState = {
			name: 'Advisories Ready For Review',
			parent: 'one row',
			url: '/readyforreview',
			data: {
				isMenuItem: true,
				reloadPage: true,
				advisoryCount: 10,
				advisoryStatus: 'ready4review'
			},
			views: {
				'page-title@': {
					template: 'Advisories Ready For Review'
				},
				'row1': {
					templateUrl: 'app/advisory/advisories.html',
					controller: 'AdvisoryListCtrl'
				}
			}
		};

		var pendingAdvisories = {
			name: 'Pending Advisories',
			parent: 'two rows',
			url: '/pendingadvisories',
			data: {
				isMenuItem: true,
				reloadPage: true,
				advisoryStatus: 'pending'
			},
			views: {
				'page-title@': {
					template: 'Pending Advisories'
				},
				'row1': {
					templateUrl: 'app/advisory/advisory_count.html',
					controller: 'AdvisoryCountCtrl'
				},
				'row2': {
					templateUrl: 'app/advisory/advisories_table.html',
					controller: 'AdvisoryListCtrl'
				}
			}
		};
		
		$stateProvider.state( advisoryDetailsState );
		$stateProvider.state( readyforreviewAdvisoriesState );
		$stateProvider.state( pendingAdvisories );
	})
});