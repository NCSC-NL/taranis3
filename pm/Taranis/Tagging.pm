# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Tagging;

use Taranis qw(:util);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use strict;
use Tie::IxHash;
use URI::Escape;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg 	=> undef,
		dbh => Database,
		sql => Sql,
	};
	
	return( bless( $self, $class ) );
}

sub getTags {
	my ( $self, $tag ) = @_;
	undef $self->{errmsg};
	my @tags;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "tag", "name", { name => { -ilike => trim($tag) . "%" } } );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	while ( $self->nextObject() ) {
		push @tags, $self->getObject()->{name};
	}
	
	return \@tags;
}

sub getTagsByItem {
	my ( $self, $item_id, $table ) = @_;
	my @tags;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "tag AS t", "t.name", { "ti.item_id" => $item_id, "ti.item_table_name" => $table }, "t.name" );
	my %join = ( "JOIN tag_item AS ti" => { "ti.tag_id" => "t.id" } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		push @tags, $self->getObject()->{name};
	}	
	
	return \@tags;	
}

sub getTagsByItemBulk {
	my ( $self, %where ) = @_;
	my %tags;
	
	if ( !exists( $where{item_table_name} ) || !exists( $where{item_id} ) ) {
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( "tag AS t", "t.name, ti.item_id", \%where, "t.name" );

	my %join = ( "JOIN tag_item AS ti" => { "ti.tag_id" => "t.id" } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		my $itemID = uri_escape( $record->{item_id}, '+/' );
		if ( exists( $tags{ $itemID } ) ) {
			push @{ $tags{ $itemID } }, $record->{name};
		} else {
			$tags{ $itemID } = [ $record->{name} ];
		}
	}	
	
	return \%tags;
}

sub getTagsForIds($$) {
	my ($self, $table, $ids) = @_;
	@$ids or return {};

	scalar $self->{dbh}{simple}->query(<<__GET_TAGS, @$ids)->group;
 SELECT ti.item_id, tag.name
   FROM tag_item AS ti
        JOIN tag       ON  ti.tag_id = tag.id
  WHERE ti.item_id IN (??)
    AND ti.item_table_name = '$table'
__GET_TAGS
}

# Newer version of getTagsByItemBulk()
#XXX digests are not uri_escaped
sub getTagsForAssessDigests($) {
	my ($self, $digests) = @_;
	$self->getTagsForIds(item => $digests);
}

sub getTagId {
	my ($self, $tag ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "tag", "id", { name => { -ilike => trim($tag) } } );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $id = $self->{dbh}->fetchRow();
	return $id->{id};
}

sub setItemTag {
	my ( $self, $tag_id, $table, $item_id ) = @_;
	undef $self->{errmsg};
	
	if ( !$tag_id || !$table || !$item_id ) {
		$self->{errmsg} = "Missing mandatory parameter!";
		return 0;
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "tag_item", { 
		item_id => $item_id, 
		item_table_name => $table, 
		tag_id => $tag_id 
		});
	
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}	
}

sub removeItemTag {
	my ( $self, $item_id, $table, @tags ) = @_;
	undef $self->{errmsg};
	
	my ( $delete_stmnt, @delete_bind ) = $self->{sql}->delete( "tag_item", { item_id => $item_id, item_table_name => $table } );

	if ( exists( $tags[0] ) && scalar @{ $tags[0] } ) {
		my @where = ( name => { -ilike => \@tags } );
		my ( $stmnt, @bind ) = $self->{sql}->select( "tag", "id", \@where );

		$delete_stmnt .= " AND tag_id NOT IN ( " . $stmnt . " )"; 

		push @delete_bind, @bind;
	}
	
	$self->{dbh}->prepare( $delete_stmnt );
	$self->{dbh}->executeWithBinds( @delete_bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};	
		return 0;
	} else {
		return 1;
	}
}

sub loadCollection {
	my ( $self, %search_fields ) = @_;
	undef $self->{errmsg};
	
	my %where = $self->{dbh}->createWhereFromArgs( %search_fields );	

	my ( $stmnt, @bind ) = $self->{sql}->select( "tag AS t", "t.*", \%where, "t.name" );
	
	my $join = { "JOIN tag_item ti " => {"ti.tag_id" => "t.id"} };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	return $result;
}

