# This file is part of Taranis, Copyright TNO.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::DocumentSet;

use strict;
use Data::Dumper;

my $DEBUG = 0;


## creator
#
sub new{
  my $class = shift;
  my $self  = {};

  bless $self,$class;

  $self->{Documents} = [];
  $self->{Index}     = {};

  return $self;
}

sub add{
  my $self = shift;
  my @docs = @_;

  foreach my $d (@docs){
    if($d){
      my $docid = $d->get('ID');

      push @{$self->{Documents}},$d;
      $self->{Index}{$docid} = $#{$self->{Documents}};
    }
  }
}

sub deleteDoc{
  my $self = shift;
  my $docid = shift;
  my $index = $self->{Index}{$docid};

  if(defined $index){
    splice(@{$self->{Documents}},$index,1);
    $self->updateIndex();
  } else{
    print STDERR "ERROR in function deleteDoc: no document index available for $docid\n";
    return 0;
  }
  return 1;
}

sub updateIndex{
  my $self = shift;
  $self->{Index} = {};
  for (my $i=0;$i<@{$self->{Documents}};$i++){
    my $d = $self->{Documents}[$i];
    my $docid = $d->get('ID');
    $self->{Index}{$docid} = $i;
  }
}

sub getDocIndex{
  my $self = shift;
  my $docid = shift;
  return $self->{Index}{$docid};
}

sub getDocument{
  my $self = shift;
  my $docid = shift;
  my $index = $self->getDocIndex($docid);
  if(defined $index and defined $self->{Documents}[$index]){
    return $self->{Documents}[$index];
  } else{
    print STDERR "ERROR: cannot find document $docid in DocumentSet\n";
  }
  return undef;
}

sub csvRecord{
  my $self = shift;
  my $format = shift;
  my $docid = shift;

  my $doc = $self->getDocument($docid);
  my $fields = $doc->fieldIndex($format);

  return [ map {$doc->get($_)} @$fields ];
}

sub setID{
  my $self = shift;
  my $id = shift;
  $self->{ID} = $id;
}

sub getID{
  my $self = shift;
  return $self->{ID};
}

sub setStart{
  my $self = shift;
  my $start = shift;
  $self->{Start} = $start;
}

sub getStart{
  my $self = shift;
  return $self->{Start};
}

sub setNew{
  my $self = shift;
  $self->{New} = 1;
}

sub getNew{
  my $self = shift;
  return $self->{New};
}

sub setStatus{
  my $self = shift;
  my $status = shift;
  $self->{Status} = $status;
}

sub getStatus{
  my $self = shift;
  return $self->{Status};
}


sub subset{
  my $self   = shift;
  my $filter = shift;
  my $docs   = [];
  my $nkeys  = keys %$filter;

  foreach my $d (@{$self->{Documents}}){
    my $match = 0;
    foreach my $key (keys %$filter){
      $match++ if $self->parameterMatches($d,$key,$filter->{$key});
    }
    push @$docs, $d if ($match == $nkeys);
  }
  return $docs;
}

sub parameterMatches{
  my $self  = shift;
  my $doc   = shift;
  my $key   = shift;
  my $value = shift;

  my $epoch = $doc->timestampToEpoch($value) if($key=~/Start|End/);

  if($key eq "Start" and $epoch){
    return 1 if($doc->get('Epoch') >= $epoch);
  }
  elsif($key eq "End" and $epoch){
    return 1 if($doc->get('Epoch') <= $epoch);
  }
  else{
    return 1 if $doc->get($key)=~/$value/;
  }
  return 0;
}

sub sortBy{
  my $self = shift;
  my $attr = shift;

  my $sorted = [ sort {$a->get($attr) <=> $b->get($attr)} @{$self->{Documents}} ];
  $self->{Documents} = $sorted;
  $self->updateIndex();
}

