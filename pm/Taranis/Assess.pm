# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Assess;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Category;
use strict;
use SQL::Abstract::More;
use Taranis qw(:all);
use Tie::IxHash;

my %STATUSDICTIONARY = ( 
	0 => 'unread',
	1 => 'read',
	2 => 'important',
	3 => 'waitingroom'
);

my %status2code = reverse %STATUSDICTIONARY;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		result_count => undef,
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub loadAssessCollection {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};

	my $limit  = ( $searchFields{limit} ) ? sanitizeInput( "only_numbers", delete ( $searchFields{limit}  ) ) : undef;
	my $offset = ( $searchFields{offset} ) ? sanitizeInput( "only_numbers", delete ( $searchFields{offset} ) ) : undef;
	
	$offset = ( $offset - 1 ) * $limit;
	
############################################ part 1 of sql statement #############################################
	my %nests;

	my %where;
	my $startdate = formatDateTimeString($searchFields{startdate});
	my $enddate   = formatDateTimeString($searchFields{enddate});
	if($startdate && $enddate) {
		$searchFields{startdate} = $startdate;
		$searchFields{enddate}   = $enddate;
		$where{'i1.created'} = {-between => ["$startdate 000000", "$enddate 235959"] };
	} elsif ( $searchFields{startdate} ) {
		$searchFields{startdate} = $startdate;
		$where{'i1.created'} = { '>=' => "$startdate 000000" }
	} elsif ( $searchFields{enddate} ) {
		$searchFields{enddate} = $enddate;
		$where{'i1.created'} = { '<=' => "$enddate 235959" }
	}
	
	if ( @{$searchFields{status} || []} != 4  ) {
		$nests{status} = [ map +('i1.status' => $_), @{$searchFields{status}} ];
	}

	$nests{title_description} = [
		'i1.title' => { ilike => "%".trim($searchFields{search})."%"},
		'i1.description' => { ilike => "%".trim($searchFields{search})."%"}
 	] if ( $searchFields{search} );
	
	if ( exists( $searchFields{category} ) &&  @{ $searchFields{category} } ) {
		
		my $ca = Taranis::Category->new();
		
		my @allCategories = $ca->getCategory( is_enabled => 1  );

		if ( scalar( @allCategories ) != scalar( @{ $searchFields{category} } ) ) {
		my @category;
		foreach (  @{ $searchFields{category} } ) {
			push @category, 'i1.category' => $_;
		}
			$nests{category} = \@category;
		}
	}

	if ( $searchFields{source} && @{ $searchFields{source} } > 0 ) {
		my @sources;
		foreach (  @{ $searchFields{source} } ) {
			push @sources, 'i1.source' => { ilike => $_ };
		}
		$nests{sources} = \@sources;
	}

	foreach my $nest ( values %nests ) {
		push @{ $where{-and} }, -nest => $nest; 
	}

	my $select = "i1.digest, to_char(created, 'DD-MM-YYYY HH24:MI:SS') AS item_date, i1.source, i1.title, i1.link, "
				. "i1.is_mail, i1.description, i1.status, i1.created, c1.name AS category, "
				. "ROUND(i1.cluster_score, 1) AS cluster_score, i1.cluster_id, i1.cluster_enabled, "
				. "EXTRACT( EPOCH FROM date_trunc('seconds', i1.created) ) AS created_epoch, i1.screenshot_object_id, "
				. "i1.screenshot_file_size, i1.matching_keywords_json, i1.id, s1.rating";

	my ( $stmnt_part1, @bind ) = $self->{sql}->select( "item i1", $select, \%where );
	
	my $join1 = { 
		"JOIN category c1" => { "c1.id" => "i1.category" },
		"JOIN sources s1" => { "s1.id" => "i1.source_id" }
	};
	
	$stmnt_part1 = $self->{dbh}->sqlJoin( $join1, $stmnt_part1 );

#################################### end of part 1 of sql statement ##############################################	

