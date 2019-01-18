'use strict';

define([
	'angular', 
	'app/advisory/advisory-services'
],function(ng){
	ng.module( 'advisory-controllers', ['advisory-services'])

	.controller( 'AdvisoryCtrl', // parent controller 
		['$scope', '$stateParams', '$state',
		function( $scope, $stateParams, $state) {
			
			var advisoryCount,
				advisoryStatus;
			
			if ( $state.current.data.advisoryCount ) {
				advisoryCount = $state.current.data.advisoryCount;
			} else if ( $scope.advisoryCount ) {
				advisoryCount = $scope.advisoryCount;
			} else if ( $stateParams.count ) {
				advisoryCount = $stateParams.count;
			}
	
			if ( $state.current.data.advisoryStatus ) {
				advisoryStatus = $state.current.data.advisoryStatus;
			} else if ( $scope.advisoryStatus ) {
				advisoryStatus = $scope.advisoryStatus;
			} else if ( $stateParams.status ) {
				advisoryStatus = $stateParams.status;
			}
			
			return {
				advisoryStatus: advisoryStatus, 
				advisoryCount: advisoryCount
			}
		}
	])	
	
	.controller('AdvisoryListCtrl',[ 
		'$scope', 'Advisory', '$controller',
		function( $scope, Advisory, $controller ) {
	
			var advisoryVars = $controller('AdvisoryCtrl', {$scope: $scope});
	
			$scope.advisories = Advisory.query({
					status: advisoryVars.advisoryStatus,
					count: advisoryVars.advisoryCount
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])	
	.controller('AdvisoryDetailsCtrl',[ 
		'$scope', '$stateParams', 'Advisory',
		function( $scope, $stateParams, Advisory) {
			$scope.advisory = Advisory.get({ advisoryId: $stateParams.advisoryId },
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('AdvisoryCountCtrl',[ 
		'$scope', 'Advisory', '$controller',
		function( $scope, Advisory, $controller ) {
	
			var advisoryVars = $controller('AdvisoryCtrl', {$scope: $scope});
	
			$scope.advisoryCount = Advisory.getTotal({
					status: advisoryVars.advisoryStatus
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])	
});