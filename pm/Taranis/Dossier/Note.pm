# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dossier::Note;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Tie::IxHash;
use SQL::Abstract::More;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		config => $config,
	};

	return( bless( $self, $class ) );
}

sub getItemNotes {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note AS dn', 'dn.*', \%where, 'created' );
	
	if ( exists( $where{dossier_id} ) ) {
		my %join = ( "JOIN dossier_item AS di" => { "di.id" => "dn.dossier_item_id" } );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	}
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @itemNotes;
	while ( $self->{dbh}->nextRecord() ) {
		push @itemNotes, $self->{dbh}->getRecord();
	}
	return \@itemNotes;
}

sub getItemNotesCountPerDossier {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note AS dn', 'COUNT(dn.*) AS notes_count, d.id, d.description', \%where );
	
	tie my %join, "Tie::IxHash";
	
	%join = (
		"JOIN dossier_item AS di" => { "di.id" => "dn.dossier_item_id" },
		"JOIN dossier AS d" => { "d.id" => "di.dossier_id" },
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	$stmnt .= ' GROUP BY d.id, d.description';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @notesCount;
	while ( $self->{dbh}->nextRecord() ) {
		push @notesCount, $self->{dbh}->getRecord();
	}
	return \@notesCount;
}

sub addNote {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'dossier_note', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setNote {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'dossier_note', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getNoteTickets {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note_ticket', '*', \%where, 'created DESC' ); 
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @noteTickets;
	while ( $self->{dbh}->nextRecord() ) {
		push @noteTickets, $self->{dbh}->getRecord();
	}
	return \@noteTickets;
}

sub addNoteTicket {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( !$inserts{note_id} || $inserts{note_id} !~ /^\d+$/ ) {
		$self->{errmsg} = 'Invalid parameter! (ticket)';
		return 0;
	}
	
	if ( my $id = $self->{dbh}->addObject( 'dossier_note_ticket', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setNoteTicket {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'dossier_note_ticket', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getNoteUrls {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note_url', '*', \%where, 'created DESC' ); 
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @noteUrls;
	while ( $self->{dbh}->nextRecord() ) {
		push @noteUrls, $self->{dbh}->getRecord();
	}
	return \@noteUrls;
}

sub addNoteUrl {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( !$inserts{note_id} || $inserts{note_id} !~ /^\d+$/ ) {
		$self->{errmsg} = 'Invalid parameter! (url)';
		return 0;
	}
	
	if ( my $id = $self->{dbh}->addObject( 'dossier_note_url', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setNoteUrl {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'dossier_note_url', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getNoteFiles {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_note_file', '*', \%where, 'created DESC' ); 
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @noteFiles;
	while ( $self->{dbh}->nextRecord() ) {
		push @noteFiles, $self->{dbh}->getRecord();
	}
	return \@noteFiles;
}

sub addNoteFile {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  

	if ( !$inserts{note_id} || $inserts{note_id} !~ /^\d+$/ || !$inserts{binary} || !$inserts{name} ) {
		$self->{errmsg} = 'Invalid parameter! (file)';
		return 0;
	}
	
	my $binary = delete( $inserts{binary} );
	
	if ( my $blobDetails = $self->{dbh}->addFileAsBlob( binary => $binary ) ) {
		$inserts{size} = $blobDetails->{fileSize};
		$inserts{object_id} = $blobDetails->{oid};
		
		if ( my $id = $self->{dbh}->addObject( 'dossier_note_file', \%inserts, 1 ) ) {
			return $id;
		} else {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{errmsg};
		return 0;
	}
}

sub copyNoteFile {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  

	if ( !$inserts{note_id} || $inserts{note_id} !~ /^\d+$/ || !$inserts{name} ) {
		$self->{errmsg} = 'Invalid parameter! (file)';
		return 0;
	}
	
	if ( my $id = $self->{dbh}->addObject( 'dossier_note_file', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub processNoteText {
	my ( $self, $noteText ) = @_;
	
	my ( $stmntGroups, @bindsGroups ) = $self->{sql}->select( 'constituent_group', 'id', { name => { '-ilike' => 'dummy' } } );
	my ( $stmntIndividuals, @bindsIndividuals ) = $self->{sql}->select( 'constituent_individual', 'id', { "firstname || ' ' || lastname" => { '-ilike' => 'dummy' } } );
	
	my %foundConstituents = ( group => [], individual => [] );
	my %uniqueConstituents;

	for ( $noteText =~ /\[\[(.*?)\]\]/g ) {
		
		my $extractedName = $_; 
		
		if ( !exists( $uniqueConstituents{ lc($extractedName) } ) ) {
			$uniqueConstituents{ lc($extractedName) } = 1;
		
			my @binds = $_;
			
			$self->{dbh}->prepare( $stmntGroups );
			$self->{dbh}->executeWithBinds( @binds );
			my $foundGroup = $self->{dbh}->fetchRow();
			
			if ( $foundGroup ) {
				push @{ $foundConstituents{group} }, { id => $foundGroup->{id}, name => $extractedName };
				
			} else {
				$self->{dbh}->prepare( $stmntIndividuals );
				$self->{dbh}->executeWithBinds( @binds );
				my $foundIndividual = $self->{dbh}->fetchRow();
				
				if ( $foundIndividual ) {
					push @{ $foundConstituents{individual} }, { id => $foundIndividual->{id}, name => $extractedName };
				} else {
					$noteText =~ s/\[\[$extractedName\]\]/$extractedName/g;
				}
			}
		}
	}

	foreach my $type ( keys %foundConstituents ) {
		foreach my $constituent ( @{ $foundConstituents{$type} } ) {
			my $linkHTML = '<span class="span-link dossier-constituent-' . $type . '-link" data-' . $type . 'id="' . $constituent->{id} . '">' . $constituent->{name} . '</span>';
			$noteText =~ s/\[\[$constituent->{name}\]\]/$linkHTML/gi;
		}
	}

	return $noteText;
}

1;

=head1 NAME

Taranis::Dossier::Note

=head1 SYNOPSIS

  use Taranis::Dossier::Note;

  my $obj = Taranis::Dossier::Note->new( $oTaranisConfig );

  $obj->getItemNotes( %where );

  $obj->getItemNotesCountPerDossier( %where );

  $obj->addNote( %note );

  $obj->setNote( %note );
  
  $obj->getNoteTickets( %where );
  
  $obj->addNoteTicket( %noteTicket );
  
  $obj->setNoteTicket( %noteTicket );
  
  $obj->getNoteUrls( %where );
  
  $obj->addNoteUrl( %noteUrl );
  
  $obj->setNoteUrl( %noteUrl );
  
  $obj->getNoteFiles( %where );
  
  $obj->addNoteFile( %noteFile );
  
  $obj->copyNoteFile( %noteFile );
  
  $obj->processNoteText( $noteText );

=head1 DESCRIPTION

CRUD functionality for dossier contributor.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dossier::Note> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dossier::Note->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 getItemNotes( %where )

Retrieves dossier item notes and dossier notes.

    $obj->getItemNotes( dossier_item_id => 3 );

or

    $obj->getItemNotes( id => 45 );

Returns an ARRAY reference.

=head2 getItemNotesCountPerDossier( %where )

Counts the item notes per dossier.

    $obj->getItemNotesCountPerDossier( 'di.advisory_id' => 34, 'di.dossier_id' => 3 );

Returns an ARRAY reference where each list entry is an HASH with keys C<notes_count>, C<id> (=dossier id) and C<description> (=dossier description).

=head2 addNote( %note )

Adds a dossier note or dossier item note.

    $obj->addNote( dossier_item_id => 76, text => 'my note text', created_by => 'someuser' );

If successful returns the note ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setNote( %note )

Updates a dossier note or dossier item note. Parameter C<id> is mandatory.

    $obj->setNote( id => 3, text => 'updated note text' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getNoteTickets( %where )

Retrieves note tickets.

    $obj->getNoteTickets( note_id => 23 );

Returns an ARRAY reference.

=head2 addNoteTicket( %noteTicket )

Adds a note ticket. Parameter C<note_id> is mandatory.

    $obj->addNoteTicket( note_id => 33, reference => 78682 );

If successful returns the note ticket ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setNoteTicket( %noteTicket )

Updates a dossier note ticket. Parameter C<id> is mandatory.

    $obj->setNoteTicket( id => 3, reference => 89230 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getNoteUrls( %where )

Retrieves note URLs.

    $obj->getNoteUrls( note_id => 23 );

Returns an ARRAY reference.

=head2 addNoteUrl( %noteUrl )

Adds a note URL. Parameter C<note_id> is mandatory.

    $obj->addNoteUrl( note_id => 33, url => 'http://www.ncsc.nl', description => 'NCSC site' );

If successful returns the note URL ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setNoteUrl( %noteUrl )

Updates a dossier note ticket. Parameter C<id> is mandatory.

    $obj->setNoteTicket( id => 3, reference => 89230 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getNoteFiles( %where )

Retrieves note files.

    $obj->getNoteFiles( note_id => 23 );

Returns an ARRAY reference.

=head2 addNoteFile( %noteFile )

Adds a note file. Parameters C<note_id>, C<binary> and C<name> are mandatory.

    $obj->addNoteFile( note_id => 33, binary=> $binary, name => 'myFile.pdf' );

If successful returns the note file ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 copyNoteFile( %noteFile )

Adds a note file, by adding only the note file settings. It does not add the binary to database, only the object ID. Parameters C<note_id> and C<name> are mandatory. 

    $obj->copyNoteFile( note_id => 2, name => 'somefile.pdf', object_id => 873, size => 723478, mime => 'application/pdf' );

If successful returns the note file ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 processNoteText( $noteText )

Conferts special notation ([[]] two square brackets), for marking constituent names, to links.

    $obj->processNoteText( 'this is constituent [[John Doe]] from [[Company X]]' );

Returns the conferted text.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing parameter!>

Caused by setNote(), setNoteTicket() or setNoteUrl().
You should check the mandatory parameters of concerned subroutine.

=item *

I<Invalid parameter! (...)>

Caused by addNoteTicket(), addNoteUrl(), addNoteFile or copyNoteFile().
You should check the parameters of concerned subroutine.

=back

=cut
