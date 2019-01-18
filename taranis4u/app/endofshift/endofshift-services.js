'use strict';

define([
	'angular', 
	'ngResource',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'endofshift-services', ['ngResource', 'auth-services'])
	
	.factory ( 'EndOfShift', ['$resource', 'TokenHandler',
		function ($resource, TokenHandler) {
		
			var endofshiftResource = $resource('/taranis4u/REST/endofshift/:action', {}, {
				get: {
					method: 'GET',
					isArray: false,
					params: { action: 'lastsent'}
				},
				getStatus: {
					method: 'GET',
					isArray: false,
					params: { action: 'status' }
				}
			});
			
			endofshiftResource = TokenHandler.wrapActions( endofshiftResource, ["get", "getStatus"] );
			return endofshiftResource;
		}
	]);
});