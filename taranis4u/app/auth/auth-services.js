'use strict';

define([
	'angular', 
	'ngResource'
], function(ng){
	ng.module( 'auth-services', ['ngResource'])
	
	.factory('Auth', ['$resource', 'TokenHandler',
		function ( $resource, tokenHandler ) {
			var auth = $resource('/taranis4u/REST/auth/', {}, {
				login: {
					method: 'POST',
					isArray: false
				},
				logout: {
					method: 'POST',
					isArray: false
				}
			});
			
			auth = tokenHandler.wrapActions( auth, ["logout"] );
			return auth;
		}
	])
	
	// source http://nils-blum-oeste.net/angularjs-send-auth-token-with-every--request/
	.factory ( 'TokenHandler',	function () {
		var tokenHandler = {};
		var token = "none";
	
		tokenHandler.set = function ( newToken ) {
			token = newToken;
			sessionStorage.setItem('token', newToken);
		};
	
		tokenHandler.get = function () {
			if ( token != "none" ) {
				return token;
			} else if ( sessionStorage.length != 0 ) {
				return sessionStorage.getItem('token');
			} else {
				return "none";
			}
		};
	
		tokenHandler.hasToken = function () {
			return ( sessionStorage.token !== undefined );
		}
	
		tokenHandler.clear = function () {
			sessionStorage.clear();
			token = "none";
		}
		
		// wrap given actions of a resource to send auth token with every request
		tokenHandler.wrapActions = function ( resource, actions ) {
			// copy original resource
			var wrappedResource = resource;
			for (var i=0; i < actions.length; i++) {
				tokenWrapper( wrappedResource, actions[i] );
			};
			// return modified copy of resource
			return wrappedResource;
		};
	
		// wraps resource action to send request with auth token
		var tokenWrapper = function ( resource, action ) {
			// copy original action
			resource['_' + action]  = resource[action];
			// create new action wrapping the original and sending token
			resource[action] = function ( data, success, error ) {
				return resource['_' + action](
						angular.extend({}, data || {}, {access_token: tokenHandler.get()}),
						success,
						error
				);
			};
		};
	
		return tokenHandler;
	});	
	
});