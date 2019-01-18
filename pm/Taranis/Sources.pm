# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Sources;

use strict;
use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use GD::Simple;
use JSON;

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		dbh => Database,
		sql => Sql,
		errmsg => ''
	};

	return( bless( $self, $class ) );
}

*addElement = \&addSource;

sub addSource {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'sources', \%args );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}


*loadCollection = \&getSources;

sub getSources {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	my $offset = delete $where{offset};
	my $limit  = delete $where{limit};

	# 'ANY' added for backwards compatibility: there was no way to select
	# both the deleted and non-deleted, because '0' was the hard default.
	if(!exists $where{deleted})     { $where{deleted} = 0 }
	elsif($where{deleted} eq 'ANY') { delete $where{deleted} }

	my $select = "s.id, s.digest, s.fullurl, s.host, s.mailbox, s.mtbc, s.parser, s.username, "
		. "s.password, s.protocol, s.port, s.sourcename, s.status, s.url, s.checkid, "
		. "s.enabled, s.archive_mailbox, s.delete_mail, s.category AS categoryid, " 
		. "c.name AS category, s.language, s.clustering_enabled, s.contains_advisory, s.create_advisory, "
		. "s.advisory_handler, s.take_screenshot, s.collector_id, s.use_starttls, s.use_keyword_matching, "
		. "s.additional_config, s.mtbc_random_delay_max";

	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources s', $select, \%where, 's.sourcename' );

	my %join = ( 'JOIN category c' => { 'c.id' => 's.category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	$stmnt .= ( defined( $offset ) && defined( $limit ) ) ? ' OFFSET ' . $offset  : '';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	my @sources;
	
	while ( $self->nextObject() ) {
		push @sources, $self->getObject();
	}

	return \@sources;
}

sub getSourcesCount {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	my $select = "COUNT(*) AS sources_count";
	$where{deleted} = 0;
	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources s', $select, \%where );

	my %join = ( 'JOIN category c' => { 'c.id' => 's.category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	my $countRecord = $self->{dbh}->fetchRow();

	return $countRecord->{sources_count};
}

#TODO: merge sub getSource(), getSourceByName() and getSources()
sub getSource {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};
	my %where = ( 's.id' => $id );
	
	my $select = "s.id, s.digest, s.fullurl, s.host, s.mailbox, s.mtbc, s.parser, s.username, "
		. "s.password, s.protocol, s.port, s.sourcename, s.status, s.url, s.checkid, "
		. "s.enabled, s.archive_mailbox, s.delete_mail, s.category AS categoryId, " 
		. "c.name AS category, s.language, s.clustering_enabled, s.contains_advisory, s.advisory_handler, "
		. "s.create_advisory, s.take_screenshot, s.collector_id, s.use_starttls, s.use_keyword_matching, "
		. "s.additional_config, s.rating, s.mtbc_random_delay_max";

	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources s', $select, \%where, 'sourcename' );
	
	my %join = ( 'JOIN category c' => { 'c.id' => 's.category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	my $hash_ref = $self->{dbh}->{sth}->fetchall_hashref( 'id' );
	my $source;
	while ( my ( $uKey, $uVal ) = ( each %$hash_ref ) ) {
		while ( my ( $key, $val ) = ( each %$uVal ) ) {
			if ( defined $val ) {
				$source->{$key} = $val ;
			} else {
				$source->{$key} = ''; #  emulate XMLGeneric behaviour
			}
		}
	}

	if ( $source->{additional_config} ) {
		my $additionalConfig = eval{ from_json($source->{additional_config}) };
		if ( $additionalConfig ) {
			while ( my ( $key, $val ) = ( each %$additionalConfig ) ) {
				next if ( exists( $source->{$key} ) );
				$source->{$key} = $val;
			}
		}
	}

	return $source;
}

sub getSourceByName {
	my ( $self, $sourceName ) = @_;
	undef $self->{errmsg};
	my %where = ( sourcename => $sourceName );

	if ( !defined( $where{sourcename} ) ) {
		$self->{errmsg} = "Missing mandatory parameter!";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources', "*", \%where, 'sourcename' );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	my $hash_ref = $self->{dbh}->{sth}->fetchall_hashref('id');
	my $source;
	while ( my ( $uKey, $uVal ) = ( each %$hash_ref ) ) {
		while ( my ( $key, $val ) = ( each %$uVal ) ) {
			if (defined $val) {
				$source->{$key} = $val ;
			} else {
				$source->{$key} = ''; #  emulate XMLGeneric behaviour
			}
		}
	}

	return $source;
}

sub getDistinctSources {
	my $self = shift;
	my @sources;
		
	my $stmnt = "SELECT DISTINCT sourcename FROM sources WHERE deleted = FALSE ORDER BY sourcename ASC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		push ( @sources, $self->getObject()->{sourcename} );
	}
	return \@sources;
}

#TODO: source is also referenced in table source_wordlist
sub deleteSource {
	my ( $self, $id ) = @_;
	undef $self->{errmsg};

	if ( !$id && $id !~ /^\d+$/ ) {
		$self->{errmsg} = "Invalid parameter!";
		return 0;
	}

	my ( $stmnt, @bind );

	if ( $self->{dbh}->checkIfExists( { source_id => $id }, "item" ) ) {
		( $stmnt, @bind ) = $self->{dbh}->{sql}->update( 'sources', { deleted => 1 }, { id => $id } );
	} else {
		( $stmnt, @bind ) = $self->{dbh}->{sql}->delete( 'sources', { id => $id } );
	}
 
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

sub setSource {
	my ( $self, %update ) = @_;
	undef $self->{errmsg};

	if ( !defined( $update{id} ) ) {
		$self->{errmsg} = "Missing mandatory parameter!";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( 'sources', \%update, { id => delete $update{id} } );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return 1;
}

sub createSourceIcon {
	my ( $self, $sourceName ) = @_;
	my ( $fontSize, $x_offset, $y_offset );
 
	# determine fontsize for icon image
	for ( length($sourceName) ) {
		if (/^(2)$/) {
			$fontSize = 21;
			$x_offset = 20;
			$y_offset = 25;
		} elsif (/^3$/) {
			$fontSize = 21;
			$x_offset = 12;
			$y_offset = 25;
		} elsif (/^4$/) {
			$fontSize = 20;
			$x_offset = 4;
			$y_offset = 25;
		} elsif (/^5$/) {
			$fontSize = 16;
			$x_offset = 4;
			$y_offset = 22;
		} elsif (/^6$/) {
			$fontSize = 13;
			$x_offset = 4;
			$y_offset = 22;
		} else {
			$fontSize = 12;
			$x_offset = 4;
			$y_offset = 22;
		}
	}

	# create source icon image
	my $img = GD::Simple->new(72,30);
	$img->bgcolor('white');
	$img->fgcolor('black');
	$img->rectangle(0,0,71,29);
	$img->fontsize($fontSize);
	$img->font('courier:bold');
	$img->moveTo($x_offset,$y_offset);

	my $sourceNameForIcon = $sourceName;

	if ( length( $sourceNameForIcon ) > 7 ) {
		$sourceNameForIcon = substr( $sourceNameForIcon, 0, 6 ) . "."; 
	}

	$img->string( $sourceNameForIcon );

	return $img->gif;
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}

### source wordlists ###
#TODO: put subs in Taranis::Sources::Wordlist
sub addSourceWordlist {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};
	
	if ( my $sourceWordlistID = $self->{dbh}->addObject( 'source_wordlist', \%inserts, 1 ) ) {
		return $sourceWordlistID;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteSourceWordlist {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
	
	if ( !%where ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	if ( $self->{dbh}->deleteObject( 'source_wordlist', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getSourceWordlist {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'source_wordlist', '*', \%where );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @wordlists;
	while ( $self->{dbh}->nextRecord() ) {
		push @wordlists, $self->{dbh}->getRecord();
	}
	return \@wordlists;
}

sub setSourceWordlist {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'source_wordlist', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

1;

=head1 NAME 

Taranis::Sources

=head1 SYNOPSIS

  use Taranis::Sources;

  my $obj = Taranis::Sources->new( $oTaranisConfig );

  $obj->addSource( %source );

  $obj->addSourceWordlist( source_id => $sourceID, wordlist_id => $wordlistID, and_wordlist_id => $wordlistID );

  $obj->createSourceIcon( $sourceName );

  $obj->deleteSource( $sourceID );

  $obj->deleteSourceWordlist( %where );

  $obj->getDistinctSources();

  $obj->getSource( $sourceID );

  $obj->getSourceByName( $sourceName );

  $obj->getSourceWordlist( %where );

  $obj->getSources( limit => $limit, offset => $offset, %where );

  $obj->getSourcesCount( %where );

  $obj->setSource( id => $sourceID, %source );

  $obj->setSourceWordlist( id => $sourceWordlistID, %sourceWordlist );

=head1 DESCRIPTION

CRUD functionality for sources as well a add wordlists to sources.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Sources> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Sources->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addSource( %source )

Adds a source.

    $obj->addSource( sourcename => 'NCSC', digest => 'YNcXjbBGxNS121YKCU7Kkg', host => 'www.ncsc.nl', mtbc => 60, etc... );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 addSourceWordlist( source_id => $sourceID, wordlist_id => $wordlistID, and_wordlist_id => $wordlistID )

Adds a wordlist to a source.

    $obj->addSourceWordlist( source_id => 35, wordlist_id => 78, and_wordlist_id => 42 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 createSourceIcon( $sourceName )

Creates an image which can be used as source icon. The icon image is 72 x 30 pixels in size with a 1px black border an white background.
The C<$sourceName> will added in the center of the image in black.

    $obj->createSourceIcon( 'NCSC' );

Returns the image.

=head2 deleteSource( $sourceID )

Deletes a source. 

    $obj->deleteSource( 89 );

Note: if the source is reference in other table, then the source will not be deleted, the deleted flag will be set.
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteSourceWordlist( %where )

Removes a wordlist(s) from source.

    $obj->deleteSourceWordlist( source_id => 987 );

OR

    $obj->deleteSourceWordlist( wordlist_id => 23 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getDistinctSources()

Retrieves a list of sourcenames which have C<deleted> set FALSE.

    $obj->getDistinctSources();

Returns an ARRAY reference.

=head2 getSource( $sourceID )

Retrieves source details of one source by source ID. Also included in the details is the categoryname as key C<category>.

    $obj->getSource( 789 );

Returns an HASH reference.

=head2 getSourceByName( $sourceName )

Retrieves source details of one source by source name.

    $obj->getSourceByName( 'NCSC' );

Returns an HASH reference.

=head2 getSourceWordlist( %where )

Retrieves the wordlist settings for sources.

    $obj->getSourceWordlist( source_id => 89 );

Returns an ARRAY reference.

=head2 getSources( limit => $limit, offset => $offset, %where )

Retrieves the sources selected by C<%where>. In any case C<deleted> is set to FALSE.
Parameters C<offset> and C<limit> are typically used for pagination.

    $obj->getSources( enabled => 1, collector_id => 70 );

OR

    $obj->getSources( category => [ 34, 76 ], limit => 100, offeset => 200 );

OR

    $obj->getSources();

Returns an ARRAY reference.

=head2 getSourcesCount( %where )

Counts the number sources selected by C<%where>. In any case C<deleted> is set to FALSE.

    $obj->getSources( enabled => 1, collector_id => 70 );

OR

    $obj->getSources( category => [ 34, 76 ], limit => 100, offeset => 200 );

OR

    $obj->getSources();

Returns a number.

=head2 setSource( id => $sourceID, %source )

Updates source details. Parameter C<id> is mandatory.

    $obj->setSource( id => 78, sourcename => 'NCSC-NL', mtbc => 30 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setSourceWordlist( id => $sourceWordlistID, %sourceWordlist )

Updates source wordlist details. Parameter C<id> is mandatory.

    $obj->setSourceWordlist( id => 78, wordlist_id => 98, source_id => 22, and_wordlist_id => 30 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by getSourceByName(), setSource(), deleteSourceWordlist() and setSourceWordlist() mandatory parameter is undefined.
You should check input parameters.

=item *

I<Invalid parameter!>

Caused by deleteSource() when parameter C<$id> is not a number.
You should check parameter C<$id>.

=item *

I<Delete failed, corresponding id not found in database.>

Caused by deleteSource() when there is no source that has the specified source id. 
You should check parameter C<$id>.

=back

=cut