########################################### part 2 of sql statement ##############################################	

	delete $where{-and};
	delete $nests{title_description};
	
	foreach my $key ( keys %where ){
		my $newKey = $key;
		$newKey =~ s/i1/i2/i;
		$where{ $newKey } = $where{ $key };
		delete $where{ $key };
	}

	foreach my $nest ( keys %nests ) {
		if ( $nest =~ /^status$/ ) {
			for ( my $i = 0; $i < @{ $nests{ $nest } }; $i++ ) {
				$nests{ $nest }[ $i ] = "i2.status" if ( $nests{ $nest }[ $i ] eq "i1.status");
			} 
		} elsif ( $nest =~ /^category$/ ) {
			for ( my $i = 0; $i < @{ $nests{ $nest } }; $i++ ) {
				$nests{ $nest }[ $i ] = "i2.category" if ( $nests{ $nest }[ $i ] eq "i1.category");
			} 
		} elsif ( $nest =~ /^sources/ ) {
			for ( my $i = 0; $i < @{ $nests{ $nest } }; $i++ ) {
				$nests{ $nest }[ $i ] = "i2.source" if ( $nests{ $nest }[ $i ] eq "i1.source");
			} 
		} 
	}

	foreach my $nest ( values %nests ) {
		push @{ $where{-and} }, -nest => $nest; 
	}

	$where{"identifier.identifier"} = { ilike => "%".trim($searchFields{search})."%"} if ( $searchFields{search} );			

	$select =~ s/i1/i2/g;
	$select =~ s/c1/c2/g;
	$select =~ s/s1/s2/g;
	
	my ( $stmnt_part2, @bind_part2 ) = $self->{sql}->select( "item i2", $select, \%where );
	my $join2 = { 
		"JOIN identifier" => { "identifier.digest" => "i2.digest" },
		"JOIN category c2" => { "c2.id" => "i2.category" },
		"JOIN sources s2" => { "s2.id" => "i2.source_id" }
	};
	$stmnt_part2 = $self->{dbh}->sqlJoin( $join2, $stmnt_part2 );
		
#################################### end of part 2 of sql statement ##############################################
	
	my $orderBy;
	
	if ( exists( $searchFields{sorting} ) && $searchFields{sorting} ) {
		my @sort = split( '_', $searchFields{sorting} );
		
		$orderBy = ( 
			scalar( @sort ) == 2 && 
			$sort[0] =~ /^(created|source|title)$/ && 
			$sort[1] =~ /^(asc|desc)$/ 
		)
		? "ORDER BY " . $sort[0] . " " . uc( $sort[1] )
		: "";
	}	else {
		$orderBy = "ORDER BY created DESC";
	}
	
	my $stmnt = "SELECT * FROM (($stmnt_part1) UNION ($stmnt_part2)) AS item $orderBy";
	$stmnt .= " LIMIT $limit OFFSET $offset;" if ( $limit =~ /^\d+$/ && $offset =~ /^\d+$/ );
	
	push @bind, @bind_part2;

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return $result;
}

sub getDistinctSources {
	my ( $self, @assessCategories ) = @_;
	my @sources;
	
	my @where = ( category => @assessCategories );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'sources', 'DISTINCT( sourcename )', \@where, 'sourcename ASC' );
		
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		push ( @sources, $self->getObject()->{sourcename} );
	}
	return @sources;
}

sub setItemStatus {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	my %where = ( digest => $args{digest}, status => { "!=", 3 } );
	delete $where{status} if ( $args{ignore_waiting_room_status} );
	
	my %fieldvals = ( status => $args{status} );

	my ( $stmnt, @bind ) = $self->{sql}->update( "item", \%fieldvals, \%where );

	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			$self->{errorIsSet} = 1;
			return 0;
		}
	} elsif ( $result =~ /^0E0$/ ) {
		$self->{errmsg} = "No items have been changed. Perhaps you tried to change items with status 'waitingroom'.";
		return 0;				
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		$self->{errorIsSet} = 1;
		return 0;		
	}	
}

