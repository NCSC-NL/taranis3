define([
	'angular',
	'app/auth/auth',
	'app/ui/ui',
	'app/advisory/advisory',
	'app/endofshift/endofshift',
	'app/assess/assess',
	'app/analysis/analysis',
	'app/mashups/numbers-overview',
	'app/announcement/announcement'
], function (ng) {
	'use strict';
	
	return ng.module('modules', [
		'auth',
		'ui',
		'advisory',
		'endofshift',
		'assess',
		'analysis',
		'numbers-overview',
		'announcement'
	]);
});