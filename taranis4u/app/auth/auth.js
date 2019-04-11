define([
	'angular',
	'ui.router',
	'app/auth/auth-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('auth', [
		'ui.router',
		'auth-controllers'
	])
	.config( function ($stateProvider) {

		var loginState = {
			name: 'login',
			url: '/login',
			templateUrl: 'app/auth/login.html',
			controller: 'LoginCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			},
		};
		
		var logoutState = {
			name: 'logout',
			url: '/logout',
			template: '<div>logging out...</div>',
			controller: 'LogoutCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			},
		};
		
		$stateProvider.state( loginState );
		$stateProvider.state( logoutState );
	})
});