sub getItem {
	my ( $self, $id, $searchArchive ) = @_;
	
	my %where = ( $id =~ /^\d+$/ )
		? ( 'i.id' => $id )
		: ( 'i.digest' => $id );
	
	my $table = ( $searchArchive ) ? 'item_archive' : 'item';
	
	my $select = "i.digest, i.source, i.title, i.link, "
		. "i.description, i.status, i.created, i.is_mail, i.is_mailed, "
		. "c.name AS category, to_char(created, 'DD-MM-YYYY HH24:MI:SS') as item_date, "
		. "i.screenshot_object_id, i.screenshot_file_size, i.matching_keywords_json, i.id";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "$table i", $select, \%where );

	my %join = ( 'JOIN category c' => { 'c.id' => 'i.category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	my $item = $self->{dbh}->fetchRow(); 
	
	if ( $item ) {
		$item->{isArchived} = ( $searchArchive ) ? 1 : 0;
	}
	
	return $item; 	
}

sub getMailItem {
	my ( $self, $id ) = @_;
	
	undef $self->{errmsg};
	
	my %where = ( 'email_item.id' => $id );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'email_item', "email_item.*, item.title, category.name AS category", \%where );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		'JOIN item' => { 'item.digest' => 'email_item.digest' },
		'JOIN category' => { 'item.category' => 'category.id' } 
	);
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}

	return $self->{dbh}->fetchRow();
}

sub getRelatedIdDescription {
	my ( $self, $id ) = @_;
	my $table = 'identifier_description';

	#select description from identifier_description where identifier=
	my %where = (identifier => uc( $id ) );
	my ( $stmnt, @bind ) = $self->{sql}->select( $table, "*", \%where,  );
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my $return;

	if ( $self->nextObject() ) {
		$return =  $self->getObject();
	} else {
		$self->{errmsg} = "No description available.";
		return 0;          
	}

	$table = 'publication_advisory pa';
	my $select = 'max(pa.id) AS id, govcertid';
	%where = ( ids => { -ilike => '%'. trim($id) .'%' }, status => 3 );

	( $stmnt, @bind ) = $self->{sql}->select( $table, $select, \%where);

	my %join = ( "JOIN publication p" => { "pa.publication_id" => "p.id" } );

	$stmnt = $self->{dbh}->sqlJoin( \%join , $stmnt );

	$stmnt .= ' GROUP BY govcertid';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @ids;
	while ( $self->nextObject ) {
		push @ids, $self->getObject();
	}
	
	$return->{ids} = \@ids;
	return $return;
}

sub getRelatedIds {
	my ( $self, $digest ) = @_;
	my @ids;
	
	my %where = ( digest => $digest );
	my ( $stmnt, @bind ) = $self->{sql}->select( "identifier", "identifier", \%where, "identifier" );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject ) {
		push @ids, $self->getObject->{identifier};
	}
	return \@ids;
}

sub getRelatedItemsIdMatch {
	my ( $self, $digest ) = @_; 

	my %where = ( digest => $digest );
	
	my ( $sub_select, @bind ) = $self->{sql}->select( "identifier", "identifier", \%where );  
	
	$sub_select = "($sub_select)";

	%where = ( "identifier.digest" => {"!=", $digest }, 
		"identifier.identifier IN" => \$sub_select
	);
	
	my ( $sub_select2, @bind_part2 ) = $self->{sql}->select( "identifier", "distinct(identifier.digest)", \%where );
	my $join = { "JOIN item" => {"identifier.digest" => "item.digest"} };

	$sub_select2 = $self->{dbh}->sqlJoin( $join, $sub_select2 );
	$sub_select2 = "($sub_select2)";	
	
	push @bind, @bind_part2;

	%where = ( "digest IN" => \$sub_select2 ); 

	my ( $stmnt, @bind_part3 ) = $self->{sql}->select( "item", "item.*, to_char(created, 'DD-MM-YYYY HH24:MI:SS') as item_date", \%where,	"created DESC");
	
	push @bind, @bind_part3;

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	my @items;
	while ( $self->nextObject ) {
		my $record = $self->getObject();
		push @items, $self->getObject;
	}
	
	return \@items;
}

sub getCertidsForAssessDigests($$) {
	my ($self, $digests) = @_;
	@$digests or return {};

	scalar $self->{dbh}->simple->query(<<'__GET_CERTIDS', @$digests)->group;
 SELECT DISTINCT digest, UPPER(identifier)
   FROM identifier
  WHERE digest IN (??)
__GET_CERTIDS
}

