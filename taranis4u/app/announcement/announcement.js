define([
	'angular',
	'ui.router',
	'app/announcement/announcement-controllers'
], function (ng) {
	'use strict';
	
	return ng.module('announcement', [
		'ui.router',
		'announcement-controllers'
	])
	.config( function ($stateProvider) {

		var todoListsState = {
			name: 'To-do Lists',
			parent: 'one row',
			url: '/todolists',
			data: {
				isMenuItem: true,
				reloadPage: true,
				announcementType: 'todo-list'
			},
			views: {
				'page-title@': {
					template: 'To-do Lists'
				},
				'row1': {
					templateUrl: 'app/announcement/todolists.html',
					controller: 'AnnouncementListCtrl'
				}
			}
		};

		var todoListDetailsState = {
			name: 'todo',
			url: '/todo/{announcementId}',
			templateUrl: 'app/announcement/todo_details.html',
			controller: 'AnnouncementDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: true
			}
		};
		
		var bulletListsState = {
			name: 'Lists',
			parent: 'one row',
			url: '/lists',
			data: {
				isMenuItem: true,
				reloadPage: true,
				announcementType: 'bullet-list'
			},
			views: {
				'page-title@': {
					template: 'Lists'
				},
				'row1': {
					templateUrl: 'app/announcement/lists.html',
					controller: 'AnnouncementListCtrl'
				}
			}
		};

		var bulletListDetailsState = {
			name: 'list',
			url: '/list/{announcementId}',
			templateUrl: 'app/announcement/list_details.html',
			controller: 'AnnouncementDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};

		var announcementsState = {
			name: 'Announcements',
			parent: 'one row',
			url: '/announcements',
			data: {
				isMenuItem: true,
				reloadPage: true,
				announcementType: 'freeform-text'
			},
			views: {
				'page-title@': {
					template: 'Announcements'
				},
				'row1': {
					templateUrl: 'app/announcement/announcements_w_description.html',
					controller: 'AnnouncementListCtrl'
				}
			}
		};
		
		var announcementDetailsState = {
			name: 'announcement',
			url: '/announcement/{announcementId}',
			templateUrl: 'app/announcement/announcement_details.html',
			controller: 'AnnouncementDetailsCtrl',
			data: {
				isMenuItem: false,
				reloadPage: false
			}
		};
		
		$stateProvider.state( todoListsState );
		$stateProvider.state( todoListDetailsState );
		$stateProvider.state( bulletListsState );
		$stateProvider.state( bulletListDetailsState );
		$stateProvider.state( announcementsState );
		$stateProvider.state( announcementDetailsState );
		
	});
});