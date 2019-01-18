# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering;

use strict;
use warnings;

use DateTime;
use DateTime::Duration;

use Taranis          qw(find_config);
use Taranis::Config  ();
use Taranis::Cluster ();
use Taranis::Clustering::DocumentSet ();
use Taranis::Clustering::Document    ();
use Taranis::Clustering::ClusterSet  ();

sub new(%)  { my $class = shift; (bless {}, $class)->init( {@_} ) }
sub init($) {
	my ($self, $args) = @_;
	$self;
}

=item $obj->recluster(%options)

Option C<cleanup_old_scores>, to reset the whole clustering.

=cut

sub recluster($) {
	my ($self, %args) = @_;

	# my @clustersConfig = $::taranis->clusters->search;  # T4
	my $cfg = Taranis::Config->new;
	my $cl  = Taranis::Cluster->new($cfg);

	my @clusterConfigs = $cl->getCluster(
		'cl.is_enabled' => 1,
		threshold       => \"IS NOT NULL",
		timeframe_hours => \"IS NOT NULL",
		'ca.is_enabled' => 1
	);

	@clusterConfigs
		or die "ERROR: no clusters configured\n";

	my %cluster_by_category;
	foreach my $clusterConfig (@clusterConfigs) {
    	my $catid = $clusterConfig->{category_id};
    	push @{$cluster_by_category{$catid}}, $clusterConfig;
	}

	my $docset = Taranis::Clustering::DocumentSet->new;
	while(my ($category, $clusters) = each %cluster_by_category) {
		$docset->add($_)
    		for $self->_collectDocuments($category, $clusters, \%args);
	}

	my $path  = find_config $cfg->{clustering_settings_path};

	$self->_createCluster($_, $docset, $path)
		for @clusterConfigs;
}

sub _collectDocuments($$$) {
    my ($self, $category, $clusters, $args) = @_;

	my $longest_timeframe = 0;
	my @documents;

	# Go through all clusterconfigs and one where the language has not
	# been set.

	my %catch_no_lang = (
		category_id     => $category,
		language        => undef,
		timeframe_hours => 0,
	);

	foreach my $config (@$clusters, \%catch_no_lang) {

		my $lang   = $config->{language} ? lc($config->{language}) : undef;
		my $cat_id = $config->{category_id};

		# get/set the longest timeframe (per category) for sources which
		# have not set a language
		$longest_timeframe = $config->{timeframe_hours}
			if $config->{timeframe_hours} > $longest_timeframe;

		my $tf_hours = $config->{timeframe_hours} ||= $longest_timeframe;
		my $aged     = "'$tf_hours hour'";

		if($args->{cleanup_old_scores}) {
			$::db->query(<<'_CLEANUP', $aged, $cat_id, $lang);
 UPDATE item AS i
    SET cluster_score = NULL, cluster_id = NULL
   FROM sources AS s
  WHERE s.id = i.source_id
    AND i.created BETWEEN NOW() - '1 week'::INTERVAL AND NOW() - ?::INTERVAL
    AND i.category = ?
    AND s.language = ?
_CLEANUP
		}

		my $items = $::db->query(<<'_GET_ITEMS', $cat_id, $aged, $lang);
 SELECT i.digest, i.category, i.source, i.title, i.link, i.description,
        i.created, i.status, i.cluster_id, i.cluster_score
   FROM item AS i
        JOIN sources AS src ON src.id = i.source_id
  WHERE i.category = ?
    AND i.created > NOW() - ?::INTERVAL
    AND i.source_id IS NOT NULL
    AND src.language = ?
    AND src.clustering_enabled
_GET_ITEMS

		while(my $item = $items->hash) {
			my $doc = Taranis::Clustering::Document->new->load($item, $lang);
			push @documents, $doc if $doc;
		}
	}

	@documents;
}

sub _createCluster($$$) {
    my ($self, $config, $docset, $path) = @_;
	my $lang       = $config->{language};

	my $clusterSet = Taranis::Clustering::ClusterSet->new({
		language     => lc $lang,
		threshold    => $config->{threshold},
		settingspath => $path,
	});

	my $subset = Taranis::Clustering::DocumentSet->new;
	my $docs   = $docset->subset({
		Lang     => $lang,
		Category => $config->{category_id},
	});

	# Do not cluster items which are older than the given timeframe.
	# This is needed, because there can be items included in de subset
    # which were selected with the longest timeframe of a category.

	my $dtTimeframe = DateTime->now;
	$dtTimeframe->subtract_duration(
		DateTime::Duration->new( hours => $config->{timeframe_hours} ));

	foreach my $doc (@$docs) {	
		$doc->get('Epoch') > $dtTimeframe->epoch or next;
		$subset->add($doc);
	}
	$subset->sortBy('Epoch');

	$clusterSet->cluster({docset => $docset, recluster => $config->{recluster}});

	foreach my $cluster ($clusterSet->getClusters) {
		my $cluster_id     = $cluster->getID;
		my $cluster_status = $cluster->getStatus;

		foreach my $document ($cluster->getDocuments) {
			my $score      = $document->get('Score');
			$score         = 0 if $score =~ /SEED/i;

			my %update     = (
				cluster_id    => $cluster_id,
				cluster_score => $score,
			);

			# only set status for 'unread' and 'important'
			$update{status} = $cluster_status
				if $cluster_status eq 1 || $cluster_status eq 2;

			my $doc_status = $document->get('Status');
			$update{status} = 1
				if $score          != 0
				&& $cluster_status eq 3
				&& $doc_status     != 3;

			my $doc_digest = $document->get('ID');
			$::db->update(item => \%update, { digest => $doc_digest } );
		}
	}
}

1;