sub getRelatedItemsKeywordMatch {
	my ( $self, $digest, @keywords ) = @_;

	my %temp;
	my ( @nest, @where );
	
	if ( scalar @keywords > 1 ) {
		for ( my $i = 0; $i < @keywords; $i++ ) {
			for ( my $j = 0; $j < @keywords; $j++ ) {
				if ( $i != $j && ( $j > $i ) ) {
					%temp = ( "-and" => 
						[ 
							title => { -ilike, "%".trim($keywords[$i])."%"  },
							title => {-ilike, "%".trim($keywords[$j])."%" }
						] 
					);
					push @nest, %temp;
				}
			}
		}
	
		@where = (
			-and => [ 
				digest => { '!=', $digest  }, 
				-nest => [ \@nest ]
			]
		);
	} else {
		@where = (
			-and => [ 
				digest => { '!=', $digest  }, 
				title => { -ilike => '%' . trim($keywords[0]) . '%' }
			]
		);
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "item", "item.*, to_char(created, 'DD-MM-YYYY HH24:MI:SS') AS item_date", \@where, "created DESC" );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	my @items;
	while ( $self->nextObject ) {
		push @items, $self->getObject;
	}

	return \@items;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

sub setIsMailedFlag {
	my ( $self, $digest ) = @_;
	
	if ( !$digest ) {
		$self->{errmsg} = 'Item id missing.';
		return 0;
	}
	
	my ( $stmnt, @bind ) = $self->{sql}->update( 'item', { 'is_mailed' => 1 }, { digest => $digest } );
	
	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( defined($result) && ($result !~ m/(0E0)/i) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;		
	}		
}

#TODO: replace other item-update subs with setItem
sub setAssessItem {
	my ( $self, %update ) = @_;

	if ( !exists( $update{digest} ) ) {
		$self->{errmsg} = 'Item id missing.';
		return 0;
	}
	
	my $itemDigest = delete $update{digest};
	
	my ( $stmnt, @bind ) = $self->{sql}->update( 'item', \%update, { digest => $itemDigest } );
	
	$self->{dbh}->prepare( $stmnt );
	
	my $result = $self->{dbh}->executeWithBinds( @bind );

	if ( defined($result) && ($result !~ m/(0E0)/i) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;		
	}	
}

sub getAttachmentInfo {
	my ($self, $entity, $info) = @_;

	# $info grows and is returned as well
	$info ||= {};

	# Scan recursive through multiparts
	if (my @p = $entity->parts) {
		$self->getAttachmentInfo($_, $info) for @p;
		return $info;
	}

	my $head = $entity->head;
	my $disposition = $head->mime_attr( 'content-disposition' ) || 'inline';
	my $fileName = $head->recommended_filename || 'noname';
	my $fileType = $head->mime_type =~ m!.*?/(.*)! ? lc($1) : '';

	$info->{$fileName} = {
		filename    => $fileName,
		filetype    => $fileType,
	} if lc($disposition) eq 'attachment';

	$info;
}

sub getAttachment {
	my ($self, $entity, $name) = @_;
	if(my @p = $entity->parts) {
		foreach my $part (@p) {
			if (my $attachment = $self->getAttachment($part, $name)) {
				return $attachment;
			}
		}
		return;
	}

	my $fileName = $entity->head->recommended_filename || 'noname';
	$fileName eq $name ? $entity->stringify : undef;
}

sub getAddedToPublicationBulk {
	my ( $self, %where ) = @_;
	my @publications;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "item_publication_type", "*", \%where );
  
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
  
	my %publications;
	while ( $self->nextObject ) {
		my $record = $self->getObject();
		if ( exists( $publications{$record->{item_digest} } ) ) {
			push @{ $publications{ $record->{item_digest} } }, $record;
		} else {
			$publications{ $record->{item_digest} } = [ $record ];
		}
	}

	return \%publications; 
}

sub getItemsAddedToPublication {
	my ( $self, $timeframe_start, $timeframe_end, $publication_type, $publication_specifics ) = @_;

	my %where;
	$where{"i.created"} = {-between => [$timeframe_start, $timeframe_end] };
	$where{"ipt.publication_type"} = $publication_type;
	$where{"ipt.publication_specifics"} = $publication_specifics;

	my ( $stmnt, @bind ) = $self->{sql}->select( "item i", "i.title, i.description, i.link", \%where, "i.created" );
	my $join = { "JOIN item_publication_type ipt" => { "ipt.item_digest" => "i.digest" } };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );  

	my @items;
	while ( $self->nextObject ) {
		push @items, $self->getObject();
	}
  
	return \@items;
}

