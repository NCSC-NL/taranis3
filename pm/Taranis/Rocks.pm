# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Rocks;

  use strict;
  use warnings;
  
  use Apache2::RequestRec ();
  use Apache2::RequestIO ();
  
  use Apache2::Const -compile => qw(OK);
  
  sub handler {
      my $r = shift;
  
      $r->content_type('text/plain');
      print "mod_perl 2.0 rocks!\n";
  
      return Apache2::Const::OK;
  }
1;
