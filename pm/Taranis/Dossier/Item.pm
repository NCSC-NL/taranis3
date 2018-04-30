# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dossier::Item;

use strict;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Tie::IxHash;
use SQL::Abstract::More;

my %CONTENTTYPES = ( 
	assess => { table => 'item', orderBy => 'created', joinColumn => 'digest', joinColumnIsInt => 0, is_publication => 0, dossier_item_column => 'assess_id' },
	analyze => { table => 'analysis', orderBy => 'orgdatetime', joinColumn => 'id', joinColumnIsInt => 0, is_publication => 0, dossier_item_column => 'analysis_id' },
	advisory => { table => 'publication_advisory', orderBy => 'created_on', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 1, dossier_item_column => 'advisory_id' },
	forward => { table => 'publication_advisory_forward', orderBy => 'created_on', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 1, dossier_item_column => 'advisory_forward_id' },
	eos => { table => 'publication_endofshift', orderBy => 'created_on', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 1, dossier_item_column => 'eos_id' },
	eod => { table => 'publication_endofday', orderBy => 'created_on', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 1, dossier_item_column => 'eod_id' },
	eow => { table => 'publication_endofweek', orderBy => 'created_on', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 1, dossier_item_column => 'eow_id' },
	note => { table => 'dossier_note', orderBy => 'created', joinColumn => 'id', joinColumnIsInt => 1, is_publication => 0, dossier_item_column => 'note_id' }
);

my %TLPMAPPING = (
#	1 => 'red',
	2 => 'amber',
	3 => 'green',
	4 => 'white'
);

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

sub getPendingItems {
	my ( $self, %args ) = @_;
	my %pendingItems;
	my @tagIDs = @{ $args{tagIDs} };
	
	tie my %join, "Tie::IxHash";

	foreach my $contentType ( keys %CONTENTTYPES ) {
		my $type = $CONTENTTYPES{$contentType};

		my $select = "$type->{table}.*, t.name, t.id AS tag_id";
		$select .= ", p.created_on, p.status AS publication_status" if ( $type->{is_publication} );
		my %where = (
			'ti.tag_id' => \@tagIDs,
			'ti.item_table_name' => $type->{table},
			'ti.dossier_id' => undef
		);
		
		my ( $stmnt, @binds ) = $self->{sql}->select( $type->{table}, $select, \%where, $type->{orderBy} . ' DESC' );
		my $joinColumn = ( $type->{joinColumnIsInt} ) ? "$type->{table}.$type->{joinColumn}::varchar(50)" : "$type->{table}.$type->{joinColumn}";
		
		%join = (
			"JOIN tag_item AS ti" => { "ti.item_id" => $joinColumn },
			"JOIN tag AS t" => { "t.id" => "ti.tag_id" },
		);

		$join{"LEFT JOIN publication AS p"} = { "p.id" => "$type->{table}.publication_id" } if ( $type->{is_publication} );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @binds );
		while ( $self->{dbh}->nextRecord() ) {
			push @{ $pendingItems{$contentType} }, $self->{dbh}->getRecord();
		}
	}

	return \%pendingItems;
}

sub getPendingItemsOfContentType {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};
	
	if ( !exists( $where{contentType} ) || !exists( $CONTENTTYPES{ $where{contentType} } ) ) {
		$self->{errmsg} = 'Missing parameter.';
		return 0;
	}

	my $type = $CONTENTTYPES{ delete( $where{contentType} ) };

	my $select = "$type->{table}.*";
	if ( $type->{is_publication} ) {
		$select .= ", p.created_on, p.status AS publication_status, p.created_on AS item_timestamp";
	} else {
		$select .= ", $type->{table}.$type->{orderBy} AS item_timestamp";
	}
	
	$where{'ti.item_table_name'} = $type->{table};
	my ( $stmnt, @binds ) = $self->{sql}->select( $type->{table}, $select, \%where, $type->{orderBy} );
	
	my $joinColumn = ( $type->{joinColumnIsInt} ) ? "$type->{table}.$type->{joinColumn}::varchar(50)" : "$type->{table}.$type->{joinColumn}";
	
	tie my %join2, "Tie::IxHash";
	%join2 = ( 
		"JOIN tag_item AS ti" => { "ti.item_id" => $joinColumn },
		"JOIN tag AS t" => { "t.id" => "ti.tag_id" }
	);
	$join2{"JOIN publication AS p"} = { "p.id" => "$type->{table}.publication_id" } if ( $type->{is_publication} );
	$stmnt = $self->{dbh}->sqlJoin( \%join2, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @pendingItems;
	while ( $self->{dbh}->nextRecord() ) {
		push @pendingItems, $self->{dbh}->getRecord();
	}
	
	return \@pendingItems;
}

