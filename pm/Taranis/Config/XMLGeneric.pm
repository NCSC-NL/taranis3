# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Config::XMLGeneric;

use strict;
use XML::Simple;
use Taranis::Config;
use Taranis qw(:all);

my ($xs, $cdatastart, $cdataclose);

BEGIN {
	$xs = new XML::Simple( NormaliseSpace => 2, SuppressEmpty => '' );
	$cdatastart = '<![CDATA[';
	$cdataclose = ']]>';
}

sub new {
	my ( $class, $fn, $primaryKey, $rootName, $normaliseSpace ) = @_;
	my $configFile = find_config $fn;
	
	my $self = {
		primary_key => $primaryKey,
		root_name => $rootName,
		config_file => $configFile,
	};

	$normaliseSpace = ( $normaliseSpace =~ /(0|1|2)/) ? $normaliseSpace : 2;

	my $xml = $xs->XMLin( $configFile, ForceArray => qr/anon/ , NormaliseSpace => $normaliseSpace);
	$self->{elements} = $xml;

	return( bless( $self, $class ) );
}

sub loadCollection {
	my ( $self, $arg ) = @_;
	my $coll;
	if ( $arg && $self->{elements} ) {
		my @elements = eval {@{ $self->{elements} }};
		if ($@) { 
			$self->{errmsg} = "error in XML $! $@\n";
			return 0;
		}
		$arg =~ s/\+/\\\+/g; 
		foreach my $element (@elements) {
			if ( $element->{$self->{primary_key}} =~ /.*$arg.*/i ) {
				push ( @$coll, $element );
			}
		}
	} else {
		$coll = $self->{elements};
	}
	return $coll;
}

sub loadCollectionBySearchField {
	my $self = shift;

	my $search_field = $_[0];
	my $search_value = $_[1];
	my $match_type 	 = $_[2]; 

	my $coll;
	my $search;

	my @elements = eval {@{ $self->{elements} }};
	if ($@) { 
		$self->{errmsg} = "error in XML $! $@\n"; 
		return 0;
	}

	$search = ( $match_type eq "EXACT_MATCH" ) ? "^$search_value\$" : ".*$search_value.*";

	foreach my $element (@elements) {
		if ( $element->{ $search_field } =~ /$search/i ) {
			push ( @$coll, $element );
		}
	}
	return $coll;
}

sub getElement {
	my ( $self, $arg ) = @_;

	my @elements = eval {@{ $self->{elements} }};
	if ($@) { 
		$self->{errmsg} = "error in XML $! $@\n"; 
		return 0;
	}

	# escape + sign with \+ for regex in foreach below 
	$arg =~ s/\+/\\\+/g; 

	foreach my $element (@elements) {
		if ( $element->{$self->{primary_key}} =~ /^$arg$/i ) {
			return $element;
		}
	}
	return;
}

sub _writeXML {
	my ( $self ) = @_;

	my $out =  $self->{elements};
	my $outfile = $self->{config_file};

	my $fh;
	eval{
		open $fh, ">", $outfile; #or logErrorToSyslog("open($outfile): $!");
	};
	if ( $@ ) {
		$self->{errmsg} = $@;
		return 0;
	}

	eval{
		XMLout( $out, NoAttr => 1, RootName => $self->{root_name}, NoEscape => 1, OutputFile => $fh, SuppressEmpty => '' , XMLDecl => 1);
	};
	if ( $@ ) {
		$self->{errmsg} = $@;
		return 0;
	}

	eval{
		close $fh;
	};
	if ( $@ ) {
		$self->{errmsg} = $@;
		return 0;
	}

	return 1;
}

sub addElement {
	my ( $self, @arg ) = @_;

	if ( @arg % 2 ) {
		$self->{errmsg} = "Default options must be name=>value pairs (odd number supplied)";
	}

	my %new_element = @arg;

	my $index;
	if ( $self->{elements} ) {
		$index = @{ $self->{elements} };
	} else {
		$index = 0;
		$self->{elements} = [];
	}

	foreach my $key ( keys %new_element ) {
		if ( q($new_element{$key}) ) {
			$self->{elements}->[$index]->{$key} = $cdatastart . $new_element{$key} . $cdataclose;
		} else {
			$self->{elements}->[$index]->{$key} = "";
		}
	}

	for ( my $i = 0 ; $i < $index ; $i++ ) {
		my $element = $self->{elements}->[$i];
		foreach my $key ( keys %$element ) {
			$self->{elements}->[$i]->{$key} = $cdatastart . $self->{elements}->[$i]->{$key} . $cdataclose if ( q($self->{elements}->[$i]->{$key}) );
		}
	}

	return $self->_writeXML();
}

sub setElement {
	my ( $self, @arg ) = @_;

	if ( @arg % 2 ) {
		$self->{errmsg} = "Default options must be name=>value pairs (odd number supplied)";
		return 0;
	}

	my %element = @arg;
	my $index = @{ $self->{elements} };

	for ( my $i = 0 ; $i < $index ; $i++ ) {
		my $orig_name = "orig_".$self->{primary_key};
		if ( $self->{elements}->[$i]->{ $self->{primary_key} } eq $element{$orig_name} ) {
			delete $element{$orig_name};
			foreach my $key ( keys %element ) {
				if ( q($element{$key}) ) {
					$self->{elements}->[$i]->{$key} = $cdatastart . $element{$key} . $cdataclose;
				} else {
					$self->{elements}->[$i]->{$key} = "";
				}
			}
			next;
		} 

		my $element = $self->{elements}->[$i];
		foreach my $key ( keys %$element ) {
			$self->{elements}->[$i]->{$key} = $cdatastart . $self->{elements}->[$i]->{$key} . $cdataclose if ( q($self->{elements}->[$i]->{$key}) );
		}
	}
	return $self->_writeXML();
}

sub deleteElement {
	my ( $self, $elementname ) = @_;

	my $index = @{ $self->{elements} };

	for ( my $i = 0 ; $i < $index; $i++ ) {
		if ( $self->{elements}->[$i]->{ $self->{primary_key} } eq $elementname ) {
			splice (@{$self->{elements}}, $i, 1);
			last;
		}
	}

	$index = @{ $self->{elements} };

	for ( my $i = 0 ; $i < $index ; $i++ ) {
		my $element = $self->{elements}->[$i];
		foreach my $key ( keys %$element ) {
			$self->{elements}->[$i]->{$key} = $cdatastart . $self->{elements}->[$i]->{$key} . $cdataclose if ( $self->{elements}->[$i]->{$key} );
		}
	}
	
	return $self->_writeXML();
}

sub checkIfExists {
	my ( $self, $elementname ) = @_;

	# escape + sign with \+ for regex below

	$elementname =~ s/\+/\\\+/g;
	my $count = 0;
	if ( $self->{elements} ) {
		my @elements = @{ $self->{elements} };	

		foreach my $element (@elements) {
			if ( $element->{ $self->{primary_key} } =~ /^$elementname$/i ) {
				$count++;
			}
		}
	}
	return $count;
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
