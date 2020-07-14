# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::Tokenizer;

use strict;
use utf8;

## creator
#
sub new{
  my $class  = shift;
  my $params = shift;
  my $self   = {};

  bless $self,$class;

  %{$self->{params}} = ( ignorecase => 1 );

  while (my ($key,$val) = each %$params){
    if(defined $self->{params}{$key}){
      $self->{params}{$key} = $val;
    }
  }

  return $self;
}

sub tokenize{
  my $self = shift;
  my $text = shift;

  my @tokens = grep {/\w\w/} split /[\s\p{Punct}]/, lc $text;
  return @tokens;
}

## this version is slower, but leaves hyphen-compounds intact
sub tokenize_hyphen{
  my $self = shift;
  my $text = shift;

  $text=~s/[^\p{IsAlnum}\s\-]/ /g;
  $text=~s/\s{2,}/ /g;

  my @tokens = grep {/\w\w/} split /[\s]/, lc $text;
  return @tokens;
}



1;
