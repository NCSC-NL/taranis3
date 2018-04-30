# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publication::Advisory;

use Taranis qw(:all);
use Taranis::Config;
use Taranis::Damagedescription;
use Taranis::Database qw(withTransaction);
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::SoftwareHardware;
use SQL::Abstract::More;
use Encode;
use HTML::Entities qw(encode_entities);
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

sub isBasedOn {
	my ( $self, %where ) = @_;
	
	$where{deleted} = 0;
	my ( $stmnt, @bind ) = $self->{sql}->select( "publication_advisory", "based_on, id AS advisory_id, publication_id, govcertid, version", \%where );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @basedOnList;
	while ( $self->{dbh}->nextRecord() ) {
		my $basedOn = $self->{dbh}->getRecord();
		$basedOn->{based_on_id} = ( $basedOn->{based_on} =~ /(.*?) \d\.\d\d$/ )[0];
		$basedOn->{based_on_version} = ( $basedOn->{based_on} =~ /.*? (\d\.\d\d)$/ )[0];
		
		push @basedOnList, $basedOn;
	}
	
	return \@basedOnList;
}

sub getLinksFromXMLAdvisory {
	my ( $self, $xmlAdvisory ) = @_;
	my $advisoryLinks = "";
	if ( ref ( $xmlAdvisory->{content}->{additional_resources}->{resource} ) =~ /^ARRAY$/ ) {
		foreach my $advisoryLink ( @{ $xmlAdvisory->{content}->{additional_resources}->{resource} } ) {
			$advisoryLinks .= $advisoryLink . "\n"; 
		}
		$advisoryLinks =~ s/\n$//;
	} else {
		$advisoryLinks = $xmlAdvisory->{content}->{additional_resources}->{resource};
	}
	return $advisoryLinks;	
}

sub getTitleFromXMLAdvisory {
	my ( $self, $xmlAdvisory ) = @_;
	my $title = encode_entities( $xmlAdvisory->{meta_info}->{title} );
	$title =~ s/.*\[v\d\.\d\d\] \[(?:L|M|H)\/(?:L|M|H)\] (.*?)$/$1/;
	return $title;
}

sub getAdvisoryIDDetailsFromXMLAdvisory {
	my ( $self, $xmlAdvisory ) = @_;
	my %advisoryDetails = ( newAdvisoryVersion => '1.00' );
	
	my $basedOn = $self->isBasedOn( based_on => { ilike => $xmlAdvisory->{meta_info}->{reference_number} . ' %' } );	
	
	if ( @$basedOn > 0 ) {
		$advisoryDetails{newAdvisoryDetailsId} = $basedOn->[0]->{govcertid};
		
		foreach my $basedOnAdvisory ( @$basedOn ) {
			if ( $basedOnAdvisory->{version} >= $advisoryDetails{newAdvisoryVersion} ) {
				$advisoryDetails{newAdvisoryVersion} = $basedOnAdvisory->{version} + 0.01;
				$advisoryDetails{publicationPreviousVersionId} = $basedOnAdvisory->{publication_id};
			}
		}
	} else {
		# this is a first version advisory
		my $advisoryIdLength = ( $self->{config} )
			? $self->{config}->{advisory_id_length}
			: Taranis::Config->getSetting("advisory_id_length");
			
		$advisoryIdLength = 3 if ( !$advisoryIdLength || $advisoryIdLength !~ /^\d+$/ );
		my $advisoryX = '';
		for ( my $i = 1; $i <= $advisoryIdLength; $i++ ) { $advisoryX .= 'X'; }
		
		my $advisoryPrefix = ( $self->{config} ) 
			? $self->{config}->{advisory_prefix}
			: Taranis::Config->getSetting("advisory_prefix");
		
		$advisoryDetails{newAdvisoryDetailsId} = $advisoryPrefix . '-' . nowstring(6) . '-' . $advisoryX;
	}	

	return \%advisoryDetails;
}

