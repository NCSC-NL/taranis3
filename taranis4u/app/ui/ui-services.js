'use strict';

define([
	'angular',
	'app/auth/auth-services'
], function(ng){
		ng.module( 'ui-services', ['auth-services', 'ui.router'])

		// ColorScheme
		.factory ( 'ColorScheme', ['$http', '$location',
			function ( $http, $location ) {
				var colorScheme = {};
				
				colorScheme.get = function () {
					var schemes = {};
					$http.get('/app/ui/color-schemes.json').success(function(data) {
						schemes.list = data;
					});
					return schemes;
				}
				
				colorScheme.set = function (bgColorName, fontColorName) {
					sessionStorage.setItem('colorScheme', bgColorName + '-' + fontColorName);
				};
				
				colorScheme.getSelectedScheme = function () {
					var defaultColorScheme = ( typeof ($location.search()).color == 'string' ) ? ($location.search()).color : 'black-red';
					var selectedScheme = ( sessionStorage.getItem('colorScheme') ) ? sessionStorage.getItem('colorScheme') : defaultColorScheme;
					return selectedScheme;
				}
				
				return colorScheme;
			}
		])
		
		// Counter
		.factory ( 'Counter', function () {
			var counter = {};
			
			counter.draw = function (seconds) {
//				counter.blocks = '';
//				for ( var i = 0; i < seconds; i++ ) {
//					counter.blocks += '_';
//				}
//				return counter.blocks;
				return seconds;
			}
			
			return counter;
		})
		
		// StreamLoader
		.factory ( 'StreamLoader', ['$resource', 'TokenHandler',
			function ( $resource, tokenHandler ) {
		
				var streamLoaderResource = $resource('/taranis4u/REST/streams/:streamId', {}, {
					query: {
						method: 'GET',
						isArray: false,
						params: { count: '20' }
					},
					get: {
						method: 'GET',
						isArray: false,
						params: { streamId: 'streams' }
					}
				});
				
				streamLoaderResource = tokenHandler.wrapActions( streamLoaderResource, ["query", "get"] );
				return streamLoaderResource;
			}
		])

		// Stream
		.factory ( 'Stream', [ '$state', '$urlMatcherFactory', function ($state, $urlMatcherFactory) {
			var stream = {};
			
			stream.set = function (strm) {
				stream.currentDisplayNumber = 0;
				stream.currentDisplay = strm.displays[0];
				stream.description = strm.description;
				stream.transition_time = strm.transition_time;
				stream.displays = strm.displays;
				stream.isRunning = true;
				stream.params = null
			}
			
			stream.next = function () {
				
				stream.currentDisplayNumber = ( stream.currentDisplayNumber == ( stream.displays.length - 1 ) )
					? 0 
					: stream.currentDisplayNumber + 1;
				
				if ( /^\//.test( stream.displays[stream.currentDisplayNumber] ) ) {
					stream.setParamsAndNameFromURL( stream.displays[stream.currentDisplayNumber] );
				} else {
					stream.params = null;
					stream.currentDisplay = stream.displays[stream.currentDisplayNumber];
				}
			}
			
			stream.isDisplayPartOfStream = function (display) {
				var isInDisplayList = false;
				if ( !Array.prototype.indexOf ) { // for IE < 9
					
					angular.forEach( stream.displays, function( dp ){
						if ( dp == display ) {
							isInDisplayList = true;
						} else {
							var myState = $state.get( display );
							var matcher = $urlMatcherFactory.compile( myState.url );
							if ( matcher.exec( dp ) ) {
								isInDisplayList = true;
							}
						}
					});
					
				} else {
					
					if ( stream.displays.indexOf(display) != -1 ) {
						isInDisplayList = true;
					} else {
						var myState = $state.get( display );
						var matcher = $urlMatcherFactory.compile( myState.url );
						angular.forEach( stream.displays, function( dp ){
							if ( matcher.exec( dp ) ) {
								isInDisplayList = true;
							}
						});
					}
				}
				
				return isInDisplayList;
			}
			
			// helper function
			stream.setParamsAndNameFromURL = function ( url ) {
				angular.forEach( $state.get(), function( myState ){
					if ( myState.url ) {
						var matcher = $urlMatcherFactory.compile( myState.url );
						var params = matcher.exec( stream.displays[stream.currentDisplayNumber] );
						if ( params != null ) {
							stream.params = params
							stream.currentDisplay = myState.name;
						}
					}
				});
			}
			
			return stream;
		}]);
});