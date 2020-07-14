'use strict';

define([
	'angular', 
	'app/announcement/announcement-services'
],function(ng){
	ng.module( 'announcement-controllers', ['announcement-services'])

	.controller( 'AnnouncementCtrl', // parent controller 
		['$scope', '$stateParams', '$state',
		function( $scope, $stateParams, $state) {
			
			var announcementCount,
				announcementType;
			
			if ( $state.current.data.announcementCount ) {
				announcementCount = $state.current.data.announcementCount;
			} else if ( $scope.announcementCount ) {
				announcementCount = $scope.announcementCount;
			} else if ( $stateParams.count ) {
				announcementCount = $stateParams.count;
			}
	
			if ( $state.current.data.announcementType ) {
				announcementType = $state.current.data.announcementType;
			} else if ( $scope.announcementType ) {
				announcementType = $scope.announcementType;
			} else if ( $stateParams.type ) {
				announcementType = $stateParams.type;
			}
			
			return {
				announcementType: announcementType,
				announcementCount: announcementCount
			}
		}
	])	
	
	.controller('AnnouncementListCtrl',[ 
		'$scope', 'Announcement', '$controller',
		function( $scope, Announcement, $controller ) {
	
			var announcementVars = $controller('AnnouncementCtrl', {$scope: $scope});
	
			$scope.announcements = Announcement.query({
					type: announcementVars.announcementType,
					count: announcementVars.announcementCount
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])	
	.controller('AnnouncementDetailsCtrl',[ 
		'$scope', '$stateParams', 'Announcement',
		function( $scope, $stateParams, Announcement) {
			$scope.announcement = Announcement.get({ announcementId: $stateParams.announcementId },
				function () {}, // success
				function (response) {} // fail
			);
		}
	]);
});