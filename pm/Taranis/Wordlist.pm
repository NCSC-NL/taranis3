# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Wordlist;

use strict;
use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use JSON;
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

sub addWordlist {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $wordlistID = $self->{dbh}->addObject( 'wordlist', \%inserts, 1 ) ) {
		return $wordlistID;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteWordlist {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	
	if ( $self->{dbh}->deleteObject( 'wordlist', { id => $id } ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getWordlist {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'wordlist', '*', \%where, 'description' );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @wordlists;
	while ( $self->{dbh}->nextRecord() ) {
		my $wordlist = $self->{dbh}->getRecord();
		$wordlist->{words} = from_json( $wordlist->{words_json} );
		push @wordlists, $wordlist;
	}
	
	return \@wordlists;
}

sub setWordlist {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	$settings{words_json} = to_json( delete( $settings{words} ) ) if ( $settings{words} );
	
	if ( $self->{dbh}->setObject( 'wordlist', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub cleanWordlist {
	my ( $self, $words ) = @_;
	
	my %uniqueWords = map { trim( lc( $_ ) ) => trim( $_ ) } @$words;
	
	my @list;
	foreach my $word ( values %uniqueWords ) {
		push @list, $word if ( $word );
	}
	
	return \@list;
}

1;

=head1 NAME

Taranis::Wordlist

=head1 SYNOPSIS

  use Taranis::Wordlist;

  my $obj = Taranis::Wordlist->new( $oTaranisConfig );

  $obj->addWordlist( %wordlist );

  $obj->cleanWordlist( \@words );

  $obj->deleteWordlist( $wordlistID );

  $obj->getWordlist( %where );

  $obj->setWordlist( id => $wordlistID, %wordlist );

=head1 DESCRIPTION

CRUD functionality for wordlists.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Wordlist> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Wordlist->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addWordlist( %wordlist )

Adds a new wordlist. 

    $obj->addWordlist( description => 'evil words', words_json => '["backdoor","exploit","Zero Day","metasploit"]' );

If successful returns the wordlist ID of the newly added wordlist.
If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 cleanWordlist( \@words )

Removes double entries and removes undef/' ' entries.

    $obj->cleanWordlist( [ 'word1', 'word2 ', 'word1' ] );

Returns an ARRAY reference.

=head2 deleteWordlist( $wordlistID )

Deletes a wordlist. Parameter C<$wordlistID> is mandatory.

    $obj->deleteWordlist( 87 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getWordlist( %where )

Retrieves wordlists selected by C<%where> parameter.

    $obj->getWordlist( id => $wordlistID );

OR

    $obj->getWordlist( words_json => { -ilike => '%zero%' } );

OR

    $obj->getWordlist();

Returns an ARRAY reference.

=head2 setWordlist( id => $wordlistID, %wordlist )

Updates a wordlist. Parameter C<id> is mandatory.

    $obj->setWordlist( id => 98, words_json => '["backdoor","exploit","Zero Day","metasploit", "virus"]' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setWordlist() when C<id> is not set.
You should check C<id> setting.

=back

=cut
