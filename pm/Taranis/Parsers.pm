# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Parsers;

use strict;
use Taranis qw(:util);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub getParsers {
	my ( $self, $parsername ) = @_;
	undef $self->{errmsg};

	my %where;
	if ( $parsername ) {
		$where{parsername} = { -ilike => [ '%' . trim($parsername) . '%' ] };
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'parsers', '*', \%where, 'parsername' );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	
	my @parsers;
	while ( $self->nextObject() ) {
		push @parsers, $self->getObject();
	}
	return \@parsers;
}

#TODO: merge getParser() & getParserSimple()
sub getParser {
	my ( $self, $parserName ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->select( 'parsers', "*", { parsername => $parserName }, 'parsername' );
	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	my $hash_ref = $self->{dbh}->{sth}->fetchall_hashref('parsername');
	my $parser;
	while ( my ( $uKey, $uVal ) = ( each %$hash_ref ) ) {
		while ( my ( $key, $val ) = ( each %$uVal ) ) {
			if (defined $val) {
				$parser->{$key} = $val ;
			} else {
				$parser->{$key} = ''; #  emulate XMLGeneric behaviour
			}
		}
	}

	return $parser;
}

sub getParserSimple {
	my ( $self, $parsername ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->select( 'parsers', "*", { parsername => $parsername }, 'parsername' );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return $self->{dbh}->fetchRow();
}

sub addParser {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};

	if ( !defined( $inserts{parsername} ) ) {
		$self->{errmsg} = "Cannot add a parser without a name";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'parsers', \%inserts );

	$self->{dbh}->prepare($stmnt);

	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setParser {
	my ( $self, %update ) = @_;
	undef $self->{errmsg};

	if ( !defined( $update{parsername} ) ) {
		$self->{errmsg} = "Invalid input.";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( 'parsers', \%update, { parsername => delete( $update{parsername} ) } );

	$self->{dbh}->prepare($stmnt);

	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined($result) && ($result !~ m/(0E0)/i ) ) {		
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Update failed, corresponding parser not found in database.";
		return 0;
	}
}

sub deleteParser {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	if ( !defined( $where{parsername} ) ) {
		$self->{errmsg} = "no parsername supplied";
		return 0;
	}

	###################################################################
	# check if there are any sources records connected to this parser #
	###################################################################
	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources', 'count(*) as cnt', { parser => $where{parsername} } );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	my $sourcesCount = $self->{dbh}->fetchRow();

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
	
	if ( $sourcesCount->{cnt} > 0 ) {
		$self->{errmsg} = 'There are ' . $sourcesCount->{cnt} . ' sources which use to this parser';
		return 0;
	}

	( $stmnt, @bind ) = $self->{dbh}->{sql}->delete( 'parsers', \%where );

	$self->{dbh}->prepare($stmnt);
	my $result = $self->{dbh}->executeWithBinds(@bind);
	if ( defined($result) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = "Delete failed, corresponding id not found in database.";
		return 0;
	}
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}

1;

=head1 NAME 

Taranis::Parsers

=head1 SYNOPSIS 

  use Taranis::Parsers;

  my $obj = Taranis::Parsers->new( $oTaranisConfig );

  $obj->addParser( %parser );

  $obj->deleteParser( %where );

  $obj->getParser( $parserName );

  $obj->getParsers( $parserName );

  $obj->getParserSimple( $parserName );

  $obj->setParser( parsername => $parserName, ... );

=head1 DESCRIPTION

Parsers are used for parsing sources. It extracts source items from source data. 
After which it will retrieve a title, a description and a link from a source item.
This module contains CRUD functionality for parsers.

=head1 METHODS

=head2 new( $oTaranisConfig )

Constructor of the C<Taranis::Parsers> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Parsers->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addParser( %parser )

Adds a new parser. Parameter C<parsername> is mandatory.

    $obj->addParser(
        'item_stop' => '&lt;/tr&gt;',
        'link_stop' => '\\&quot;',
        'title_stop' => '&lt;',
        'title_start' => '450px;\\&quot;&gt;',
        'strip1_start' => 'OSVDB\\ News',
        'strip0_start' => 'DOCTYPE',
        'parsername' => 'html:osvdb',
        'strip0_stop' => 'ader\\&amp;quot;&amp;gt;Latest\\ OSVDB\\ Vulnerabilities',
        'item_start' => '&lt;tr&gt;',
        'strip1_stop' => '&amp;lt;\\/html&amp;gt;',
        'link_prefix' => 'http://osvdb.org',
        'link_start' => 'href=\\&quot;' 
    );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteParser( %where )

Deletes a parser. Parameter C<parsername> is mandatory.
Also checks if the parser is in use by a source.

    $obj->deleteParser( parsername => 'html:ncsc' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getParser( $parserName ) & getParserSimple( $parserName )

Retrieve parser details. Parameter C<$parserName> is mandatory.

    $obj->getParser( $parsername );

Returns HASH reference.

=head2 getParsers( $parserName )

Retrieves a list of parsers. Parameter C<$parserName> is optional.

    $obj->getParsers();

Returns an ARRAY reference.

=head2 setParser( parsername => $parserName, ... )

Updates a parser. Parameter C<parsername> is mandatory.

    $obj->setParser( parsername => 'html:ncsc', link_prefix => undef, link_start => '<a href=' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Cannot add a parser without a name> & I<Invalid input>

Caused by addParser() or setParser() parameter C<parsername> is not set.
You should check if C<parsername> is defined.

=item *

I<Update failed, corresponding parser not found in database.>

Caused by setParser() when there is no parser with the set parsername.
You should check parameter C<parsername>.

=back

=cut
