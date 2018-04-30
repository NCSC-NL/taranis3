#!/usr/bin/env perl
# Install some useful vim defaults.
# vim: filetype=perl

use warnings;
use strict;

use Carp   qw(confess);

use Taranis::Install::Config qw(config_generic become_user_taranis);

my $generic = config_generic;
my $vimrc   = "$generic->{home}/.vimrc";

become_user_taranis;

if(-f $vimrc) {
	print "*   vimrc already present\n";
	exit 0;
}

open my $rc, '>:encoding(utf8)', $vimrc
	or die "ERROR: cannot write $vimrc: $!\n";

$rc->print(<<'_DEFAULT_VIMRC');
set incsearch
set hlsearch
set modeline
au BufNewFile,BufRead *.tt set filetype=tt2html

" Taranis code uses tabstop=4
set ts=4

" Tell vim to remember certain things when we exit
"  '10  :  marks will be remembered for up to 10 previously edited files
"  "100 :  will save up to 100 lines for each register
"  :20  :  up to 20 lines of command-line history will be remembered
"  %    :  saves and restores the buffer list
"  n... :  where to save the viminfo files
set viminfo='10,\"100,:20,%,n~/.viminfo

_DEFAULT_VIMRC

exit 0;
