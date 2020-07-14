# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::TemplateModule;

use strict;
use Taranis::Collector;

sub new {
	my ( $class, $config, $debugSource ) = @_;
	
	my $self = {
		collector => Taranis::Collector->new( $config, $debugSource )
	};
	
	return( bless( $self, $class ) );
}

# there are two scenarios:
# 1. collect and process all found links
#		-> return 1 or set $self->{errmsg} and return 0
# 2. collect all found links and let the collector script process the found links
#		-> return \@foundLinks or set $self->{errmsg} and return 0
#		-> each item in @foundLinks is a Hash with the following keys: itemDigest, link, description and title
sub collect {
	my ( $self, $sourceData, $source, $debugSource ) = @_;
	
	# scenario 1
	if ( 'all is well' ) {
		return 1
	} else {
		$self->{errmsg} = 'some error';
		return 0;
	}
	
	# scenario 2
	my @foundLinks;
	push @foundLinks, { itemDigest => 'md5 hash of item', 'link' => 'the url of the item', description => 'description text', title => 'title of item' };
		
	if ( 'all is well' ) {
		return \@foundLinks;
	} else {
		$self->{errmsg} = 'some error';
		return 0;
	}
}

sub getAdditionalConfigKeys {
	return []; # list of additional keys; 'collector_module' can be left out
}
sub testCollector {
	return "some text message containing the test result";
}

# 'getSourceData' is optional. 
# If not specified, the sub in Taranis::Collector will be used.
sub getSourceData {
	my ( $self, $url, $source, $debugSource ) = @_;
	# May return anything as long as collect() can understand it.
}

1;

=head1 NAME

Taranis::Collector::TemplateModule - Template for new feed collector modules

=head1 SYNOPSIS

  use Taranis::Collector::TemplateModule;

  my $obj = Taranis::Collector::TemplateModule->new( $objTaranisConfig, $debugSource );

  $obj->collect( $sourceData, $source, $debugSourceName );

  $obj->getAdditionalConfigKeys();

  $obj->testCollector();

  $obj->getSourceData();

=head1 DESCRIPTION

Example file to aid in the creation of new feed collector modules.

=head1 METHODS

=head2 new( $objTaranisConfig, $debugSource )

Constructor of the C<Taranis::Collector::TemplateModule> module.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

    my $obj = Taranis::Collector::Twitter->new( $objTaranisConfig, 'Some Source Name' );

Creates a new collector instance. Can be accessed by:

    $obj->{collector};

Returns the blessed object.

=head2 collect( $sourceData, $source, $debugSourceName );

Should parse retrieved data. Parameters %sourceData and %source are mandatory.

Optionally a sourcename can be supplied for debugging. This will generate debug output to stdout.

Returns an ARRAY of HASH references with the following keys: itemDigest, link, description, title, status, matching_keywords (=ARRAY reference).

=head2 getAdditionalConfigKeys();

Should return a list of additional keys. 'collector_module' can be left out. 

=head2 testCollector();

returns a text message containing the test result.

=head2 getSourceData();

=cut