sub addToPublication {
	my ( $self, $digest, $publicationTypeId, $publicationSpecifics ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->insert( "item_publication_type", {
		item_digest => $digest, 
		publication_type => $publicationTypeId,
		publication_specifics => $publicationSpecifics
	});

	$self->{dbh}->prepare( $stmnt );

	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub removeFromPublication {
	my ( $self, $itemDigest, $publicationTypeId, $publicationSpecifics ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->delete( "item_publication_type", {
		item_digest => $itemDigest, 
		publication_type => $publicationTypeId,
		publication_specifics => $publicationSpecifics,
	});

	$self->{dbh}->prepare( $stmnt );

	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
    return 1;
  } else {
    $self->{errmsg} = $self->{dbh}->{db_error_msg};
    return 0;
  }
}

sub getStatusDictionary {
	return \%STATUSDICTIONARY;
}

sub countItemStatus($) {
	my ($self, $status) = @_;
	my $status_code = $status2code{$status} // $status;

	my $db = $self->{dbh}->simple;
	$db->query('SELECT COUNT(*) FROM item WHERE status = ?', $status_code)->list;
}

# When too many items are unread, we may want to purge a bunch.  See
# "taranis db purge-items".
sub readOldestItems($) {
	my ($self, $keep) = @_;
	my $unread = $status2code{unread};

	my $db = $self->{dbh}->simple;
	$db->query(<<'__READ_OLDEST', $status2code{read}, $unread, $unread, $keep);
UPDATE item
   SET status = ?
 WHERE status = ?
   AND item.digest NOT IN
    ( SELECT i.digest
        FROM item AS i
       WHERE i.status = ?
       ORDER BY i.created DESC
       LIMIT ?
    )
__READ_OLDEST

}

1;


=head1 NAME

Taranis::Assess - functionality for Assess

=head1 SYNOPSIS

  use Taranis::Assess;

  my $obj = Taranis::Assess->new( $objTaranisConfig );

  $obj->loadAssessCollection( startdate => $start_date, enddate => $end_date, 
                        search => $search_string, status => \@statuses, 
                        category => \@categories, limit => $limit, offset => $offset,
                        source => \@sources );

  $obj->getDistinctSources( \@assessCategories );

  $obj->setItemStatus( status => $status, digest => $digest );

  $obj->getItem( $id, $searchArchive );

  $obj->getMailItem( $id );

  $obj->getRelatedIdDescription( $id );

  $obj->getRelatedIds( $digest );

  $obj->getRelatedItemsIdMatch( $digest );

  $obj->getRelatedItemsKeywordMatch( $digest, @keywords );

  $obj->nextObject();

  $obj->getObject();  

  $obj->setIsMailedFlag( $digest );

  $obj->setAssessItem( digest => $digest);

  $obj->getAttachmentInfo( $entity, $info );

  $obj->getAttachment( $entity, $name );

  $obj->getAddedToPublicationBulk( item_digest => \@itemDigests );

  $obj->getItemsAddedToPublication( $beginDate, $endDate, $publicationTypeId, 'vuln_threats' );

  $obj->addToPublication( $itemDigest, $publicationTypeId, $publicationSpecifics );

  $obj->removeFromPublication( $itemDigest, $publicationTypeId, $publicationSpecifics );

  $obj->getStatusDictionary();

  Taranis::Assess->getStatusDictionary();

=head1 DESCRIPTION

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Assess> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Assess->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Clears error message for the new object. Can be accessed by;

    $obj->{errmsg};

Clears the counted results that can be accessed by:

    $obj->{result_count};

Returns the blessed object.  

=head2 loadAssessCollection( startdate => $start_date, enddate => $end_date, search => $search_string, ... )

Retrieves all items that are collected by the collector. 

Arguments determine which items are retrieved. Possible arguments are:

=over

=item *

startdate & enddate, searches in column C<created> between supplied startdate and enddate. Both dates come with a time part, for startdate the time is 000000, for enddate the time is 235959.   

=item *

search, string which searches columns C<title> and C<description> from table C<item> and column C<identifier> from table C<identifier>

=item *

status, searches column C<status> for matching status. Value is an ARRAY reference. Possible statuses are: 

=over

=item *

0 (unread)

=item *

1 (read)

=item *

2 (important)

=item *

3 (deleted)

=back

=item *

category, searches column C<category> for matching categories. Value is an ARRAY reference.

=item *

source searches column C<source> for matching sources. Value is an ARRAY reference.

=item *

limit, setting for the maximum items per page

=item *

offset, setting depending on the current page

=item *

sorting, setting to set the ORDER BY of the SQL statement. Possible values are:

=over

=item *

created_desc, translates to 'ORDER BY created DESC'

=item *

created_asc, translates to 'ORDER BY created ASC'

=item *

source_asc, translates to 'ORDER BY source ASC'

=item *

source_desc, translates to 'ORDER BY source DESC'

=item *

title_asc, translates to 'ORDER BY title ASC'

=item *

title_desc, translates to 'ORDER BY title DESC'

=back

=back

Example:

    $obj->loadAssessCollection( startdate => '21-12-2008', enddate => '23-12-2008', 
                          search => 'microsoft update for office 2007', status => \[ 1, 3 ],
                          source => \[ 'source_x', 'source_y' ], category => \[ 2, 4 ] );

The query being build in this method consists of two queries which are combined with a UNION. 
The difference between the two queries can be found in the JOIN of table identifier in one of the queries. 

Returns the return value of DBI->execute(). Use getObject() and nextObject() to get the list of assess items. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if database execution fails.

=head2 getDistinctSources( \@assessCategories )

Retrieves a list of all unique source names depending on the supplied Assess statuses.

Method expects an ARRAY reference as argument containing assess categories.

    $obj->getDistinctSources( \[ 1, 4, 5 ] );

Returns an ARRAY containing only sourcenames in alphabetical order.

=head2 setItemStatus( status => $status, digest => $digest )

Method for changing the status of an item.

Takes two arguments as key value pairs, both are mandatory:

    $obj->setItemStatus( status => 2, digest => 'YCpWzDJgrxy+aWdXzaf2lw' );

Returns TRUE if database update is successful or returns FALSE if update is unsuccessful and sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >>.

=head2 getItem( $id, $searchArchive )

Retrieves one item and returns it.

Takes the item ID or digest as argument. The second argument is optional, which specifies whether to search archived items or non-archived items. 
Setting value to 1 (or 'true') does a search in archived items, value 0 (default), does a search in non-archived items.

    $obj->getItem( 432, 1 );

OR

    $obj->getItem( 'YCpWzDJgrxy+aWdXzaf2lw', 1 );

Returns the item. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if there's a database failure.

=head2 getMailItem( $id )

Retrieves one email item.

Takes the item digest as argument:

    $obj->getMailItem( 'YCpWzDJgrxy+aWdXzaf2lw' );

Returns the item. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if there's database failure.

=head2 getRelatedIdDescription( $id )

Retrieves description from identifiers like CVE id's.

Takes the identifier as argument.

    $obj->getRelatedIdDescription( 'CVE-2010-0001' );

If found, it will also collect all related Advisory ids. Note that it will only collect the last published advisories.

Returns an HASH reference containing all columns of table identifier_description and, if found, related advisory id's with key name C<ids>.

=head2 getRelatedIds( $digest )  

Retrieves identifiers that are related with the item.

Takes the item digest as argument:

    $obj->getRelatedIds( 'YCpWzDJgrxy+aWdXzaf2lw' );

The method searches the table identifier for the supplied digest.

Returns an ARRAY of all the identifiers found. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if there's database failure.

=head2 getRelatedItemsIdMatch( $digest )

Retrieves all items that having matching identifiers.

Takes the item digest as argument:

    $obj->getRelatedItemsIdMatch( 'YCpWzDJgrxy+aWdXzaf2lw' );

Note: the column C<created> is converted to string and is formatted to 'DD-MM-YYYY HH24:MI:SS' (example: '23-12-2008 14:23:55') and renamed to C<item_date>.

Also: the resulting items are ordered by date (column C<created>) descending. So newest items first.

Returns all the items found in an ARRAY. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if there's database failure.

=head2 getRelatedItemsKeywordMatch( $digest, \@keywords )

Retrieves all the items where the title matches combinations of the supplied keywords.

Takes two arguments, both mandatory. Argument one is the item digest, second is an ARRAY of keywords:

    $obj->getRelatedItemsKeywordMatch( 'YCpWzDJgrxy+aWdXzaf2lw', [ 'keyword1', 'keyword2' ] );

The search is done by combining two keywords:

    ...( ( title ILIKE 'keyword_1' ) AND ( title ILIKE 'keyword_2' ) ) OR ( ( title ILIKE 'keyword_1 ) AND ( title ILIKE 'keyword_3' ) )...
 
The method creates all combinations of keywords.

Returns all the items found. Sets C<< $obj->{errmsg} >> of this object to C<< Taranis::Database->{db_error_msg} >> if there's database failure.

=head2 nextObject( ) & getObject( )

Method to retrieve the list that is generated by a method like loadCollection().

This way of retrieval can be used to get data from the database one-by-one.

Both methods don't take arguments.

    $obj->loadCollection( $args );

    while( $obj->nextObject ) {
        push @list, $obj->getObject;
    }

=head2 setIsMailedFlag( $digest )

This method is used to set the is_mailed flag of an item when a user uses the 'E-mail the item' option in Assess.

It takes the item digest as argument.

    $obj->setIsMailedFlag( 'YCpWzDJgrxy+aWdXzaf2lw' );

Returns TRUE if it's successful, FALSE on database failure. Also sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >> on failure.

=head2 setAssessItem( digest => $digest )

Update assess item. Digest argument is mandatory and is used for item lookup, all other arguments must be columns of table 'item'.

=head2 getAttachmentInfo( $entity, $info )

Retrieves information on possible attachments in an email item.

First argument is an MIME::Entity object which can be created by using MIME::Parser as follows:

    my $parser = MIME::Parser->new();
    my $entity = $parser->parse_data( $email_body_text );

The second argument should be supplied with value C<undef>. The method uses this argument only when in recursion.

Returns an HASH reference containing the filename and filetype of the attachments.

Returns FALSE if the contenttype is not C<application>, C<image>, C<audio> or C<video>. 
Also returns FALSE in case contenttype is C<application> but content disposition is not attachment. 

=head2 getAttachment( $entity, $name )

Retrieves the complete attachment as raw text.
Takes a MIME::Entity object as first argument (see getAttachmentInfo() ). 
Second argument is the name of the attachment which can retrieved by getAttachmentInfo().

    my $parser = MIME::Parser->new();
    my $entity = $parser->parse_data( $email_body_text );
    $obj->getAttachment( $messageEntity, 'my_attachment.pdf' );

Returns the attachment as raw text.

=head2 getAddedToPublicationBulk( item_digest => \@itemDigests )

Retrieves per assess item to which publication type the item has been added.
Returns an HASH reference where the key is the item digest and the values are list of record of the table 'item_publication_type'.

=head2 getItemsAddedToPublication( $beginDate, $endDate, $publicationTypeId, 'vuln_threats' )

Retrieves a list of assess items which are added to a certain publication type.

Returns a list of items.

=head2 addToPublication( $itemDigest, $publicationTypeId, $publicationSpecifics ) & removeFromPublication( $itemDigest, $publicationTypeId, $publicationSpecifics )

Adds/removes an assess item to/from a publication type which can be used within that publication. 

$publicationSpecifics can be one the following: 

=over

=item *

media_exposure

=item *

vuln_threats

=item *

community_news

=item *

publ_advis

=item *

linked_item

=back

=head2 getStatusDictionary()

Returns the assess status mapping as HASH reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<No items have been changed. Perhaps you tried to change items with status 'waitingroom'.>

Message is caused by trying to change the status of items that have status 'waitingroom' (value 3). This is not allowed in Taranis.
The message originates from method setItemStatus().

=item *

I<No description available.>

Message is caused by method getRelatedIdDescription() when there is no description in the database for specified identifier. 
If there's a description available online, running admin script cve_descriptions.pl will solve this issue.

=item * 

I<Item id missing.>

Message is caused by setIsMailedFlag() when the item digest is missing.

=back

=cut
