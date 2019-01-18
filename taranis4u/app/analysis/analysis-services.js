'use strict';

define([
	'angular', 
	'ngResource',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'analysis-services', ['ngResource', 'auth-services'])
	
	.factory ( 'Analysis', ['$resource', 'TokenHandler',
		function ( $resource, TokenHandler ) {
		
			var analysisResource = $resource('/taranis4u/REST/analyses/:analysisId/:total', {}, {
				query: {
					method: 'GET',
					isArray: false,
					params: {}
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
			
			analysisResource = TokenHandler.wrapActions( analysisResource, ["query", "get", "getTotal"] );
			return analysisResource;
		}
	]);
});