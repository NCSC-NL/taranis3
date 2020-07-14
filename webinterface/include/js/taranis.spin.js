/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

// TaranisSpinner: thin wrapper around the Spinner library (for displaying a spinning 'loading' icon).

function TaranisSpinner() {
	"use strict";

	this.spinner = new Spinner({
	  lines: 13,
	  length: 14,
	  width: 7,
	  radius: 21,
	  corners: 1,
	  opacity: 0,
	  zIndex: 2e9,
	  top: '80px',
	});

	/*
	Keep a "stack" of spinner requests so that start()/stop() calls can be nested.
	Callers should be able to call start() and stop() without worrying that they might get in another caller's way.

	For example:

		var taranisSpinner = new TaranisSpinner();
		function a() {
			taranisSpinner.start();
			b();
			taranisSpinner.stop();
		}
		function b() {
			taranisSpinner.start(); <---- This call should *not* start a spinner, since a() already started one.
			doSomeStuff();
			taranisSpinner.stop();  <---- This call should *not* stop the spinner, since a() isn't done spinning yet.
		}
		a();

	Therefore, in this.runningSpinners, keep track of the number of start() calls minus the number of stop() calls,
	i.e. the number of current spinner requests. Show the spinner when runningSpinners > 0.
	*/
	this.runningSpinners = 0;

	this.start = function() {
		if (this.runningSpinners == 0) {
			$('#filters-wrapper, #content').css({opacity: .5});
			this.spinner.spin(document.getElementById('spinner-anchor'));
		}
		this.runningSpinners++;
	};

	this.stop = function() {
		if (this.runningSpinners < 1) {
			throw "TaranisSpinner.stop(): no spinner is active";
		}
		if (this.runningSpinners == 1) {
			$('#filters-wrapper, #content').css({opacity: 1});
			this.spinner.stop();
		}
		this.runningSpinners--;
	};
}

