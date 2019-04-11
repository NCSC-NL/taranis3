# This file is part of Taranis, Copyright TNO.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::ClusterSet;

use strict;
use Taranis::Clustering::DocumentSet;
use Text::Wrap;
use Term::ANSIColor;
use Taranis::Clustering::SimilarityMatrix;
use Digest::MD5 qw(md5_base64);
use Time::Stamp -stamps => { dt_sep => ' ', date_sep => '/', us => 1 };
use FileHandle;

$Text::Wrap::columns = 80;
$Text::Wrap::separator = "\n";

my $MAX_ITERATIONS = 3;

## creator
#
sub new{
  my $class = shift;
  my $args  = shift;
  my $self  = {};

  bless $self,$class;

  ## check the initialization parameters
  unless($self->checkInitParameters($args)){
    print STDERR "ERROR: ClusterSet->initialize() incorrect or missing parameters.\n";
    return 0;
  }

  $self->{numClusters} = 0;
  $self->{docset}      = undef;
  $self->{matrix}      = undef;
  $self->{clusters}    = {};
  $self->{scoreOf}     = {};
  $self->{memberOf}    = {};
  $self->{logfile}     = '/tmp/clustering.log';

  $self->initLogging();

  return $self;
}

sub initLogging{
  my $self = shift;
  $self->{logfh} = FileHandle->new;
  unless($self->{logfh}->open(">> $self->{logfile}")){
    die "ERROR: cannot write to logfile $self->{logfile}\n";
  }

#  print STDERR "Logging will be written to $self->{logfile}\n";

  $self->logmessage("Initialized ClusterSet with following parameters:");

  my @p = ();
  for('language','threshold','settingspath'){
    push @p, "$_ = $self->{$_}";
  }
  $self->logmessage(join(", ",@p));
}



## first pass: cluster the documents into an initial clustering state
#
sub cluster{
  my ($self, $args) = @_;
  my $debug = 0;

  ## check the initialization parameters
  $self->{docset}    = $args->{docset};
  $self->{recluster} = $args->{recluster};

  unless($self->{docset}){
    warn "ERROR: ClusterSet->cluster() requires DocumentSet as input.";
    return 0;
  }

  ## create the similarity matrix
  #
  $self->createSimilarityMatrix();

  $self->logmessage("Started initial clustering run");

  ## loop over each document in docset for initial clustering
  #
  foreach my $doc ($self->{docset}->getDocuments()){
    my $docid = $doc->get('ID');
    my $clusterid = $doc->get('ClusterID');
    my $cached_score = $doc->get('Score');
    my %scores = ();

    $self->logmessage("Initializing document $docid: ".$doc->get('Text'))
		if $debug;

    ## check if we have a stored clusterID and score
    #  if so, load and continue
    #
    if(defined $clusterid && $clusterid=~/\S/){
      $doc->set(WasClustered => 1);

      if($self->clusterExists($clusterid)){
        $self->addClusterMember($clusterid, $doc, $cached_score);
      } else{
        $self->addCluster($doc,$clusterid);
      }
      next;
    }

    if($self->numClusters == 0){
    	## initialize first cluster with the first document
		$self->addCluster($doc);
    }
    else{
    	## or compute the average similarity to each cluster
      foreach my $cluster ($self->getClusters){
        my $cid = $cluster->getID();
        $self->logmessage("Comparing $docid to cluster $cid") if $debug;
        $scores{$cid} = $self->similarityDocToCluster($docid,$cluster);
      }

      ## then sort the cluster id's by the average scores from $doc to the clusters
      #
      my @sorted_ids = sort {$scores{$b}<=>$scores{$a}} keys %scores;
      my $highscore = $scores{$sorted_ids[0]};
      $self->logmessage("Best score for $docid = $highscore for cluster $sorted_ids[0]") if $debug;

      ## and add $doc to the best cluster, but only if the score exceeds the threshold
      #
      if($highscore > $self->{threshold}){
        $self->logmessage("Adding document $docid to cluster $sorted_ids[0] with score $highscore") if $debug;
        $self->addClusterMember($sorted_ids[0],$doc,$highscore);
      }
      ## or else create a new cluster with this document as the seed
      #
      else{
        my $cid = $self->addCluster($doc);
        $self->logmessage("Creating new cluster ($cid) for $docid") if $debug;
      }
    }
  }

  ## recluster if the recluster parameter is given
  #
  if($self->{recluster}){
    $self->recluster($self->{recluster});
  }

  ## return a docID-to-clusterID/score hash
  #
  my $map = {};
  foreach my $d (keys %{$self->{memberOf}}){
    $map->{$d}{clusterid} = $self->{memberOf}{$d};
    $map->{$d}{score} = $self->{scoreOf}{$d};
  }

  ## close the logfile
  #
  $self->{logfh}->close();

  return $map;
}