sub addTag {
	my ( $self, $tag ) = @_;
	undef $self->{errmsg};
	
	if ( !$tag || length( $tag ) > 100 ) {
		$self->{errmsg} = "Invalid tag. Possibly tag is too long.";
		return 0;
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "tag", { name => $tag } );
	
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub cleanUp {
	my $self = shift;
	
	my $stmnt =	"DELETE FROM tag WHERE id NOT IN ( SELECT tag_id FROM tag_item );";
	
	$self->{dbh}->do( $stmnt );
	
	return 1;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;
}

sub getDossierLabelsPerTag {
	my ( $self ) = @_;
	my %labelsPerTag;
	
	my $stmnt = 
"SELECT d.description, t.name
FROM dossier AS d
JOIN tag_item AS ti ON ti.item_id = d.id::varchar(50)
JOIN tag AS t ON t.id = ti.tag_id
WHERE ti.item_table_name = 'dossier'";

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	while ( $self->{dbh}->nextRecord() ) {
		my $record = $self->{dbh}->getRecord();
		$labelsPerTag{ $record->{name} } = $record->{description};
	}
	
	return \%labelsPerTag;
}

1;

=head1 NAME

Taranis::Tagging

=head1 SYNOPSIS

  use Taranis::Tagging;

  my $obj = Taranis::Tagging->new( $oTaranisConfig );

  $obj->addTag( $tag );

  $obj->cleanUp();

  $obj->getDossierLabelsPerTag();

  $obj->getTagId( $tag );

  $obj->getTagsByItem( $itemID, $table );

  $obj->getTagsByItemBulk( item_id => \@itemIDs, item_table_name => $table, %where );

  $obj->loadCollection( %where );

  $obj->removeItemTag( $itemID, $table, @tags );

  $obj->setItemTag( $tagID, $table, $itemID );

=head1 DESCRIPTION

Module for handling tagging functionality in GUI.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Tagging> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Tagging->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addTag( $tag )

Adds a tag. Length of tag may be a maximum of 100 characters long.

    $obj->addTag( 'NCSC' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 cleanUp()

Deletes tags from table C<tag> that are not present in table C<tag_item>. In other words, deletes tags which are not in use anymore.

    $obj->cleanUp(); 

Always returns TRUE.

=head2 getDossierLabelsPerTag()

Retrieves the dossier descritions per tag.

    $obj->getDossierLabelsPerTag();

Returns an HASH reference with the keys being the tags and the values being the dossier description.

=head2 getTagId( $tag )

Retrieves the ID of C<$tag>.

    $obj->getTagId( 'NCSC' );

Returns a number.

=head2 getTagsByItem( $itemID, $table )

Retrieves tags which are linked to an item with ID C<$itemID> in table C<$table>.

    $obj->getTagsByItem( 20140001, 'analysis' );

Returns an ARRAY reference.

=head2 getTagsByItemBulk( item_id => \@itemIDs, item_table_name => $table, %where )

Same as getTagsByItem(), but can retrieve it for more than one item.

    $obj->getTagsByItemBulk( item_id => [ 20140001, 20140002, 20140003 ] , item_table_name => 'analysis' );

Returns a HASH reference with the keys being the item ID and the values being a list of tags.

=head2 loadCollection( %where )

Executes a SELECT statement on table C<tag> which is joined with C<tag_item>.

    $obj->loadCollection( item_table_name => 'dossier', item_id => [ 23, 45, 89 ] );

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 removeItemTag( $itemID, $table, @tags )

Removes references to tags. Parameters C<$itemID> and C<$table> are mandatory.

    $obj->removeItemTag( 20140001, 'analysis' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setItemTag( $tagID, $table, $itemID )

Links a tag to an item. All parameters are mandatory.

    $obj->setItemTag( 78, 'analysis', 20140001 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setItemTag() when one of the required parameters is undefined.
You should check input parameters.

=item *

I<Invalid tag. Possibly tag is too long.>

Caused by addTag() when the given tag is longer than 100 characters.
You should check the given tag length.

=back

=cut
