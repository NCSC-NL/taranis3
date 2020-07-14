# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

=head1 NAME

Taranis::Collector::Statistics - Collector statistics management

=head1 SYNOPSIS

  my $stats = Taranis::Collector::Statistics->new(collector => $col);

=head1 DESCRIPTION

Module for creating, downloading, and managing statistics images. Mainly
used at the end of a collector run.

=cut

package Taranis::Collector::Statistics;
#use parent 'Taranis::Object';

use strict;
use warnings;

use GD::Graph::bars;
use GD::Graph::hbars;
use Digest::MD5         qw(md5_base64);
use Carp                qw(confess croak);

use Taranis                qw(nowstring trim);
use Taranis::Config        ();
use Taranis::Collector     ();
use Taranis::Config::Stats ();

my $own_stats_category = 'Taranis Statistics';

=head1 METHODS

=head2 Constructors

=over 4

=item my $stats = $class->new(%options);

As C<%options> you need to provide a C<collector> (L<Taranis::Collector>
object).

=cut

sub new() { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($) {
	my ($self, $args) = @_;
#	$self->SUPER::init($args);
	$self->{TCS_collector} = $args->{collector} ||
		Taranis::Collector->new(Taranis::Config->new);
	$self;
}


=back

=head2 Accessors

=over 4

=item my $collector = $stats->collector;

=cut

sub collector() { shift->{TCS_collector} }


=back

=head2 Image generation

=over 4

=cut

#XXX interface simplication in T4
sub writeSourceCheck($$) {
	my ($self, $source, $comment) = @_;
	my $now = nowstring(2);
	$self->collector->writeSourceCheck(
		source  => $source,
		comment => "($now) $comment",
	);
}

# $stats->_downloadStatisticImages($config, $logger);
# Will download images which are set in the statistics configuration file,
# which can be set in Taranis or collector configuration file with setting
# C<statsconfig>.

sub _downloadStatisticImages($$) {
	my ($self, $stats, $logger) = @_;

  STAT:
	foreach my $stat (@$stats) {
		$stat->{no_encoding} = 1;
		$stat->{is_image}    = 1;

		my $description = $stat->{description};
		my $imageUrl    = $stat->{image};
		my $link        = $stat->{link};
		my $source      = $stat->{source};
		my $category    = $stat->{category};
		my $digest      = md5_base64 $imageUrl;
		$stat->{digest} = $digest;


		my $collector   = $self->collector;
		unless($collector->sourceMtbcPassed($stat, undef)) {
			$logger->info("skipping stats image on mtbc: $imageUrl");
			next STAT;
		}

		$logger->info("download stats image $imageUrl");

		my $image = eval { $collector->getSourceData($imageUrl, $stat) };
		if($@) {
			$collector->writeError(
				source   => $source,
				error    => "URL: $imageUrl - HTTP STATUS: $collector->{http_status_code} - ERROR: $@",
				error_code => delete $collector->{http_status_code},
			);
			$self->writeSourceCheck($digest, 'ERROR');
			return $self;
		}

		my ($blob_oid, $blob_size) = $::db->addBlob($image);

		my %update = (
			description => $description,
			link        => $link,
			source      => $source,
			category    => $category,
			object_id   => $blob_oid,
			file_size   => $blob_size,
		);

		if($::db->query(<<'__EXISTS', $digest)->list) {
SELECT 1 FROM statsimages WHERE digest = ?
__EXISTS
			$logger->info("update downloaded image $imageUrl (digest $digest)");
			$::db->update(statsimages => \%update, {digest => $digest});
		} else {
			$logger->info("new downloaded image $imageUrl (digest $digest)");
			$update{digest} = $digest;
			$::db->insert(statsimages => \%update);
		}
		$self->writeSourceCheck($digest, 'OK');
	}

	$self;
}


# $stats->_cleanupStatisticImages($config, $logger)
# Will delete database entries in table C<statsimages> which are no longer
# set in the statistics configuration file, which can be set in Taranis
# or collector configuration file with setting C<statsconfig>.

sub _cleanupStatisticImages($$) {
	my ($self, $stats, $logger) = @_;
	my %keep  = map +(md5_base64($_->{image}) => 1), @$stats;

	my @haves = $::db->query( <<'__DOWNLOADED', $own_stats_category)->flat;
SELECT digest FROM statsimages WHERE category != ?
__DOWNLOADED

	foreach my $have (@haves) {
		next if $keep{$have};

		$logger->info("removed statsimage with digest $have");
		$::db->query("DELETE FROM statsimages WHERE digest = ?", $have);
	}
	$self;
}


=item my $count = $stats->downloadStats($stats_file, $logger);

Download stats from external sources.  The sources for the images are
configured in the file indicted by the statsconfig configuration 
parameter.

=cut

#XXX There is no reason to link this to the collector code.

sub downloadStats($$) {
	my ($self, $statsfile, $logger) = @_;

	my $st        = Taranis::Config::Stats->new;
	my $newstats  = $st->loadCollection($statsfile);
	unless($newstats) {
		$logger->error("retrieving stats config: $st->{errmsg}");
		return 0;
	}

	$self->_cleanupStatisticImages($newstats, $logger)
	     ->_downloadStatisticImages($newstats, $logger);
}


# $stats->_createGraph($logger, %settings)

sub _createGraph($%) {
	my ($self, $logger, %settings) = @_;

	my $graph_type  = uc $settings{graphType};
	my $graph_title = $settings{graphTitle};
	my $graphXLabel = $settings{graphXLabel};
	my $graphYLabel = $settings{graphYLabel};
	my $reverse     = $settings{reverse};
	my $records     = $settings{records};

	my $cntr = -1;
	my $max  = 0;
	my (@x, @y);

	if(@$records==1 && !$records->[0]{label}) {
		$logger->warning("no records (yet) for '$graph_title'");
		return;
	}

	foreach my $record (@$records) {
		push @x, $record->{label};
		push @y, $record->{cnt};
		$max = $record->{cnt} if $record->{cnt} > $max;
	}

	return 1 if !$max;

	my @data = $reverse ? ([reverse @x], [reverse @y]) : (\@x, \@y);
    my $graph
	  = $graph_type eq 'BAR'  ? GD::Graph::bars->new(650, 400)
	  : $graph_type eq 'HBAR' ? GD::Graph::hbars->new(650, 400)
	  :                         confess $graph_type;

	$graph->set(
		x_label       => $graphXLabel,
		y_label       => $graphYLabel,
		title         => '',
		y_max_value   => $max + 100,
		y_min_value   => 0,
		y_tick_number => 10,
		y_label_skip  => 2,
		box_axis      => 0,
		line_width    => 3,
		fgclr         => 'red',
		show_values   => 1,
		transparent   => 1,
	);

	$graph->set_text_clr('black');
	my $gd = $graph->plot(\@data);

	my ($blob_oid, $blob_size) = $::db->addBlob($gd->gif);

	my %update = (
		description => $graph_title,
		link        => '#',
		source      => 'Taranis',
		category    => $own_stats_category,
		object_id   => $blob_oid,
		file_size   => $blob_size,
	);

	my $digest = md5_base64 $settings{filename};
	if($::db->query( <<'__EXISTS', $digest)->list) {
SELECT 1 FROM statsimages WHERE digest = ?
__EXISTS
		$::db->update(statsimages => \%update, {digest => $digest});
	} else {
		$update{digest} = $digest;
		$::db->insert(statsimages => \%update);
	}

	return 1;
}


=item my $count = $stats->createGraphs($logger);

Create all graphs needed for the dashboard.

=cut

sub createGraphs($) {
	my ($self, $logger) = @_;

	#################################
	### Graph #1: number of items ###
	#################################
	my @itemcount = $::db->query( <<'_NR_ITEMS' )->hashes;
 SELECT COUNT(*) AS cnt, EXTRACT(day FROM DATE_TRUNC('day', created)) AS label
   FROM item
  GROUP BY DATE_TRUNC('day', created)
  ORDER BY DATE_TRUNC('day', created) DESC
  LIMIT 30
_NR_ITEMS

	my $cntr = 1;
	$self->_createGraph($logger,
		records		=> \@itemcount,
		graphType 	=> "bar",
		graphTitle 	=> "Collected Items by Taranis",
		graphXLabel => "Day of month",
		graphYLabel => "Number of collected items",
		filename 	=> "taranis${cntr}.gif",
		reverse 	=> 1,
	);
	$cntr++;

	######################################
	### Graph #2: Imported items to WR ###
	######################################

	my @imported = $::db->query( <<'_NR_IMPORTED')->hashes;
 SELECT a.e AS label, COALESCE(b.cnt, 0) AS cnt
   FROM
    ( SELECT EXTRACT(day FROM DATE_TRUNC('day', (CURRENT_DATE - offs))) AS e
      FROM GENERATE_SERIES(0, 29, 1) AS offs
    ) AS a
    LEFT JOIN
    ( SELECT EXTRACT(day FROM DATE_TRUNC('day', item.created)) AS e,
             COUNT(item.id) AS cnt
        FROM item
       WHERE item.status = 3
         AND item.created > NOW() - INTERVAL '1 month'
       GROUP BY DATE_TRUNC('day', item.created)
    ) AS b ON a.e = b.e
  ORDER BY a.e
_NR_IMPORTED

	$self->_createGraph($logger,
		records     => \@imported,
		graphType   => "bar",
		graphTitle 	=> "Number of items imported to waitingroom",
		graphXLabel => "Day of month",
		graphYLabel => "Number of items imported to WR",
		filename    => "taranis${cntr}.gif",
		reverse		=> 1
	);
	$cntr++;

	#############################
	### Graph #3: Top sources ###
	#############################

	# T4: my @categories = $::taranis->categories->list;
	my @categories = $::db->query(<<'__CATEGORY_IDS')->hashes;
SELECT * FROM category WHERE is_enabled
__CATEGORY_IDS

	foreach my $category (@categories) {
		$cntr++;

		my @tops = $::db->query( <<'__TOP_CATS', $category->{id})->hashes;
 SELECT DISTINCT(source) AS label, COUNT(*) AS cnt
   FROM item
  WHERE category = ? 
  GROUP BY source
  ORDER BY cnt DESC
  LIMIT 10
__TOP_CATS

		$self->_createGraph($logger,
			records     => \@tops,
			graphType 	=> "hbar",
			graphTitle 	=> "Top 10 sources (category $category->{name})",
			graphXLabel => "Source",
			graphYLabel => "Number of collected items",
			filename	=> "taranis${cntr}.gif",
			reverse 	=> 0,
		);
	}

	################################
	### Graph #4: Bottom sources ###
	################################

	foreach my $category (@categories) {
		$cntr++;

		my @bottoms = $::db->query( <<'__BOTTOM', $category->{id})->hashes;
 SELECT DISTINCT(source) AS label, COUNT(*) AS cnt
   FROM item
  WHERE category = ? 
  GROUP BY source
  ORDER BY cnt ASC
  LIMIT 10
__BOTTOM

		$self->_createGraph($logger,
			records		=> \@bottoms,
			graphType 	=> "hbar",
			graphTitle 	=> "Bottom 10 sources (category $category->{name})",
			graphXLabel => "Source",
			graphYLabel => "Number of collected items",
			filename	=> "taranis${cntr}.gif",
			reverse  	=> 0,
		);
	}

	$cntr;
}

=back

=cut

1;
