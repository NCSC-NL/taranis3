'use strict';

define([
	'angular',
	'app/auth/auth-services'
], function(ng){
	ng.module( 'landingpage', ['auth-services'])
	.controller('LandingpageCtrl',[
		'$scope', '$state', 'TokenHandler', 'StreamLoader', 'Stream',
		 function( $scope, $state, TokenHandler, StreamLoader, Stream ) {
	
			var menuItems = new Array();
			angular.forEach( $state.get(), function( myState ){
				if ( !myState.abstract && myState.data.isMenuItem ) {
					menuItems.push( { name: myState.name, url: myState.url } );
				}
			});
				
			$scope.menuItems = menuItems;

			$scope.startStream = function (strm) {
				Stream.set(strm);
				$scope.$emit('$stateChangeSuccess');
			}
		
			// do request displays
			if ( TokenHandler.hasToken() === true ) {
				var menuItems = new Array();
				angular.forEach( $state.get(), function( myState ){
					if ( !myState.abstract && myState.data.isMenuItem ) {
						menuItems.push( { name: myState.name, url: myState.url } );
					}
				});
				
				$scope.menuItems = menuItems;
				
				$scope.streams = StreamLoader.query(
					{},
					function () {}, // success
					function (response) { // fail
					}
				);
			} else {
				$state.transitionTo( 'login' );
			}
		}
	]);
});