sub getSoftwareHardwareFromXMLAdvisory {
	my ( $self, $xmlAdvisory ) = @_;
	
	my $sh = Taranis::SoftwareHardware->new( $self->{config} );
	my %softwareHardwareDetails = (
		products => [],
		platforms => [],
		importProblems => []
	);

	foreach my $shType ( 'product', 'platform' ) {
		my @xmlAdvisorySoftwareHardware = ( ref ( $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{'affected_' . $shType}->{$shType} ) =~ /^ARRAY$/  ) 
			? @{ $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{'affected_' . $shType}->{$shType} }
			: $xmlAdvisory->{meta_info}->{system_information}->{systemdetail}->{'affected_' . $shType}->{$shType};

		my %uniqueSoftwareHardwareIDs;

		foreach my $softwareHardware ( @xmlAdvisorySoftwareHardware ) {
			next if ( !$softwareHardware->{cpe_id} && !$softwareHardware->{producer} && !$softwareHardware->{name} );
			
			my %where = ( $softwareHardware->{cpe_id} ) 
				? ( cpe_id => $softwareHardware->{cpe_id} ) 
				: ( 
					producer => { -ilike => encode_entities( $softwareHardware->{producer} ) },
					name => { -ilike => encode_entities( $softwareHardware->{name} ) }
				);
			$where{deleted} = 0;
				
			if ( exists( $where{producer} ) && $softwareHardware->{version} ) {
				$where{version} = { -ilike => encode_entities( $softwareHardware->{version} ) };
			}

			if ( my $foundSoftwareHardware = $sh->loadCollection( %where ) ) {
				if ( @$foundSoftwareHardware == 1 ) {

					next if ( exists( $uniqueSoftwareHardwareIDs{ $foundSoftwareHardware->[0]->{id} } ) );
					$uniqueSoftwareHardwareIDs{ $foundSoftwareHardware->[0]->{id} } = 1;

					if ( $shType eq 'product') {
						push @{ $softwareHardwareDetails{products} }, $foundSoftwareHardware->[0];
					} else {
						push @{ $softwareHardwareDetails{platforms} }, $foundSoftwareHardware->[0];
					}
				} else {
					my $productDescription = "$softwareHardware->{producer} $softwareHardware->{name}";
					$productDescription .=  " $softwareHardware->{version}" if ( $softwareHardware->{version} );
					$productDescription .= " ($softwareHardware->{cpe_id})" if ( $softwareHardware->{cpe_id} );
					
					if ( @$foundSoftwareHardware > 1 ) {
						push @{ $softwareHardwareDetails{importProblems} }, encode( 'UTF-8', "Found several matches for '$productDescription' during advisory import. Did not link product to advisory. Please check 'Products text', 'Versions text' and 'Platforms text' for references to missing product." );
					} else {
						push @{ $softwareHardwareDetails{importProblems} }, encode( 'UTF-8', "Could not find '$productDescription' during advisory import. Did not link product to advisory. Please check 'Products text', 'Versions text' and 'Platforms text' for references to missing product." );
					}
				}
			}
		}
	}
	
	return \%softwareHardwareDetails;
}

sub getDamageDescriptionsFromXMLAdvisory {
	my ( $self, $xmlAdvisory ) = @_;
	my %damageDescriptions = ( newDamageDescriptions => [], damageDescriptionIds => [] );
	
	my $dd = Taranis::Damagedescription->new( $self->{config} );
	
	my @xmlDamageDescriptions = ( ref ( $xmlAdvisory->{meta_info}->{vulnerability_effect}->{effect} ) =~ /^ARRAY$/  ) 
		? @{ $xmlAdvisory->{meta_info}->{vulnerability_effect}->{effect} }
		: $xmlAdvisory->{meta_info}->{vulnerability_effect}->{effect};
	
	# check whether damage descriptions from XML exist in database,
	foreach my $xmlDamageDescription ( @xmlDamageDescriptions ) {
		$xmlDamageDescription = encode_entities( $xmlDamageDescription );
			
		if ( $xmlDamageDescription ) {
			if ( my $damageDescription = $dd->getDamageDescription( description => { ilike => $xmlDamageDescription } ) ) {
				push @{ $damageDescriptions{damageDescriptionIds} }, $damageDescription->{id};
			} else {
				push @{ $damageDescriptions{newDamageDescriptions} }, $xmlDamageDescription;
			}
		}
	}
	
	return \%damageDescriptions;
}

