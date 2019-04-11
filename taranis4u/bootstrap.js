define([
	'require',
	'angular',
	'ui.router',
	'app/app'
], function (require, ng) {
	'use strict';

	require(['domReady!'], function (document) {
		ng.bootstrap(document, ['app']);
	});
});