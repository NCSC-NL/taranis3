'use strict';

define([
	'angular',
	'jquery',
	'app/auth/auth-services'
],function(ng,$){
	ng.module( 'auth-controllers', ['auth-services'])

	.controller('LoginCtrl',[
		'$scope', '$state', 'Auth', 'TokenHandler', '$rootScope',
		 function( $scope, $state, Auth, TokenHandler, $rootScope ) {
			
			$('#login-username').focus();
			
			// login( username, password )
			$scope.login = function (username, password) {
				Auth.login(
					{
						username: username,
						password: password
					},
					function (response) {// success
						TokenHandler.set( response.access_token );
						$scope.$emit('loginChange');
						$rootScope.loginErrorMessage = '';
						$state.transitionTo('home');
					},
					function (response) { // fail
						$rootScope.loginErrorMessage = 'Login failure...';
					}
				);
			};
			// loginAsGuest()
			$scope.loginAsGuest = function () {
				Auth.login(
					{
						username: 'guest'
					},
					function (response) {  // success
						TokenHandler.set( response.access_token );
						$scope.$emit('loginChange');
						$rootScope.loginErrorMessage = '';
						$state.transitionTo('home');
					},
					function (response) { // fail
						$rootScope.loginErrorMessage = 'Log in failure...';
					}
				);
			};
		}
	])
	.controller('LogoutCtrl',[ 
		'$scope', '$state', 'Auth', 'TokenHandler', '$rootScope',
		 function( $scope, $state, Auth, TokenHandler, $rootScope ) {
			
			var logoutNow = function() {
				Auth.logout({},
					function (response) {// success
						TokenHandler.clear();
						$scope.$emit('loginChange');
						$state.transitionTo('home');
					},
					function (response) { // fail
						$scope.loginErrorMessage = 'Log out failure...';
					}
				);
			};
			
			logoutNow();
		}
	]);

});