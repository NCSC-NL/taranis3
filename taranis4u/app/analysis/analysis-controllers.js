'use strict';

define([
	'angular', 
	'app/analysis/analysis-services'
],function(ng){
	ng.module( 'analysis-controllers', ['analysis-services'])

	.controller( 'AnalysisCtrl', // parent controller 
		['$scope', '$stateParams', '$state',
		function( $scope, $stateParams, $state) {
			
			var analysisStatus,
				analysisRating,
				hasOwner,
				analysisCount;
			
			if ( $state.current.data.analysisCount ) {
				analysisCount = $state.current.data.analysisCount;
			} else if ( $scope.analysisCount ) {
				analysisCount = $scope.analysisCount;
			} else if ( $stateParams.count ) {
				analysisCount = $stateParams.count;
			}
			
			if ( $state.current.data.analysisRating ) {
				analysisRating = $state.current.data.analysisRating;
			} else if ( $scope.analysisRating ) {
				analysisRating = $scope.analysisRating;
			} else if ( $stateParams.rating ) {
				analysisRating = $stateParams.rating;
			}
	
			if ( $state.current.data.analysisStatus ) {
				analysisStatus = $state.current.data.analysisStatus;
			} else if ( $scope.analysisStatus ) {
				analysisStatus = $scope.analysisStatus;
			} else if ( $stateParams.status ) {
				analysisStatus = $stateParams.status;
			}
	
			if ( $state.current.data.hasOwner ) {
				hasOwner = $state.current.data.hasOwner;
			} else if ( $scope.hasOwner ) {
				hasOwner = $scope.hasOwner;
			} else if ( $stateParams.hasOwner ) {
				hasOwner = $stateParams.hasOwner;
			}
			
			return {
				analysisStatus: analysisStatus,
				analysisRating: analysisRating,
				hasOwner: hasOwner,
				analysisCount: analysisCount
			}
		}
	])	
	
	.controller('AnalysisListCtrl',[ 
		'$scope', 'Analysis', '$controller',
		 function( $scope, Analysis, $controller) {
	
			var analysisVars = $controller('AnalysisCtrl', {$scope: $scope});
			
			$scope.analyses = Analysis.query({
					status: analysisVars.analysisStatus,
					rating: analysisVars.analysisRating,
					count: analysisVars.analysisCount,
					has_owner: analysisVars.hasOwner
				},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('AnalysisDetailsCtrl',[ 
		'$rootScope', '$scope', '$stateParams', 'Analysis',
		 function( $rootScope, $scope, $stateParams, Analysis) {
			$scope.analysis = Analysis.get({ analysisId: $stateParams.analysisId },
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('AnalysesCountCtrl',[ 
		'$scope', 'Analysis', '$controller',
		 function( $scope, Analysis, $controller ) {
			
			var analysisVars = $controller('AnalysisCtrl', {$scope: $scope});
			
			$scope.analysesCount = Analysis.getTotal({
					status: analysisVars.analysisStatus,
					rating: analysisVars.analysisRating,
					has_owner: analysisVars.hasOwner
				},
				function () {}, // success
				function (response) {}// fail
			);
		}
	]);
});