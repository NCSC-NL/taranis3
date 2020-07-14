# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::SimilarityMatrix;

use strict;
use Taranis::Clustering::BackgroundModel;
use Time::Stamp qw(localstamp);

my $DEBUG = 0;


## creator
#
sub new{
  my $class = shift;
  my $language = shift;
  my $settingsPath = shift;
  my $logfh = shift;

  my $self = {};

  bless $self,$class;

  unless (defined $language and defined $logfh and defined $settingsPath){
    print STDERR "ERROR: SimilarityMatrix constructor requires a language and a logfilehandle\n";
    return undef;
  }

  $settingsPath .= '/' if ( $settingsPath !~ /\/$/);

  $self->{Language}        = $language;
  $self->{SettingsPath}    = $settingsPath;
  $self->{logfh}           = $logfh;
  $self->{CWFile}          = $settingsPath . "commonwords.$self->{Language}";
  $self->{CommonWords}     = {};
  $self->{Smoothing}       = 'dirichlet';
  $self->{MinScore}        = -5;
  $self->{MinTokenOverlap} = 3;
  $self->{Similarities}    = [];
  $self->{Index}           = {};
  $self->{RevIndex}        = {};

  return $self;
}

## build a similarity matrix from the documents in a document set
#
sub create{
  my $self = shift;
  my $docset = shift;

  $self->{DocumentSet} = $docset;
  $self->{BackgroundModel} = new Taranis::Clustering::BackgroundModel($self->{Language}, $self->{SettingsPath}, $self->{logfh});

  $self->readCommonWords();
  $self->computeMatrix();
}

## compute the similarity matrix
#
sub computeMatrix{
  my $self  = shift;
  my $cnt   = 0;
  my @docs  = $self->{DocumentSet}->getDocuments();
  my $ndocs = @docs;

  for(my $x=0;$x<@docs;$x++){

    ## store the matrix id in an index
    #
    my $docid = $docs[$x]->get('ID');
    $self->{Index}{$docid} = $x;
    $self->{RevIndex}{$x} = $docid;

    ## we skip documents that were already asigned to a cluster
    #  in a previous run
    #
    my $clusterid = $docs[$x]->get('ClusterID');
    next if defined $clusterid and $clusterid=~/\S/;
    for(my $y=0;$y<@docs;$y++){
      $cnt++;
      print STDERR "$cnt\r" if $DEBUG;

      if (($x != $y) and (not defined $self->{Similarities}[$y][$x])){
        if(my $sim = $self->similarity($docs[$x],$docs[$y])){
          if($sim > $self->{MinScore}){
            $self->{Similarities}[$x][$y] = $sim;
          }
        }
      }
    }
  }
}

## get the stored similarity between two documents (input: two docid's)
#
sub getSimilarity{
  my $self = shift;
  my ($id_x,$id_y) = @_;

  unless (defined($id_x) and defined($id_y)){
    $self->logmessage("ERROR in function getSimilarity: called with wrong number of arguments");
    return undef;
  }

  my $x = $self->{Index}{$id_x};
  my $y = $self->{Index}{$id_y};

  if(defined $self->{Similarities}[$x][$y]){
    return $self->{Similarities}[$x][$y];
  }
  elsif(defined $self->{Similarities}[$y][$x]){
    return $self->{Similarities}[$y][$x];
  }
  else{
    return 0;
  }
}

## the actual similarity computation
#
sub similarity{
  my $self   = shift;
  my ($x,$y) = @_;
  my $lambda = 0.20;
  my $mu     = 2000;
  my $debug  = 0;

  ## get the unique words in both documents
  #
  my %w_x = map {$_ => 1} @{$x->get('Tokens')};
  my %w_y = map {$_ => 1} @{$y->get('Tokens')};

  ## return immediately if the documents share no words
  #
  return 0 unless $self->tokensOverlap(\%w_x,\%w_y);

  ## merge all words into a single hash
  #
  my %w_z = map {$_ => 1} (keys %w_x, keys %w_y);

  my $xlen = $x->get('Doclen');
  my $ylen = $y->get('Doclen');

  my ($sim_xy,$sim_yx) = (0,0);

  foreach my $w (keys %w_z){
    my $bgProb = $self->{BackgroundModel}->getWordProbability($w);

    ## Dirichlet smoothing
    #
    if($self->{Smoothing} eq 'dirichlet'){
      $sim_xy += ( $x->getWordFreq($w) * log( ( ($y->getWordFreq($w) + ($mu * $bgProb) ) / ($ylen + 2000)) / $bgProb ) );
      $sim_yx += ( $y->getWordFreq($w) * log( ( ($x->getWordFreq($w) + ($mu * $bgProb) ) / ($xlen + 2000)) / $bgProb ) );
    }
  }

  ## length normalization
  #
  $sim_xy /= $xlen;
  $sim_yx /= $ylen;

  my $sim = $sim_xy + $sim_yx;

  $self->logmessage("SCORE: $sim - $sim_xy ($xlen) $sim_yx ($ylen):\nX = ".$x->get('Text')."\nY = ".$y->get('Text')."\n") if $debug;

  return $sim;
}

## returns the smoothing method which is in use
#
sub smoothingMethod{
  my $self = shift;
  return $self->{Smoothing};
}

## checks if two token sets have at least $self->{MinTokenOverlap} words in common
#
sub tokensOverlap{
  my $self   = shift;
  my ($x,$y) = @_;
  my $cnt    = 0;

  foreach my $w (keys %$x){
    $cnt++ if ($y->{$w} and not $self->{CommonWords}{$w});
    return 1 if $cnt == $self->{MinTokenOverlap};
  }
  return 0;
}

sub readCommonWords{
  my $self = shift;

  if(open(CW,"<$self->{CWFile}")){
    while(<CW>){
      chop;
      if(/^(\S+)/){
        $self->{CommonWords}{$1} = 1;
      }
    }
    close CW;
  } else{
    $self->logmessage("Warning: cannot read common words file $self->{CWFile}");
    return 0;
  }
  return 1;
}

sub indexToID{
  my $self = shift;
  my $index = shift;
  return $self->{RevIndex}{$index};
}

sub idToIndex{
  my $self = shift;
  my $id = shift;
  return $self->{Index}{$id};
}

sub logmessage{
  my $self = shift;
  my $msg = shift;
  $self->{logfh}->print(localstamp() . " $msg\n");
}


1;
