# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::CsvBuilder;

use strict;

sub new {
	my ( $class, %args ) = @_;
	
	my $sep_char = ( $args{sep_char} ) ? $args{sep_char} : ',';
	my $quo_char = ( $args{quo_char} ) ? $args{quo_char} : '"';
	
	my $file = ( $args{file} ) ? $args{file}	: 'foo.csv';
	
	my $quote_all = ( exists $args{quote_all} ) ? $args{quote_all} : 1;
	
	my $self = { 
		sep_char => $sep_char,
		quo_char => $quo_char,
		file => $file,
		quote_all => $quote_all,
		csv_string => undef,
		err_msg => undef
	 };

	return( bless( $self, $class ) );
}

sub addLine {
	my ( $self, @line) = @_;
	
	eval{
		foreach my $val ( @line ) {
			$val =~ s/(")/""/g;
			
			if ( $self->{quote_all} || $val =~ /("|[$self->{sep_char}])/g ) {
				$self->{csv_string} .= $self->{quo_char} . $val . $self->{quo_char};
			} else {
				$self->{csv_string} .= $val;
			}
			
			$self->{csv_string} .= $self->{sep_char};
		}
		
		chop $self->{csv_string};
		$self->{csv_string} .= "\n";
	};
	
	if ( $@ ) {
		$self->{err_msg} = $@;
		return 0;
	} else {
		return 1;
	}
}

sub print_csv {
	my $self = shift;
	
	return $self->{csv_string};
}

sub print_error {
	my $self = shift;
	
	return $self->{err_msg};
}

sub csv2file {
	my $self = shift; 
	
	eval{
		my $fh;
  	open( $fh, ">>", $self->{file} );
  	print $fh $self->{csv_string};
  	close $fh;
	};
	
	if ( $@ ) {
		$self->{err_msg} = $@;
		return 0;
	} else {
		return 1;
	}
}

sub clear_csv {
	my $self = shift;
	$self->{csv_string} = '';
	return 1;	
}


=head1 NAME 

Taranis::CsvBuilder - creating as CSV data string and/or file.

=head1 SYNOPSIS

  use Taranis::CsvBuilder;

  my $obj = Taranis::CsvBuilder->new( sep_char => $sep_char, 
                                      quote_all=> $quote_all,
                                      file => $file );

  $obj->addLine( @line );

  $obj->print_csv();

  $obj->print_error();

  $obj->csv2file();

  $obj->clear_csv();

=head1 DESCRIPTION

This module can be used to create a CSV data string and save the CSV to file. 
There are a few options that can used like setting of separator character and quote character. 

=head1 METHODS

=head2 new( sep_char => $sep_char, quote_all=> $quote_all, file => $file )

Constructor of the Taranis::CsvBuilder class:

    my $obj = Taranis::CsvBuilder->new( sep_char  => ',', quote_all => 1, file => '/opt/taranis/test.csv' );

Parameter C<sep_char> stands for separator character, which separates the fields. 
Parameter C<quote_all> adds quotes to all field values (if set to true).
Parameter C<file> sets the filename for output to file.

The object also holds the CSV string.

=head2 addLine( @line )

Method for adding a line to the csv string.

Takes an array as input. The array holds all the values for one line:

    $obj->addLine( ['apple', 'car', 2009, 'etc']);

Returns TRUE if addition is successful. Returns FALSE if addition is unsuccessful and sets the error property of the object.

=head2 print_csv( ) 

Method for retrieving the CSV string:

    $obj->print_csv();

Returns the CSV string.

=head2 print_error( )

Method for retrieving the error message, if present:

    $obj->print_error();

Returns the error message.

=head2 csv2file( )

Method for saving the CSV string to a file:

    $obj->csv2file();

Returns TRUE if saving of file is successful. Returns FALSE if saving of file is unsuccessful and sets the error property of the object.

=head2 clear_csv( )

Empties the CSV string in the object.

    $obj->clear_csv();

Returns TRUE.

=cut

1;
