'use strict';

define([
	'angular', 
	'app/ui/ui-services',
	'app/auth/auth-services'
],function(ng){
	ng.module( 'ui-controllers', ['ui-services', 'auth-services'])
	.controller('MainCtrl',[
		'$scope', '$interval', '$state', '$stateParams', 'TokenHandler', 'ColorScheme', '$location', 'Counter', 'Stream',
		 function( $scope, $interval, $state, $stateParams, TokenHandler, ColorScheme, $location, Counter, Stream ) {
	
			var reloadingSeconds = 30, // will be made configurable
				pageReloadingInterval,
				counterInterval,
				streamInterval;
	
			var stopInterval = function (interval) {
				if ( angular.isDefined( interval ) ) {
					$interval.cancel( interval );
				}
				return undefined;
			}
			var stopReloading = function () {
				pageReloadingInterval = stopInterval( pageReloadingInterval );
				counterInterval = stopInterval( counterInterval );
				$scope.counterBlock = Counter.draw( '' );
			}
	
			var stopStream = function () {
				streamInterval = stopInterval( streamInterval );
				counterInterval = stopInterval( counterInterval );
				$scope.counterBlock = Counter.draw( '' );
				Stream.isRunning = false;
			}
			
			// draw a counter bar with one block less each second
			var startCounter = function (seconds) {
				var countDown = seconds;
				if ( angular.isUndefined( counterInterval ) ) {
					counterInterval = $interval( function () {
						if ( countDown == 0 ) {
							countDown = seconds
						}
						countDown = countDown - 1;
						$scope.counterBlock = Counter.draw( countDown );
					}, 1000);
				}
			}
	
			// listerner for page (state) change/reload
			$scope.$on('$stateChangeSuccess', function ( event, toState, toParams, fromState, fromParams ) {

				if ( Stream.isRunning ) {
					if ( toState && !Stream.isDisplayPartOfStream( toState.name ) && toState.name != 'notfound' ) {
						stopStream();
					} else if ( angular.isUndefined( streamInterval ) ) {
						$scope.counterBlock = Counter.draw( Stream.currentDisplay );
						
						streamInterval = $interval( function () {
							startCounter( Stream.transition_time );
							Stream.next();
							
							var stateParameters = ( Stream.params != null ) ? Stream.params : $stateParams;

							$state.go( Stream.currentDisplay, stateParameters, {reload: true} );
							
						}, Stream.transition_time * 1000);
						
						startCounter( Stream.transition_time );

						if ( /^\//.test( Stream.currentDisplay ) ) {
							Stream.setParamsAndNameFromURL( Stream.currentDisplay );
						}
						var stateParameters = ( Stream.params != null ) ? Stream.params : $stateParams;
						$state.transitionTo( Stream.currentDisplay, stateParameters ); // go to first display
					}
					
				} else if ( $state.current.data.reloadPage ) {
	
					$scope.counterBlock = Counter.draw( reloadingSeconds ); // draw a full counter bar
					
					if ( angular.isUndefined( pageReloadingInterval ) ) {
						// start page reloading
						pageReloadingInterval = $interval( function () {
							startCounter( reloadingSeconds );
							$state.transitionTo( $state.current, $stateParams, {reload: true} );
						}, reloadingSeconds * 1000);
						
						startCounter( reloadingSeconds );
					}
				} else {
					// stop page reloading
					stopReloading();
				}
			});
	
			$scope.$on('$stateNotFound', function ( event, toState, toParams, fromState, fromParams ) {
				event.preventDefault();
				$state.go('notfound');
			});
			
			$scope.$on('$destroy', function() {
				// on destroy all intervals should be cancelled
				stopReloading();
			});
			
			// listener for login change event; should be fired after login/logout
			$scope.$on('loginChange', function () {
				$scope.hasToken = TokenHandler.hasToken();
			});
			
			// listener for color scheme change; should be fired when selecting a color on the right panel
			$scope.$on('colorSchemeChange', function () {
				$scope.selectedColorScheme = ColorScheme.getSelectedScheme();
			});
			
			$scope.selectedColorScheme = ColorScheme.getSelectedScheme();
			
			// if token is set in URL, the side panel is not available
			if ( typeof ($location.search()).token == 'string' ) {
				TokenHandler.set( ($location.search()).token );
				$scope.hasToken = false;
			} else {
				$scope.hasToken = TokenHandler.hasToken();
			}
		}
	])
	.controller('ColorSchemesCtrl',[
		'$scope', 'ColorScheme',
		 function( $scope, ColorScheme ) {
			$scope.schemes = ColorScheme.get();
			
			$scope.setScheme = function (bgColorName, fontColorName) {
				ColorScheme.set( bgColorName, fontColorName );
				$scope.$emit('colorSchemeChange');
			}
		}
	]);

});