sub getDossierItems {
	my ( $self, %where ) = @_;

	my ( $stmnt, @binds ) = $self->{sql}->select( 'dossier_item', "*, to_char(event_timestamp, 'DD-MM-YYYY HH24:MI') AS event_timestamp_str", \%where, 'event_timestamp' );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my @items;
	while ( $self->{dbh}->nextRecord() ) {
		push @items, $self->{dbh}->getRecord();
	}
	return \@items;
}

sub getDossierItemContent {
	my ( $self, %args ) = @_;
	
	if ( !exists( $args{contentType} ) || !exists( $CONTENTTYPES{ $args{contentType} } ) || !$args{dossierItem} ) {
		$self->{errmsg} = 'Missing parameter.';
		return 0;
	}

	my $contentType = $CONTENTTYPES{ delete( $args{contentType} ) };
	my $dossierItem = $args{dossierItem};
	my %where = ( $contentType->{table} . '.' . $contentType->{joinColumn} => $dossierItem->{ $contentType->{dossier_item_column} } );

	my $select = "$contentType->{table}.*";
	$select .= ", p.created_on, p.status AS publication_status, p.created_on AS item_timestamp, p.contents" if ( $contentType->{is_publication} );
	
	my ( $stmnt, @binds ) = $self->{sql}->select( $contentType->{table}, $select, \%where );
	
	if ( $contentType->{is_publication} ) {
		my %join = ( "JOIN publication AS p" => { "p.id" => "$contentType->{table}.publication_id" } );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	}

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	
	my $itemContent = $self->{dbh}->fetchRow();
	
	return $itemContent;
}

