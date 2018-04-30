# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Config::Stats;
use strict;

use XML::Simple;
use Taranis qw(:util);

sub new {
	my $class = shift;

	my $self = { errmsg => undef };

	return( bless( $self, $class ) );
}

sub loadCollection {
	my ( $self, $configFile ) = @_;	

	my $xs = XML::Simple->new( NormaliseSpace => 2 );
	my $stats = eval { $xs->XMLin(find_config $configFile ) };
	
	if ( $@ ) {
		$self->{errmsg} = "Error in Stats XML: " . $@;
		return 0;  
	}
	my $stat = $stats->{stat} || [];
	bless $stat, ref $self;
}

1;

=head1 NAME

Taranis::Config::Stats - Read Taranis stats configuration file (XML).

=head1 SYNOPSIS

  use Taranis::Config::Stats;

  my $obj = Taranis::Config::Stats->new();

  $obj->loadCollection( $configFile );

=head1 DESCRIPTION

Module for reading the XML stats configuration file.

=head1 METHODS

=head2 new()

Constructor of the C<Taranis::Config::Stats> module. Returns the blessed object.

=head2 loadCollection( $configFile );

Will parse C<< $configFile >> with C<XML::Simple>.

    $obj->loadCollection( 'taranis.conf.stats.xml' );

If successful Returns a blessed ARRAY of HASH references.
If unsuccessful it will return 0 and set C<< $obj->{errmsg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Error in Stats XML: '...'>

Caused by loadCollection() when C<XML::Simple> causes an error.
You should check the set configuration file. 

=back

=cut
