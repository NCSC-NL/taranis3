# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package My::Fixup;

# This module is needed to enable the mod_dir directive DirectoryIndex. 
# Please see http://www.perlmonks.org/bare/?node_id=631334

use strict;
use warnings FATAL => qw(all);

use Apache2::Const -compile => qw(DIR_MAGIC_TYPE OK DECLINED);
use Apache2::RequestRec;
use Apache2::RequestUtil;

sub handler {
  my $r = shift;

  if ($r->handler eq 'perl-script' && -d $r->filename 
      && $r->is_initial_req)
  {
    $r->handler(Apache2::Const::DIR_MAGIC_TYPE);
    return Apache2::Const::OK;
  }
  return Apache2::Const::DECLINED;
}

1;