sub deletePublication {
	my ( $self, $id, $oTaranisPublication ) = @_;
	undef $self->{errmsg};	

	my $oTaranisTagging = Taranis::Tagging->new();

	my $publication = $oTaranisPublication->getPublicationDetails(
		table => "publication_advisory",
		"publication_advisory.id" => $id
	);

	my $is_update = $self->{dbh}->checkIfExists( { replacedby_id => $publication->{publication_id} }, "publication" );

	my $previousVersion;
	my %tags;

	if ( $is_update ) {
		$previousVersion = $oTaranisPublication->getPublicationDetails(
			table => "publication_advisory",
			"pu.replacedby_id" => $publication->{publication_id}
		);
			
		$oTaranisPublication->{previousVersionId} = $previousVersion->{publication_id};
			
		$oTaranisTagging->loadCollection( "ti.item_id" => $id, "ti.item_table_name" => "publication_advisory" );
	
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
					table => "publication_advisory",
					where => { publication_id => $newerPublication->{id} },
					version => \'version::decimal - 0.01'
				);
				$oTaranisPublication->{multiplePublicationsUpdated} = 1;
			}
		}
			
		if ( !$check_1
			|| !$oTaranisPublication->setPublicationDetails( 
				table => "publication_advisory",
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
			
		$oTaranisTagging->removeItemTag( $id, "publication_advisory" );
			
		if ( $is_update ) {
			my @addTags = keys %tags;
			foreach my $tag_id ( @addTags ) {
				if (  !$oTaranisTagging->setItemTag( $tag_id, "publication_advisory", $previousVersion->{id}  ) ) {
					$self->{errmsg} .= $oTaranisTagging->{errmsg};
				}
			}
		}
	};
	return $result;
}

1;

=head1 NAME

Taranis::Publication::Advisory

=head1 SYNOPSIS

  use Taranis::Publication::Advisory;

  my $obj = Taranis::Publication::Advisory->new( config => $oTaranisConfig, no_db => 1 );

  $obj->deletePublication( $id, $oTaranisPublication );

  $obj->getAdvisoryIDDetailsFromXMLAdvisory( $xmlAdvisory );

  $obj->getDamageDescriptionsFromXMLAdvisory( $xmlAdvisory );

  $obj->getLinksFromXMLAdvisory( $xmlAdvisory );

  $obj->getSoftwareHardwareFromXMLAdvisory( $xmlAdvisory );

  $obj->getTitleFromXMLAdvisory( $xmlAdvisory );

  $obj->isBasedOn( %where );

=head1 DESCRIPTION

Several advisory specific functions, which are mostly used for handling XML advisory.

=head1 METHODS

=head2 new( config => $oTaranisConfig, no_db => 1 )

Constructor of the C<Taranis::Publication::Advisory> module. An object instance of C<Taranis::Config>, which is optional, will be used for creating a database handler.
The parameter C<no_db> is optional. C<no_db> = 1 prevents the constructor from creating a database handler.

    my $obj = Taranis::Publication::Advisory->new( config => $oTaranisConfig, no_db => 1 );

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

=head2 getAdvisoryIDDetailsFromXMLAdvisory( $xmlAdvisory )

Will retrieve advisory ID details like advisory ID and version from an XML advisory. C<< $xmlAdvisory >> is an instance of Perl module C<XML::Simple>. 

    $obj->getAdvisoryIDDetailsFromXMLAdvisory( XML::Simple );

Returns an HASH reference.

=head2 getDamageDescriptionsFromXMLAdvisory( $xmlAdvisory )

Will retrieve damage descriptions from an XML advisory. It will check if the damage description in the XML advisory exists in database.
C<< $xmlAdvisory >> is an instance of Perl module C<XML::Simple>.

    $obj->getDamageDescriptionsFromXMLAdvisory( XML::Simple );

Returns an HASH reference.

=head2 getLinksFromXMLAdvisory( $xmlAdvisory )

Will retrieve links from an XML advisory. It will concatenate the links, separated by a newline.
C<< $xmlAdvisory >> is an instance of Perl module C<XML::Simple>.

    $obj->getLinksFromXMLAdvisory( XML::Simple );

Returns a STRING of links, separated by newlines.

=head2 getSoftwareHardwareFromXMLAdvisory( $xmlAdvisory )

Will retrieve software and hardware from an XML advisory. It will check if the S/H from the XML advisory also exists in database, if not it will append an error to the list of C<importProblems>.
C<< $xmlAdvisory >> is an instance of Perl module C<XML::Simple>.

    $obj->getSoftwareHardwareFromXMLAdvisory( XML::Simple );

Returns an HASH reference.

=head2 getTitleFromXMLAdvisory( $xmlAdvisory )

Will retrieve the title from an XML advisory. It will strip of the advisory ID, version and damage and probability scaling.
C<< $xmlAdvisory >> is an instance of Perl module C<XML::Simple>.

    $obj->getTitleFromXMLAdvisory( XML::Simple );

Returns the title as STRING.

=head2 isBasedOn( %where )

Retrieves a list of advisories with specifc based_on setting.

    $obj->isBasedOn( based_on => 'NCSC-2014-0001%' );

Returns an ARRAY reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
