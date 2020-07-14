# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Publish;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		tpl => 'dashboard_publish.tt',
		tpl_minified => 'dashboard_publish_minified.tt'
	};
	return( bless( $self, $class ) );
}

sub numberOfApprovedPublications {
	my ($self) = @_;
	my $db = Database->simple;
	$db->query('SELECT COUNT(*) FROM publication WHERE status = 2')->list;
}

sub oldestUnpublishedToWebsite {
	my $self = shift;
	my $db   = Database->simple;

	my $oldest = $db->query(<<'__OLDEST_UNPUBLISHED')->hash;
 SELECT to_char(MIN(p.created_on), 'HH24:MI DD-MM-YYYY' ) AS oldest_created_on,
        FLOOR(EXTRACT(EPOCH FROM current_timestamp - MIN(created_on))/60) AS minutes_ago
   FROM publication AS p
        JOIN publication_advisory_website AS paw ON paw.publication_id = p.id
  WHERE p.created_on < NOW() - '30 minutes'::INTERVAL
    AND p.status != 3
    AND advisory_forward_id IS NULL
__OLDEST_UNPUBLISHED

	$oldest;
}

1;

=head1 NAME

Taranis::Dashboard::Publish

=head1 SYNOPSIS

  use Taranis::Dashboard::Publish;

  my $obj = Taranis::Dashboard::Publish->new( $oTaranisConfig );

  my $count = $obj->numberOfApprovedPublications;

  my $h = $obj->oldestUnpublishedToWebsite;

=head1 DESCRIPTION

Controls the content of the Publish section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Publish> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Publish->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Sets the template of the Publish section of the dashboard:

    $obj->{tpl}

Sets the template of the Publish section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 numberOfApprovedPublications()

Counts the number of publications with status 'approved'.

Returns a number.

=head2 oldestUnpublishedToWebsite()

Returns a hash with two keys: C<oldest_created_on> and C<minutes_ago>.

=cut
