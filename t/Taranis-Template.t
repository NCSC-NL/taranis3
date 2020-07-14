#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

## Taranis-Publication.t: tests for Taranis::Publication.

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use utf8;

use Test::Most;

use Taranis qw(fileToString);
use Taranis::Template;
use Taranis::FunctionalWrapper qw(Template);
use Taranis::TestUtil qw(cmp_deeply_or_diff withDistConfig withEphemeralDatabase);


# Unfortunately, Template's constructor calls Database's constructor, which calls Config's constructor, so we need both
# withDistConfig and withEphemeralDatabase because we're using Template (even though we won't actually be using the
# config or the database).
withDistConfig {
	withEphemeralDatabase {
		# Test &setNewlines.
		# It has a whole bunch of warts, just reproducing its exact behaviour here so we can safely refactor it.
		{
			is
				Template->setNewlines('', 5, 71),
				'',
				'empty string';
			is
				Template->setNewlines('blah', 5, 71),
				'blah',
				'trivial small string';

			{
				# Some random text, with some wide characters, some long lines and some creative whitespace.
				my $longstr = q{
(｡◕‿‿◕｡)
NU, Het laatste nieuws het eerst op NU.nl, , http://www.nu.nl/, nl-nl, Copyright (c) 2015, NU, 10 dus
item vars: Israëlische startup wil elektrische auto's in vijf minuten opladen, Storedot, een Israëlische startup die snelladende batterijen ontwikkelt, heeft een investering van 18 miljoen dollar binnengehaald. Het bedrijf zal dat geld gebruiken om snel ladende batterijen voor elektrische auto's te ontwikkelen, 2015-08-19T15:57:05+02:00, http://www.nu.nl/gadgets/4109262/israelische-startup-wil-elektrische-autos-in-vijf-minuten-opladen.html, Auto Tech Gadgets, NU.nl dus
item vars: 'Megan Fox na elf jaar weer vrijgezel', Megan Fox en haar echtgenoot Brian Austin Green zijn na een relatie van elf jaar uit elkaar.

ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJ

1 here comes a bunch of trailing spaces:
 2                                                                                                                                                                                                                                                                          
  3

http://ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJ.nl/foo
};

				my $expected = q{(&#xFF61;&#x25D5;&#x203F;&#x203F;&#x25D5;&#xFF61;)
NU, Het laatste nieuws het eerst op NU.nl, , http://www.nu.nl/,
nl-nl, Copyright (c) 2015, NU, 10 dus
item vars: Isra&euml;lische startup wil elektrische auto&#39;s in vijf
minuten opladen, Storedot, een Isra&euml;lische startup die snelladende
batterijen ontwikkelt, heeft een investering van 18 miljoen dollar
binnengehaald. Het bedrijf zal dat geld gebruiken om snel ladende
batterijen voor elektrische auto&#39;s te ontwikkelen,
2015-08-19T15:57:05+02:00,
http://www.nu.nl/gadgets/4109262
   /israelische-startup-wil-elektrische-autos-in-vijf-minuten-opla
   den.html, Auto Tech Gadgets, NU.nl dus
item vars: &#39;Megan Fox na elf jaar weer vrijgezel&#39;, Megan Fox en
haar echtgenoot Brian Austin Green zijn na een relatie van elf
jaar uit elkaar.

ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEF
   GHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHI
   JABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJAB
   CDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDE
   FGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGH
   IJ

1 here comes a bunch of trailing spaces:
 2                                                                
                                                                  
                                                                  
                                                                  

  3

http:/
   /ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJAB
   CDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDE
   FGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGH
   IJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJA
   BCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCD
   EFGHIJ.nl/foo
};

				cmp_deeply_or_diff
					Template->setNewlines($longstr, 5, 71),
					$expected,
					'wide chars, long lines, whitespace';


				# Add URL to the end whose last part, after being split into multiple lines, is between setNewlines'
				# $link_length and $line_length. To test the 'if ($in_hyperlink)' part of setNewlines.
				$longstr .= q{

http://ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGH.nl/fooooooooooooooooooooooooooooooooooooooooooooooooooooo
};
				$expected .= q{

http:/
   /ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJAB
   CDEFGH.nl
   /fooooooooooooooooooooooooooooooooooooooooooooooooooooo
};

				cmp_deeply_or_diff
					Template->setNewlines($longstr, 5, 71),
					$expected,
					'wrapped URL at end with $link_length < length < $line_length';

				$longstr =~ s/\n/\r\n/g;
				$expected =~ s/\n/\r\n/g;
				cmp_deeply_or_diff
					Template->setNewlines($longstr, 5, 71),
					$expected,
					'DOS line endings';
			}
		}
	};
};

done_testing;
