'use strict';

define([
	'angular', 
	'ngResource',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'advisory-services', ['ngResource', 'auth-services'])
	
	.factory ( 'Advisory', ['$resource', 'TokenHandler',
		function ($resource, TokenHandler) {
		
			var advisoryResource = $resource('/taranis4u/REST/advisories/:advisoryId/:total', {}, {
				query: {
					method: 'GET',
					isArray: false,
					params: { status: 'published', count: '20' }
				},
				get: {
					method: 'GET',
					isArray: false,
					params: {}
				},
				getTotal: {
					method: 'GET',
					isArray: false,
					params: { total: 'total' }
				}
			});
			
			advisoryResource = TokenHandler.wrapActions( advisoryResource, ["query", "get", "getTotal"] );
			return advisoryResource;
		}
	]);
});