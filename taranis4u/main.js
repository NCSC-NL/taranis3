require.config({
	paths: {
		'angular':		'/lib/angular/angular',
		'ngResource':	'/lib/angular/angular-resource',
		'ngAnimate':	'/lib/angular/angular-animate',
		'ui.router':	'/lib/angular-ui-router',
		'domReady':		'/lib/requirejs-domready/domReady',
		'jquery':		'/lib/jquery/jquery',
		'jQCloud':		'/lib/jqcloud/jqcloud',
		'angular-loading-bar':	'/lib/loading-bar/loading-bar'
	},

	// angular does not support AMD out of the box, put it in a shim
	shim: {
		'angular': {
			exports: 'angular'
		},
		'ngResource':	['angular'],
		'ngAnimate':	['angular'],
		'ui.router':	['angular'],
		'jQCloud':		['jquery'],
		'angular-loading-bar':	['angular']
	},
	
	// kick start application
	deps: ['bootstrap']
});