'use strict';

define([
	'angular', 
	'app/endofshift/endofshift-services'
],function(ng){
	ng.module( 'endofshift-controllers', ['endofshift-services'])

	.controller('EndOfShiftDetailsCtrl',[ 
		'$scope', '$stateParams', 'EndOfShift',
		function( $scope, $stateParams, EndOfShift) {
			$scope.endOfShift = EndOfShift.get({ endofshiftId: $stateParams.endofshiftId },
				function () {}, // success
				function (response) {} // fail
			);
		}
	])
	.controller('EndOfShiftStatusCtrl',[
		'$scope', 'EndOfShift',
		function( $scope, EndOfShift ) {
	
			$scope.endOfShiftStatus = EndOfShift.getStatus(
				{},
				function () {}, // success
				function (response) {} // fail
			);
		}
	])	
});