'use strict';

define([
	'angular', 
	'ngResource',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'assess-services', ['ngResource', 'auth-services'])
	
	.factory ( 'AssessItem', ['$resource', 'TokenHandler',
		function ( $resource, TokenHandler ) {
		
			var assessResource = $resource('/taranis4u/REST/assess/:assessId/:action', {}, {
				query: {
					method: 'GET',
					isArray: false,
					params: { count: '20' }
				},
				get: {
					method: 'GET',
					isArray: false,
					params: {}
				},
				getTotal: {
					method: 'GET',
					isArray: false,
					params: { action: 'total' }
				},
				getTagCloud: {
					method: 'GET',
					isArray: false,
					params: { action: 'tagcloud' }
				}
			});
			
			assessResource = TokenHandler.wrapActions( assessResource, ["query", "get", "getTotal", "getTagCloud"] );
			return assessResource;
		}
	]);	
});