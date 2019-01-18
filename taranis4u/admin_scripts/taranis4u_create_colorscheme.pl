#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;

use Taranis qw(:all);
use Data::Dumper;
use JSON;

my $colorSchemesFile = './color-schemes.json';
my $json = eval{
	fileToString( $colorSchemesFile );
};

if ( $@ ) {
	print "FAIL: $@\n";
} else {
	
	my $colorSchemes = from_json( $json );

	foreach my $colorSchemeType ( keys %{ $colorSchemes } ) {
		foreach my $colorScheme ( @{ $colorSchemes->{$colorSchemeType} } ) {
			my $cssFilenamePath = './css/color-' . $colorScheme->{bgColorName} . '-' . $colorScheme->{fontColorName} . '.css';
			my $options = "--modify-var='text-color=$colorScheme->{fontColor}' --modify-var='background-color=$colorScheme->{bgColor}'";
			$options .= " --modify-var='marked=$colorScheme->{marked}' " if ( exists( $colorScheme->{marked} ) );
			my $result = qx(lessc $options ./less/color-scheme-$colorSchemeType-bg.less $cssFilenamePath);
			print "$cssFilenamePath\ created with ./less/color-scheme-$colorSchemeType-bg.less \n";
		}
	}
	print "DONE\n";
}

