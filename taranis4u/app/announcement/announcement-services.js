'use strict';

define([
	'angular', 
	'ngResource',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'announcement-services', ['ngResource', 'auth-services'])
	
	.factory ( 'Announcement', ['$resource', 'TokenHandler',
		function ($resource, TokenHandler) {
		
			var announcementResource = $resource('/taranis4u/REST/announcements/:announcementId', {}, {
				query: {
					method: 'GET',
					isArray: false,
					params: { count: '20' }
				},
				get: {
					method: 'GET',
					isArray: false,
					params: {}
				}
			});
			
			announcementResource = TokenHandler.wrapActions( announcementResource, ["query", "get"] );
			return announcementResource;
		}
	]);
});