sub createSimilarityMatrix{
  my $self = shift;

  $self->logmessage("Started computing the similarity matrix");

  $self->{matrix} = Taranis::Clustering::SimilarityMatrix->new(
		$self->{language},$self->{settingspath},$self->{logfh});
  $self->{matrix}->create($self->{docset});
}

sub checkInitParameters{
  my $self = shift;
  my $args = shift;

  for('threshold','language','settingspath'){
    if(defined $args->{$_}){
      $self->{$_} = $args->{$_};
    } else{
      print STDERR "ERROR: ClusterSet->initialize() required parameter $_ missing!\n";
      return 0;
    }
  }
  return 1;
}

sub recluster{
  my $self   = shift;
  my $n_iter = shift || 1;

  my $iter = 1;

  $self->logmessage("Started reclustering iteration $iter");

  while($self->reclusterSinglePass() && $iter < $MAX_ITERATIONS){
    $iter++;
    $self->logmessage("Started reclustering iteration $iter");
  }
}

## recluster the initial clustering state
#
sub reclusterSinglePass{
  my $self     = shift;
  my $unstable = 0;
  my $debug    = 0;
  my $docset   = $self->{docset};
  my $matrix   = $self->{matrix};
  my %done     = ();

  foreach my $doc ($docset->getDocuments()){

    next if $doc->get('WasClustered');

    my $docid = $doc->get('ID');
    my $docs_clusid = $self->getClusterIDOfDoc($docid);
    my %scores;

    $self->logmessage("Reclustering $docid (now in $docs_clusid)") if $debug;

    foreach my $cluster ($self->getClusters()){
      my $cid = $cluster->getID();
      $scores{$cid} = $self->similarityDocToCluster($docid,$cluster);
    }

    my @sorted_ids = sort {$scores{$b}<=>$scores{$a}} keys %scores;
    my $highscore = $scores{$sorted_ids[0]};

    ## unstable scenario 1: document feels better at home in another cluster
    #
    if( ($highscore > $self->{threshold}) and ($sorted_ids[0] ne $docs_clusid) ){
      $self->deleteFromCluster($docid,$docs_clusid);
      $self->addClusterMember($sorted_ids[0],$doc,$highscore);
      $self->logmessage("Moving $docid from $docs_clusid to $sorted_ids[0]") if $debug;
      $unstable = 1;
    }
    ## unstable scenario 2: document is better off alone
    #
    elsif( ($highscore <= $self->{threshold}) and ($self->numClusterMembers($docs_clusid) > 1) ){
      $self->deleteFromCluster($docid,$docs_clusid);
      my $cid = $self->addCluster($doc);
      $self->logmessage("Moving $docid from $docs_clusid to its own cluster ($cid)") if $debug;
      $unstable = 1;
    }
    $done{$docid} = 1;
  }
  return $unstable;
}

## compute the similarity of a document to a cluster
#
sub similarityDocToCluster{
  my ($self, $docid, $cluster) = @_;

  my $matrix  = $self->{matrix};
  my $score   = 0;
  my $ncm     = 0;
  my $debug   = 0;

  my $seedclus = $cluster->getNumberOfDocuments == 1 ? 1 : 0;

  foreach my $clusterMember ($cluster->getDocuments){
    my $cmid = $clusterMember->get('ID');

    unless($cmid eq $docid){
      $ncm++;
      my $s = $matrix->getSimilarity($docid, $clusterMember->get('ID'));
      $score += $s;
      $self->logmessage("Got score $s ($ncm) for document: ".$clusterMember->get('Text')) if $debug;
    }
  }

  unless($ncm==0){
    $score /= $ncm;
    $self->logmessage("Average score for ".$cluster->getID()." = $score") if $debug;
  }

  return $score;
}

## get the number of clusters in this ClusterSet object
#
sub numClusters{
  my $self = shift;
  return $self->{numClusters};
}

## add a new empty cluster to this ClusterSet object
#
sub addCluster{
  my ($self, $seed, $given_id) = @_;

  my $c   = Taranis::Clustering::DocumentSet->new;
  my $cid = undef;
  if(defined($given_id)){
    $cid = $given_id;
  } else{
    my $lts = localstamp();
    $cid = md5_base64($seed->get('ID'),$seed->get('Timestamp'),$seed->get('URL'),$lts);
    $c->setNew();
  }

  $c->setID($cid);
  $c->setStart($seed->get('Epoch'));
  $c->setStatus($seed->get('Status'));

  $self->{clusters}{$cid} = $c;
  $self->{numClusters}++;

  $self->addClusterMember($cid, $seed, 'SEED');

  return $cid;
}

## get cluster object with id $cid
#
sub getCluster($) {
  my ($self, $cid) = @_;
  return $self->{clusters}{$cid};
}

