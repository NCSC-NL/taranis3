define([
	'angular',
	'ngAnimate',
	'ui.router',
	'angular-loading-bar',
	'app/landingpage-controller',
	'app/common/filters',
	'app/ui/ui-controllers',
	'app/modules'
], function (ng) {
	'use strict';
	
	return ng.module('app', [
		'ui.router',
		'landingpage',
		'filters',
		'ngAnimate',
		'ui-controllers',
		'modules',
		'angular-loading-bar'
	])
	.config( function ($stateProvider, $urlRouterProvider) {
		
		$urlRouterProvider.otherwise('/');
		
		$stateProvider
			.state( 'home', {
				url: '/',
				templateUrl: 'app/landingpage.html',
				controller: 'LandingpageCtrl',
				data: {
					isMenuItem: false,
					reloadPage: false
				},
			})

			// layouts
			.state( 'one row', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-one-row.html',
			})
			.state( 'two rows', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-two-rows.html',
			})
			.state( 'three rows', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-three-rows.html',
			})
			.state( 'two by two', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-two-by-two.html',
			})
			.state( 'two by three', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-two-by-three.html',
			})
			.state( 'two columns', {
				abstract: true,
				templateUrl: 'assets/layouts/layout-two-columns.html',
			});
	})
	.config([
		'$httpProvider',
		function ($httpProvider) {
			
			var interceptor = ['$location', '$q', '$injector', function($location, $q, $injector) {
				function success(response) {
					return response;
				}
	
				function error(response) {
	
					if(response.status === 401) {
						sessionStorage.clear();
						$injector.get('$state').transitionTo('home');
						return $q.reject(response);
					} else {
						return $q.reject(response);
					}
				}
	
				return function(promise) {
					return promise.then(success, error);
				}
			}];
	
			$httpProvider.responseInterceptors.push(interceptor);
		}
	])
});