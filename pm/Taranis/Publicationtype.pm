# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publicationtype;

use Taranis qw(:util);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Data::Validate qw(is_integer);
use SQL::Abstract::More;
use Tie::IxHash;
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg 	=> undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub getPublicationTypeIds { # by constituent individual ID
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	my @type_ids;
		
	if ( !defined( $id ) || !is_integer( $id ) ) {
		$self->{errmsg} = "Invalid parameter!";
		return 0;
	}

	my %where = ( "ci.id" => $id );
	
	tie my %join, "Tie::IxHash";
	my ( $stmnt, @bind ) = $self->{sql}->select("publication_type AS pt", "pt.id", \%where );
	%join = ( 
		"JOIN constituent_publication AS cp" => { "cp.type_id" => "pt.id" },
		"JOIN constituent_individual AS ci" => { "ci.id" => "cp.constituent_id" }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} )) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		while ( $self->nextObject ) {
			push( @type_ids, $self->getObject->{id} );
		}
		return @type_ids;
	}	
}

sub getPublicationTypes {
  my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};
	my %where;
	
	tie my %join, "Tie::IxHash";
		
	for my $key ( keys ( %searchFields ) ) {
		if ( $key eq "cg.id" || ref $searchFields{$key} eq 'ARRAY') {
			$where{$key} = \@{ $searchFields{$key} };
		} elsif ( defined( is_integer( $searchFields{$key} ) ) ) {
			$where{$key} = $searchFields{$key};
		} elsif ( $searchFields{$key} ne "" ) {
			$where{$key}{-ilike} = "%".trim($searchFields{$key})."%";
		}
	}	

	my $select = "pt.*";
	$select .= ", min(cg.status) as group_status" if ( exists( $searchFields{"ci.id"} ) || exists( $searchFields{"cg.id"} ) );

	my ( $stmnt, @bind ) = $self->{sql}->select( "publication_type AS pt", $select, \%where, "pt.title"); 

	if ( exists( $searchFields{"ci.id"} ) ) {
		%join = ( 
			"JOIN type_publication_constituent AS tpc" => { "tpc.publication_type_id" => "pt.id" },
			"JOIN constituent_group AS cg" => { "cg.constituent_type" => "tpc.constituent_type_id" },
			"JOIN membership AS m" => { "m.group_id" => "cg.id" },
			"JOIN constituent_individual AS ci" => { "ci.id" => "m.constituent_id" }
		);
	} elsif ( exists( $searchFields{"cg.id"} ) ) {
		%join = (
			"JOIN type_publication_constituent AS tpc" => { "tpc.publication_type_id" => "pt.id" },
			"JOIN constituent_group AS cg" => { "cg.constituent_type" => "tpc.constituent_type_id" }
		);
	} elsif ( exists( $where{"ct.id"} ) || exists( $where{"ct.type_description"} ) ) {
		%join = (
			"JOIN type_publication_constituent AS tpc" => { "tpc.publication_type_id" => "pt.id" },
			"JOIN constituent_type AS ct" => { "ct.id" => "tpc.constituent_type_id" }
		);
	}
	
	if ( keys %join ) {
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		$stmnt =~ s/(ORDER.*)/ GROUP BY pt.id, pt.title, pt.description $1/i;
	}

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} .= $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	return $result;
	
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;
}

1;
=head1 NAME 

Taranis::Publicationtype

=head1 SYNOPSIS

  use Taranis::Publicationtype;

  my $obj = Taranis::Publicationtype->new( $oTaranisConfig );
  
  $obj->getPublicationTypeIds( $constituent_individual_id );
  
  $obj->getPublicationtypes( %where );

=head1 DESCRIPTION

Module for retrieval of pubication types and retrieval of list of constituent individuals for a specific publication type.

=head1 METHODS

=head2 new( $oTaranisConfig )

Constructor for the Taranis::Publicationtype module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Publicationtype->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};
	  
Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Returns the blessed object.

=head2 getPublicationTypeIds( $constituent_individual_id )

Retrieves the id's of publication types.

    $obj->getPublicationTypeIds( 24 );
  
If successful returns an ARRAY. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
  
=head2 getPublicationtypes( %where )

Retrieves publication types.

Takes arguments that correspond with table columns of different tables. A column name is preceeded by a table alias:

=over

=item ci. for constituent_individual

=item cg. for consitituen_group

=item ct. for constituent_type

=item pt. for publication_type

=back

For instance 'ci.id' corresponds with the column id of table constituent_individual:

    $obj->getPublicationTypes( 'ci.id' => 23 );  

To retrieve all publication types:

    $obj->getPublicationtype();	

Note: for argument 'cg.id' a list of id's is expected:

    $obj->getPublicationTypes( 'cg.id' => \@group_ids );

Also: it is not possible to combine one of the following: 'ci.id', 'cg.id' and  'ct.id'.

Returns the return value of DBI->execute(). Sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameter!>

Caused by getPublicationTypeIds() when parameter C<$constituent_individual_id> is not a number.
You should check parameter C<$constituent_individual_id>.

=back

=cut
