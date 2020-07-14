# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Config::XMLGeneric;

use strict;
use warnings;
use XML::Simple;
use List::Util  qw(first);
use Taranis     qw(find_config);

use Taranis::Config;

my ($xs, $cdatastart, $cdataclose);

BEGIN {
	$xs = XML::Simple->new(NormaliseSpace => 2, SuppressEmpty => '');
	$cdatastart = '<![CDATA[';
	$cdataclose = ']]>';
}

sub new {
	my ($class, $configFile, $primaryKey, $rootName, $normalise) = @_;
	my $normaliseSpace = defined $normalise && $normalise =~ /([012])/ ? $1 : 2;

	my $fn  = find_config $configFile;
	my $xml = $xs->XMLin($fn,
		ForceArray     => qr/anon/,
		NormaliseSpace => $normaliseSpace
	);

	bless {
		primary_key => $primaryKey,
		root_name   => $rootName,
		config_file => $configFile,
		elements    => $xml,
	}, $class;
}

sub loadCollection {
	my ($self, $arg) = @_;

	my $elements = $self->{elements};
	$arg or return $elements;

	$arg =~ s/\+/\\+/g;
	[ grep $_->{$self->{primary_key}} =~ /$arg/i, @$elements ];
}

sub loadCollectionBySearchField {
	my ($self, $search_field, $search_value, $match_type) = @_;

	my $elements = $self->{elements};
	my $search = $match_type eq "EXACT_MATCH" ?
		qr/^$search_value$/i : qr/$search_value/i;

	[ grep $_->{$search_field} =~ $search, @$elements ];
}

sub getElement {
	my ($self, $arg) = @_;
	my $elements = $self->{elements};

	# escape + sign with \+ for regex in foreach below
	$arg =~ s/\+/\\+/g;

	first { $_->{$self->{primary_key}} =~ /^$arg$/i } @$elements;
}

sub _cdata($) {
	my ($self, $data) = @_;
	my %element;
	while( my ($key, $value) = each %$data) {
		$element{$key} = defined $value && length $value
			? "$cdatastart$value$cdataclose" : '';
	}
	\%element;
}

sub _writeXML {
	my $self    = shift;
	my @out     = map $self->_cdata($_), @{$self->{elements}};
	my $outfile = $self->{config_file};

	open my $fh, ">", $outfile
		or die "Cannot write $outfile: $!\n";

	eval {
		XMLout(\@out, NoAttr => 1, RootName => $self->{root_name},
		 NoEscape => 1, OutputFile => $fh, SuppressEmpty => '' , XMLDecl => 1);
	};
	if($@) {
		$self->{errmsg} = $@;
		return 0;
	}

	close $fh
		or die "ERROR: errors while writing file $outfile: $!\n";

	return 1;
}

sub addElement {
	my ($self, %element) = @_;
	push @{$self->{elements}}, \%element;
	$self->_writeXML;
}

sub setElement {
	my ($self, %element) = @_;
	my $elements = $self->{elements};
	my $prim     = $self->{primary_key};
	my $orig     = delete $element{"orig_$prim"};

	for(my $i = 0; $i <@$elements; $i++) {
		if($elements->[$i]->{$prim} eq $orig) {
			$elements->[$i] = \%element;
			last;
		}
	}
	$self->_writeXML;
}

sub deleteElement {
	my ($self, $name) = @_;
	my $elements = $self->{elements};
	my $prim     = $self->{primary_key};

	for(my $i = 0; $i <@$elements; $i++) {
		if($elements->[$i]->{$prim} eq $name) {
			splice @$elements, $i, 1;
			last;
		}
	}

	$self->_writeXML;
}

sub checkIfExists {
	my ($self, $name) = @_;
	my $elements = $self->{elements};

	$name =~ s/\+/\\+/g;
	my $count = grep $_->{$self->{primary_key}} =~ /^$name$/i, @$elements;
	$count;
}

1;

=head1 NAME

Taranis::Config::XMLGeneric

=head1 SYNOPSIS

  use Taranis::Config::XMLGeneric;

  my $obj = Taranis::Config::XMLGeneric->new( $configFile, $primaryKey, $rootName, $normaliseSpace );

  $obj->loadCollection( [ $search_string ] );

  $obj->loadCollectionBySearchField( $search_field, $search_value, $match_type );

  $obj->getElement( $searchString );

  $obj->_writeXML();

  $obj->addElement( %elementContents );

  $obj->setElement( orig_name => $orginal_value_of_primary_key_field , $key1 => $value1, ... );

  $obj->deleteElement( $value_of_primary_key_field );

  $obj->checkIfExists( $value_of_primary_key_field );