sub getStartEnd{
  my $self = shift;
  my @sortedDocs = sort {$a->get('Epoch') <=> $b->get('Epoch')} @{$self->{Documents}};
  my ($sdoc,$edoc) = ($sortedDocs[0],$sortedDocs[$#sortedDocs]);

  return ($sdoc->get('Timestamp'),$edoc->get('Timestamp'));
}

sub getNoveltyScore{
  my $self = shift;

  my @sortedDocs = sort {$b->get('Epoch') <=> $a->get('Epoch')} $self->getDocuments();

  my $curEpoch = time();

  my $novelty = 0;
  my $novThreshold = 1 / 24;

  foreach my $t (@sortedDocs){
    my $dEpoch = $t->get('Epoch');
    my $nsecs = $curEpoch - $dEpoch;
    my $nhour = $nsecs / 3600;
    my $dNovelty = sprintf("%.3f", 1 / $nhour);

    if($dNovelty >= $novThreshold){
       $novelty += $dNovelty;
    }
  }

  return $novelty;
}

sub getDocuments{
  my $self = shift;
  return @{$self->{Documents}};
}

sub getDocumentIds{
  my $self = shift;
  return map { $_->get('ID') } $self->getDocuments();
}

sub getNumberOfDocuments{
  my $self = shift;
  my $n = @{$self->{Documents}};
  return $n;
}

sub getCaption{
  my $self = shift;
  foreach my $d (sort {$a->get('Epoch') <=> $b->get('Epoch')} @{$self->{Documents}}){
    my $title = $d->get('Title');
    if(defined $title and length($title)>5){
      return $title;
    }
  }
  return '';
}

sub getTimespan{
  my $self = shift;
  my $timespan = '';
  my @chronDocs = (sort {$a->get('Epoch') <=> $b->get('Epoch')} @{$self->{Documents}});
  if(@chronDocs>1){
    my $secs = $chronDocs[$#chronDocs]->get('Epoch') - $chronDocs[0]->get('Epoch');
    $timespan = sec2human($secs);
  }
  return $timespan;
}

sub getOldestMember{
  my $self = shift;
  my @chronDocs = (sort {$a->get('Epoch') <=> $b->get('Epoch')} @{$self->{Documents}});
  return $chronDocs[0];
}

sub sec2human {
    my $secs = shift;
    if    ($secs >= 365*24*60*60) { return sprintf '%.1fy', $secs/(365*24*60*60) }
    elsif ($secs >=     24*60*60) { return sprintf '%.1fd', $secs/(    24*60*60) }
    elsif ($secs >=        60*60) { return sprintf '%.1fh', $secs/(       60*60) }
    elsif ($secs >=           60) { return sprintf '%.1fm', $secs/(          60) }
    else                          { return sprintf '%.1fs', $secs                }
}




1;


__END__

=head1 NAME

DocumentSet - A module for managing multiple documents.

=head1 SYNOPSIS

use DocumentSet;

my $docset = new DocumentSet();

$docset->add( @documents );

my @docs = $docset->subset( { Lang => $language,
                              Category => $category });

=head1 DESCRIPTION

See the section on "Public Methods" below for details.

=head2 Public Methods


=over

=item I<PACKAGE>->new(I< parameter_hashref >):

Returns a newly created PACKAGE object.

=item I<$OBJ>->add(I< array_of_documents >):

Add one or more documents (i.e. Document object references) to the DocumentSet object.

=item I<$OBJ>->subset(I< attr_value_hashref >):

Returns all Document objects in the DocumentSet that fullfil the attribute-values given in the input hash reference.

=item I<$OBJ>->getNumberOfDocuments()

Get the number of documents in the document set

=item I<$OBJ>->getDocuments()

Get all Document objects in the document set

=item I<$OBJ>->sortBy(I< attr >)

Sort all document by attribute attr (e.g. for chronological sorting, sort by Epoch)


=back

=head1 AUTHORS

Copyright (c) 2012-2013, TNO. All rights reserved.

=head1 VERSION

1.0



