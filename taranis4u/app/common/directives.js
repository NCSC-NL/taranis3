'use strict';

define([
	'angular',
//	'jquery',
	'jQCloud'
], function(ng){
	ng.module( 'directives', [])
	.directive( 'jqcloud', function () {
		return {
			// Restrict it to be an attribute in this case
			restrict: 'A',
			// responsible for registering DOM listeners as well as updating the DOM
			link: function(scope, element, attrs) {
				$(element).jQCloud( scope.$evalAsync( attrs.jqcloud ) );
			}
		};
	})
});