=head1 DESCRIPTION

CRUD functionality for Taranis XML configuration files.

=head1 METHODS

=head2 new( $configFile, $primaryKey, $rootName, $normaliseSpace )

Constructor of the Taranis::Config::XMLGeneric module. Calling new will create a new blessed object.

=over

=item *

C<< $configFile >> is the absolute path of the XML configuration file.

=item *

C<< $primaryKey >> is the 'primary key'. This means values of these field should always be unique.

=item *

C<< $rootName >> is the root element name of the XML config file.

=item *

C<< $normaliseSpace >> is the C<NormaliseSpace> setting of Perl module C<XML::Simple>. Possible values are 0, 1 and 2.

=back

    $obj = Taranis::Config::XMLGeneric->new( "taranis.tools.conf.xml", "toolname", "tools", 0 );

Returns the blessed object with the parsed XML set in the C<elements> key.

=head2 loadCollection( $searchString )

Loads elements of the XML confifuration file. The returned elements can be filtered by the setting C<$arg>, which will be used to search all 'primary key' elements.

    $obj->loadCollection( 'ncsc' );

To retrieve all data from the object, call method without arguments:

    $obj->loadCollection();

Returns an ARRAY reference with matching elements.

=head2 loadCollectionBySearchField( $search_field, $search_value, $match_type )

Searches selected elements.

=over

=item *

C<< $search_field >> is the name of the element to search

=item *

C<< $search_value >> is the searchstring.

=item *

C<< $match_type >> is the type of search. There are two options: exact matching (specify 'EXACT_MATCH'), and non exact matching (any string will do).

=back

    $obj->loadCollectionBySearchField( 'host', 'www.ncsc.nl', 'EXACT_MATCH' );

Returns matching elements.

=head2 getElement( $searchString )

Retrieves one element. C<< $searchString >> is mandatory, which is used to do an exact match search.

    $obj->getElement( 'quickndirty' );

Returns an HASH reference with matching element.

=head2 _writeXML()

Writes the data stored in the $obj->{elements} to file (XML) using C<XML::Simple->XMLout()>

    $obj->_writeXML();

Returns TRUE if successful. Returns FALSE if unsuccessful and sets $obj->{errmsg} to the corresponding error.

=head2 addElement( %elementContents )

Adds an element to XML configuration file.
C<< %elementContents >> is a serie of key, value pairs.

    $obj->addElement( idname => 'myIdName', pattern => '.*?', substitute => 'mySubstritue' );

Calls C<< _writeXML() >> to write file to disk and returns C<< _writeXML() >> result.

=head2 setElement( orig_name => $orginal_value_of_primary_key_field , $key1 => $value1, ... )

Used to update an element.

Parameter C<orig_myelement> is mandatory and differs for each configuration file. The keyname is split into two parts: 'orig_' and the name of the 'parimary key'.
Other parameter are key => value pairs that correspond to the content of element.

    $obj->setElement( orig_name => 'quickndirty', link_prefix => 'test' );

Calls C<< _writeXML() >> to write file to disk and returns C<< _writeXML() >> result.

=head2 deleteElement( $value_of_primary_key_field )

Deletes matching element and writes XML configuration file to disk using C<_writeXML()>.
The value of the primary key of the element is mandatory.

    $obj->deleteObject( 'quickndirty' );

Calls C<< _writeXML() >> to write file to disk and returns C<< _writeXML() >> result.

=head2 checkIfExists( $value_of_primary_key_field )

Checks if an element with C<< $value_of_primary_key_field >> exists.

    $obj->checkIfExists( 'quickndirty' );

Returns the number of elements that match the primary key value. (This should however always return 1 or 0).

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<error in XML '...'>

Caused by new() when Perl module C<XML::Simple> can't read or parse the XML file.
You should check the XML file rights and content.

=item *

I<error in XML '...'>

Caused by loadCollection() or loadCollectionBySearchField() or getElement() when C<< $self->{elements} >> is not an ARRAY.
You should check the XML file rights and content.

=item *

I<Default options must be name=>value pairs (odd number supplied)>
Caused by addElement() or setElement() when arguments are not key, value pairs.

=back

=cut
