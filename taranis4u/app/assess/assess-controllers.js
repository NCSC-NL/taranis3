'use strict';

define([
	'angular',
	'jquery',
	'jQCloud',
	'app/assess/assess-services'
],function(ng, $){
	ng.module( 'assess-controllers', ['assess-services'])
	
	.controller( 'AssessCtrl', // parent controller 
		['$scope', '$stateParams', '$state',
		function( $scope, $stateParams, $state) {
			
			var assessStatus,
				assessCategory,
				assessCount,
				assessSearch;

			if ( $stateParams.count !== undefined ) {
				assessCount = $stateParams.count;
			} else if ( $state.current.data.assessCount !== undefined ) {
				assessCount = $state.current.data.assessCount;
			} else if ( $scope.assessCount !== undefined ) {
				assessCount = $scope.assessCount;
			}
			
			if ( $stateParams.status ) {
				assessStatus = $stateParams.status;
			} else if ( $state.current.data.assessStatus ) {
				assessStatus = $state.current.data.assessStatus;
			} else if ( $scope.assessStatus ) {
				assessStatus = $scope.assessStatus;
			}
			
			if ( $stateParams.category && $stateParams.category.indexOf(':') != 0 ) {
				assessCategory = $stateParams.category;
			} else if ( $state.current.data.assessCategory ) {
				assessCategory = $state.current.data.assessCategory;
			} else if ( $scope.assessCategory ) {
				assessCategory = $scope.assessCategory;
			}
			if ( $stateParams.search ) {
				assessSearch = $stateParams.search;
			} else if ( $state.current.data.assessSearch ) {
				assessSearch = $state.current.data.assessSearch;
			} else if ( $scope.assessSearch ) {
				assessSearch = $scope.assessSearch;
			}
			
			return {
				assessStatus: assessStatus, 
				assessCategory: assessCategory,
				assessCount: assessCount,
				assessSearch: assessSearch
			}
		}
	])
	
	.controller('AssessItemListCtrl',[ 
		'$scope', 'AssessItem', '$controller',
		function( $scope, AssessItem, $controller) {
			
			var assessVars = $controller('AssessCtrl', {$scope: $scope});

			$scope.assessItems = AssessItem.query({
					status: assessVars.assessStatus,
					category: assessVars.assessCategory,
					count: assessVars.assessCount,
					search: assessVars.assessSearch
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('AssessItemDetailsCtrl',[
		'$scope', '$stateParams', 'AssessItem',
		 function( $scope, $stateParams, AssessItem) {
			$scope.assessItem = AssessItem.get({ assessId: $stateParams.assessId },
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('AssessItemsCountCtrl',[ 
		'$scope', 'AssessItem', '$controller',
		 function( $scope, AssessItem, $controller ) {
			
			var assessVars = $controller('AssessCtrl', {$scope: $scope});
			
			$scope.assessCount = AssessItem.getTotal({
					status: assessVars.assessStatus,
					category: assessVars.assessCategory,
					search: assessVars.assessSearch
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	
	.controller('AssessTagCloudCtrl', 
		['$scope', 'AssessItem', '$controller',
		function ($scope, AssessItem, $controller ) {
		
			var assessVars = $controller('AssessCtrl', {$scope: $scope});
			
			$scope.tagCloud = AssessItem.getTagCloud({
					status: assessVars.assessStatus,
					category: assessVars.assessCategory,
					search: assessVars.assessSearch
				},
				function (response, header) {
					$('#assess-tag-cloud').jQCloud(response.list, { delayedMode: true, removeOverflowing: false });
				}, // success
				function (response) {} // fail
			);
		}
	]);
	
});