sub clusterExists($) {
  my ($self, $cid) = @_;
  defined $self->{clusters}{$cid};
}

## get the number of documents in cluster $cid
#
sub numClusterMembers{
  my ($self, $cid) = @_;
  my $c = $self->{clusters}{$cid};
  return $c->getNumberOfDocuments;
}

## get all cluster objects in this ClusterSet object
#
sub getClusters() {
  my $self = shift;

  # sort by initiation time
  my @clusters = sort { $a->getStart <=> $b->getStart }
		values %{$self->{clusters}};

  return @clusters;
}

## delete document $docid from cluster $cid
#
sub deleteFromCluster{
  my ($self, $docid, $cid) = @_;
  my $c     = $self->{clusters}{$cid};

  my $res = $c->deleteDoc($docid);
  delete $self->{scoreOf}{$docid};
  delete $self->{memberOf}{$docid};

  if($c->getNumberOfDocuments() == 0){
    $self->deleteCluster($cid);
  }
}

## delete cluster $cid from this ClusterSet object
#
sub deleteCluster{
  my ($self, $cid) = @_;

  if(defined $self->{clusters}{$cid}){
    delete $self->{clusters}{$cid};
  } else{
    $self->logmessage("WARNING: attempt to delete non-existing cluster $cid");
    return 0;
  }
  return 1;
}

## stores some administration for a document
#
sub setMemberAdministration{
  my ($self, $docid, $cid, $score) = @_;

  $score ||= 'SEED';

  $self->{scoreOf}{$docid} = $score;
  $self->{memberOf}{$docid} = $cid;
}

## get the cluster id of document $docid
#
sub getClusterIDOfDoc{
  my $self  = shift;
  my $docid = shift;

  return $self->{memberOf}{$docid};
}

## add a document object to cluster $cid
#
sub addClusterMember{
  my $self = shift;
  my ($cid,$doc,$score) = @_;

  if(my $c = $self->{clusters}{$cid}){
    $c->add($doc);
    $self->setMemberAdministration($doc->get('ID'),$cid,$score);

    # we also add the clusterID and score to the document object itself
    $doc->set('ClusterID',$cid);
    $doc->set('Score',$score);
  } else{
    $self->logmessage("ERROR in function addClusterMember: cluster $cid not defined in ClusterSet object");
    return 0;
  }
  return 1;
}

## get the score of document $docid for its current cluster
#
sub getDocumentScore{
  my $self  = shift;
  my $docid = shift;
  return $self->{scoreOf}{$docid};
}

## print the clusters in a readable form
#
sub printClusters{
  my $self = shift;

  foreach my $c ($self->getClusters()){
    my $cid = $c->getID();
    my $caption = $c->getCaption();
    my $timespan = $c->getTimespan();

    print "Cluster $cid ($caption) [timespan: $timespan]\n  |\n";

    foreach my $d ($c->getDocuments()){
      my $did = $d->get('ID');
      my $score = $self->getDocumentScore($did);
      $score = sprintf("%.2f",$score) if $score =~/\d/;
      my $time = $d->get('Timestamp');

      print "  |____[ docid=$did, score=$score, time=$time ]\n";
      print "       ".wrap("","              ","title: ".$d->get('Title'))."\n";
      print "       ".wrap("","              ","text:  ".$d->get('Description'))."\n\n";
    }
    print "\n";
  }
}

sub logmessage{
  my $self = shift;
  my $msg = shift;
  $self->{logfh}->print(localstamp() . " $msg\n");
}

1;


__END__

=head1 NAME

ClusterSet - A module for clustering text documents.

=head1 SYNOPSIS

 use ClusterSet;

 my $clusterSet = ClusterSet->new( { language  => $language,
                                   threshold => $threshold } );

 $clusterSet->cluster( { docset => $docset, recluster => 1 } );

=head1 DESCRIPTION

=head2 Public Methods

=over

=item I<PACKAGE>->new(I< parameter_hashref >):

Returns a newly created PACKAGE object. Accepts a hash reference containing the clustering parameters. The following three parameters are required:

language  : The language of the input documents ('nl' or 'en').
threshold : A higher treshold value means stricter clustering.


=item I<$OBJ>->cluster(I< parameter_hashref >):

Returns a hash reference with document-ID to cluster-ID and score mappings, with the following structure:

   {
     documentID => { clusterID => clusterID, score => score },
     ...
   }

Accepts a hash reference containing the input parameters. The following two parameters are required:

docset    : DocumentSet object reference containing the documents.
recluster : After initial clustering, recluster: 1 or 0.

=item I<$OBJ>->printClusters():

Writes the clusters in a readable format to STDOUT.

=back

=head1 AUTHORS

Copyright (c) 2012-2013, TNO. All rights reserved.

=head1 VERSION

1.0

=cut
