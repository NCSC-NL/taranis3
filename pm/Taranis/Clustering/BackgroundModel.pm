# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::BackgroundModel;

use strict;
use Time::Stamp qw(localstamp);

my $ZERO_PROBABILITY = 0.0001;

#my %BGMODEL = ( nl => 'BGNL.model',
#                en => 'BGEN.model' );
#
#my %BGCONFIG = ( nl => 'BGNL.model.cfg',
#                 en => 'BGEN.model.cfg' );


## creator
#
sub new{
  my $class  = shift;
  my $lang   = shift;
  my $settingsPath = shift;
  my $logfh  = shift;
  my $self   = {};

  bless $self,$class;

  $self->{language} = $lang;
  $self->{logfh}    = $logfh;
  $self->{logging}  = 0 unless defined $self->{logfh};

  $settingsPath .= '/' if ( $settingsPath !~ /\/$/);

#  my $file = $BGMODEL{$self->{language}};
  my $file = $settingsPath . 'BG' . uc( $self->{language} ) . '.model';
#  my $cfg = $BGCONFIG{$self->{language}};
  my $cfg = $settingsPath . 'BG' . uc( $self->{language} ) . '.model.cfg';

  if(-f $file){
    $self->init($file,$cfg);
  } else{
      $self->logmessage("ERROR: background model $file does not exist") if $self->{logging};
      print STDERR "ERROR: background model $file does not exist\n" unless $self->{logging};
  }

  return $self;
}


sub init{
  my $self  = shift;
  my $file  = shift;
  my $cfg   = shift;

  if(open(BG,"<$file")){
    $self->logmessage("Started reading background model for $self->{language}") if $self->{logging};

    ## read the model's token records
    #
    while(<BG>){
      $self->readBGModelLine($_);
    }
    close BG;

    ## if we have a config file, read its token records
    #
    if(-f $cfg){
      if(open(CFG,"<$cfg")){
        $self->logmessage("Overwriting records from config $cfg") if $self->{logging};

        while(<CFG>){
          $self->readBGModelLine($_);
        }
        close CFG;
      } else{
        $self->logmessage("Warning: Cannot read background model config file $cfg") if $self->{logging};
      }

      $self->{Probs} = [];
    }
  } else{
    $self->logmessage("ERROR: Cannot read background model $file") if $self->{logging};
    print STDERR "ERROR: Cannot read background model $file\n" unless $self->{logging};
    exit;
  }
}

sub readBGModelLine{
  my $self = shift;
  my $line = shift;
  chop $line;
  if($line=~/\S/ and $line!~/^\#/){
    my @flds = split(" ",$line);
    $self->{Lookup}{$flds[1]} = $flds[0];
    $self->{df}[$flds[0]] = $flds[2];
    $self->{gtf}[$flds[0]] = $flds[3];
    $self->{GlobalDF} += $flds[2];
    $self->{GlobalTF} += $flds[3];
  }
}

sub tokenDefined{
  my $self  = shift;
  my $token = shift;

  if(defined $self->{Lookup}{$token}){
    return 1;
  }
  return 0;
}

sub getId{
  my $self  = shift;
  my $token = shift;
  return $self->{Lookup}{$token};
}

sub getDF{
  my $self  = shift;
  my $token = shift;
  return $self->getFromArray($token,'df');
}

sub getGTF{
  my $self  = shift;
  my $token = shift;
  return $self->getFromArray($token,'gtf');
}

sub getFromArray{
  my $self  = shift;
  my $token = shift;
  my $attr  = shift;

  if(my $id = $self->{Lookup}{$token}){
    return $self->{$attr}[$id];
  }
  return undef;
}

sub getWordProbability{
  my $self = shift;
  my $word = shift;

  if(my $id = $self->{Lookup}{$word}){
    $self->{Probs}[$id] = $self->{df}[$id] / $self->{GlobalDF}
      unless defined $self->{Probs}[$id];

    return $self->{Probs}[$id];
  } else{
    return $ZERO_PROBABILITY;
  }
}

sub logmessage{
  my $self = shift;
  my $msg = shift;
  $self->{logfh}->print(localstamp() . " $msg\n");
}


1;