sub setDossierItem {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'dossier_item', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setDossierItemTag {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( 
		!exists( $settings{tagID} ) 
		|| !exists( $settings{itemID} )
		|| !exists( $settings{contentType} )
		|| !exists( $CONTENTTYPES{ $settings{contentType} } )
	) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my %where = (
		tag_id => delete( $settings{tagID} ),
		item_id => delete( $settings{itemID} ),
		item_table_name => $CONTENTTYPES{ delete( $settings{contentType} ) }->{table}
	);
	
	if ( $self->{dbh}->setObject( 'tag_item', \%where, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getDossierItemsFromDossier {
	my ( $self, $dossierID ) = @_;
	
	tie my %dossierItems, "Tie::IxHash";

	foreach my $contentType ( keys %CONTENTTYPES ) {
		tie my %join, "Tie::IxHash";
		my $type = $CONTENTTYPES{$contentType};
		
		my $select = "$type->{table}.*, EXTRACT( EPOCH FROM date_trunc('milliseconds', di.event_timestamp) ) AS created_epoch, "
			. "di.event_timestamp, di.classification, di.id AS dossier_item_id, di.$type->{dossier_item_column} AS product_id";
		$select .= ", p.created_on, p.published_on, p.status AS publication_status, p.contents" if ( $type->{is_publication} );
		
		my ( $stmnt, @binds ) = $self->{sql}->select( $type->{table}, $select, { 'di.dossier_id' => $dossierID } );

		my $joinColumn = ( $type->{joinColumnIsInt} ) ? "$type->{table}.$type->{joinColumn}::varchar(50)" : "$type->{table}.$type->{joinColumn}";
		
		%join = (
			"JOIN dossier_item AS di" => { "di.$type->{dossier_item_column}::varchar(50)" => $joinColumn },
		);
		
		$join{"JOIN publication AS p"} = { "p.id" => "$type->{table}.publication_id" } if ( $type->{is_publication} );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @binds );
		while ( $self->{dbh}->nextRecord() ) {
			my $item = $self->{dbh}->getRecord();
			$item->{dossier_item_type} = $contentType;
			my $epochTimestamp = $item->{created_epoch};
			while ( exists( $dossierItems{ $epochTimestamp } ) ) {
				$epochTimestamp += 1;
			} 
			$dossierItems{ $epochTimestamp } = $item;
		}
	}

	return \%dossierItems;
}

sub createDossierItemFromPending {
	my ( $self, %args ) = @_;

	if ( !exists( $CONTENTTYPES{ $args{contentType} } ) ) {
		$self->{errmgs} = 'Missing parameter';
		return 0;
	}
	
	my $contentType = $CONTENTTYPES{ $args{contentType} };
	my %insert = ( 
		event_timestamp => $args{event_timestamp},
		dossier_id => $args{dossier_id},
		classification => $args{classification},
		$contentType->{dossier_item_column} => $args{item_id}
	);
	
	if ( my $dossierItemID = $self->{dbh}->addObject( 'dossier_item', \%insert, 1 ) ) {
		return $dossierItemID;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub discardPendingItem {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	if ( $where{item_table_name} && $where{item_id} && $where{tag_id} ) {
	
		if ( $self->{dbh}->deleteObject( 'tag_item', \%where ) ) {
			return 1;
		} else {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		return 0;
	}
}

sub addDossierItem {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'dossier_item', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getContentTypes { return \%CONTENTTYPES; }
sub getTLPMapping { return \%TLPMAPPING; }

1;

=head1 NAME

Taranis::Dossier::Item

=head1 SYNOPSIS

  use Taranis::Dossier::Item;

  my $obj = Taranis::Dossier::Item->new( $oTaranisConfig );

  $obj->addDossierItem( %dossierItem );

  $obj->setDossierItem( %dossierItem );

  $obj->setDossierItemTag( %dossierItemTag );

  $obj->getPendingItems( tagIDs => [4, 6] );

  $obj->getPendingItemsOfContentType( %where );

  $obj->getDossierItems( %where );

  $obj->getDossierItemContent( %args );

  $obj->getDossierItemsFromDossier( $dossierID );

  $obj->createDossierItemFromPending( %args );

  $obj->discardPendingItem( %where );

  $obj->getContentTypes();

  $obj->getTLPMapping();

  Taranis::Dossier::Item->getContentTypes();

  Taranis::Dossier::Item->getTLPMapping();

=head1 DESCRIPTION

CRUD functionality for dossier contributor.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dossier::Item> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dossier::Item->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Returns the blessed object.

=head2 addDossierItem( %dossierItem )

Adds a dossier item.

    $obj->addDossierItem( note_id => 2, event_timestamp => '20140131 18:00', classification => 2, dossier_id => 2, etc... );

If successful, returns the ID of the newly added dossier item. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setDossierItem( %dossierItem )

Updates a dossier item. Parameter C<id> is mandatory.

    $obj->setDossierItem( id => 3, classification => 2, event_timestamp => '20140131 18:00' );

If successful, returns the TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setDossierItemTag( %dossierItemTag )

Updates the tag setting for the dossier item. Parameters C<contentType>, C<tagID> and C<itemID> are mandatory.

    $obj->setDossierItemTag( contentType => 'assess', tagID => 2, itemID => 34, dossier_id => 7 );

If successful, returns the TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getPendingItems( tagIDs => [4, 6] )

Retrieves pending dossier items sorted by contenttype. Filtering is done by adding a list of tag ID's.

    $obj->getPendingItems( tagIDs => [4, 6] );

Returns an HASH reference with the following structure C<< { $contenttype => [ \%pendingItem1, \%pendingItem2 ], 'advsiory' => [\%pendingItem1, \%pendingItem2], etc... } >>.

=head2 getPendingItemsOfContentType( %where )

Retrieves pending dossier items of a particular contenttype. Parameter C<contentType> is mandatory.

    $obj->getPendingItemsOfContentType( contentType => 'assess', 'ti.item_id' => 3 );

Returns an ARRAY reference with matching pending dossier items.

=head2 getDossierItems( %where )

Retrieves a list of dossier items. Use column names of table C<dossier_item> to filter the results.

    $obj->getDossierItems( classification => 2 );

Returns an ARRAY reference.

=head2 getDossierItemContent( %args )

Retrieves the content of one dossier item. Parameters C<contentType> and C<dossierItem>.

    $obj->getDossierItemContent( contentType => 'assess', dossierItem => \%dossierItem );

Returns an HASH reference or FALSE if one of the mandatory parameters are missing.

=head2 getDossierItemsFromDossier( $dossierID )

Retrieves dossier items from one particular dossier.

    $obj->getDossierItemsFromDossier( 20 );

Returns an HASH reference where the keys are epoch timestamps.

=head2 createDossierItemFromPending( %args )

Transforms a pending dossier item to a permanent dossier item. Parameter C<contentType> is mandatory.

    $obj->createDossierItemFromPending( contentType => 'assess', dossier_id => 4, item_id => 7, classification => 2, event_timestamp => '20140131 18:00');

If successfule returns the dossier item ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 discardPendingItem( %where )

Deletes a pending dossier item by removing the tag from item. Parameters C<item_table_name>, C<item_id>, and C<tag_id> are mandatory.

    $obj->discardPendingItem( item_table_name => 'item', item_id => '00/3G3SeooQTNyLCVOgWaw', tag_id => 3 );

If successful, returns the TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getContentTypes()

Retrieves all contenttype settings.

    $obj->getContentTypes();

or

    Taranis::Dossier::Item->getContentTypes();

Returns an HASH reference.

=head2 getTLPMapping()

Retrieves TLP mapping.

    $obj->getTLPMapping();

or

    Taranis::Dossier::Item->getTLPMapping();

Returns an HASH reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing parameter.>

Caused by getPendingItemsOfContentType(), getDossierItemContent(), setDossierItem(), setDossierItemTag() or createDossierItemFromPending() when a mandatory parameter is missing.
You should check arguments of calling subroutine.

=back

=cut
