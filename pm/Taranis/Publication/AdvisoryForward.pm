# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication::AdvisoryForward;

use Taranis::Config;
use Taranis::Damagedescription;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::SoftwareHardware;
use SQL::Abstract::More;
use Encode;
use strict;

sub new {
	my ( $class, %args ) = @_;

	my $config = ( exists( $args{config} ) ) ? $args{config} : undef;
	my $dbh = ( !$args{no_db} ) ? Database : undef;

	my $self = {
		errmsg => undef,
		dbh => $dbh,
		sql => Sql,
		scale => { high => 1, medium => 2, low => 3 },
		config => $config
	};
	
	return( bless( $self, $class ) );
}

sub deletePublication {
	my ( $self, $id, $oTaranisPublication ) = @_;
	undef $self->{errmsg};	

	my $oTaranisTagging = Taranis::Tagging->new();

	my $publication = $oTaranisPublication->getPublicationDetails(
		table => "publication_advisory_forward",
		"publication_advisory_forward.id" => $id
	);

	my $is_update = $self->{dbh}->checkIfExists( { replacedby_id => $publication->{publication_id} }, "publication" );

	my $previousVersion;
	my %tags;

	if ( $is_update ) {
		$previousVersion = $oTaranisPublication->getPublicationDetails(
			table => "publication_advisory_forward",
			"pu.replacedby_id" => $publication->{publication_id}
		);
			
		$oTaranisPublication->{previousVersionId} = $previousVersion->{publication_id};
			
		$oTaranisTagging->loadCollection( "ti.item_id" => $id, "ti.item_table_name" => "publication_advisory_forward" );
	
		while ( $oTaranisTagging->nextObject() ) {
			my $tag = $oTaranisTagging->getObject();
			$tags{ $tag->{id} } = 1;
		}
	}
		
	my $newerVersions;
	if ( $publication->{replacedby_id} ) {
		$newerVersions = $oTaranisPublication->getNextVersions( $publication->{replacedby_id} );
	}

	my $result;
	withTransaction {
		my $check_1;
		if ( $is_update ) {
			$check_1 = $oTaranisPublication->setPublication( 
				where => { replacedby_id => $publication->{publication_id} },
				replacedby_id => $publication->{replacedby_id}
			);
		} else {
			$check_1 = 1;
		}
			
		# update the version numbers with -0.01 of advisories with a higher version number.
		if ( $newerVersions && @$newerVersions ) {
			foreach my $newerPublication ( @$newerVersions ) {
				$oTaranisPublication->setPublicationDetails(
					table => "publication_advisory_forward",
					where => { publication_id => $newerPublication->{id} },
					version => \'version::decimal - 0.01'
				);
				$oTaranisPublication->{multiplePublicationsUpdated} = 1;
			}
		}
			
		if ( !$check_1
			|| !$oTaranisPublication->setPublicationDetails( 
				table => "publication_advisory_forward",
				where => { id => $id }, 
				deleted => 1
			) 
			|| !$oTaranisPublication->setPublication( 
				where => { id => $publication->{publication_id} },
				replacedby_id => undef
			)
		) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
			$result = 0;
		} else {
			$result = 1;
		}
			
		$oTaranisTagging->removeItemTag( $id, "publication_advisory_forward" );
			
		if ( $is_update ) {
		my @addTags = keys %tags;
			foreach my $tag_id ( @addTags ) {
				if (  !$oTaranisTagging->setItemTag( $tag_id, "publication_advisory_forward", $previousVersion->{id}  ) ) {
					$self->{errmsg} .= $oTaranisTagging->{errmsg};
				}
			}
		}
	};
	return $result;
}

1;

=head1 NAME

Taranis::Publication::AdvisoryForward

=head1 SYNOPSIS

  use Taranis::Publication::AdvisoryForward;

  my $obj = Taranis::Publication::AdvisoryForward->new( config => $oTaranisConfig, no_db => 1 );

  $obj->deletePublication( $id, $oTaranisPublication );

=head1 DESCRIPTION

Several advisory forward specific functions.

=head1 METHODS

=head2 new( config => $oTaranisConfig, no_db => 1 )

Constructor of the C<Taranis::Publication::AdvisoryForward> module. An object instance of C<Taranis::Config>, which is optional, will be used for creating a database handler.
The parameter C<no_db> is optional. C<no_db> = 1 prevents the constructor from creating a database handler.

    my $obj = Taranis::Publication::AdvisoryForward->new( config => $oTaranisConfig, no_db => 1 );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Sets the scale mapping for damage and probability:

    $obj->{scale}

Returns the blessed object.

=head2 deletePublication( $id, $oTaranisPublication )

Will delete an advisory, but will also do the following:

=over

=item *

restore the replacedby_id of the previous version of the advisory

=item *

update the version number of newer advisories with -0.01

=item *

set the deleted flag of the advisory to TRUE and replacedby_id to NULL

=item *

move the associated tags from current version to previous version.

=back

If successful returns TRUE.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
