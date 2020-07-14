# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::ImportPhoto;

use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::SoftwareHardware;
use Tie::IxHash;
use SQL::Abstract::More;
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

sub addImportPhotoEntry {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	return $self->addToImport( "import_photo_software_hardware", \%inserts );
}

sub addImportPhoto {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	return $self->addToImport( "import_photo", \%inserts );
}

sub addImportSoftwareHardware {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	return $self->addToImport( "import_software_hardware", \%inserts );
}

#TODO: needs to be replaced by Taranis::Database->addObject()
sub addToImport {
	my ( $self, $table ,$inserts ) = @_;
	undef $self->{errmsg};  

	my ( $stmnt, @bind ) = $self->{sql}->insert( $table, $inserts );
	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getPhotoDetails {
	my ( $self, $photoId ) = @_;
	
	my $select = "ip.*, to_char(created_on, 'DD-MM-YYYY') AS created, cg.name, u.fullname, to_char(imported_on, 'DD-MM-YYYY') AS imported";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', $select, { 'ip.id' => $photoId } );

	my %join = (
		'JOIN constituent_group cg' => { 'cg.id' => 'ip.group_id' },
		'LEFT JOIN users u' => { 'u.username' => 'ip.imported_by' }
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $photoDetails = $self->{dbh}->fetchRow();
	
	return $photoDetails;
}

sub getNewPhoto {
	my ( $self, %settings ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', 'ish.*', \%settings, 'ish.producer, ish.name, ish.cpe_id' );
	tie my %join, "Tie::IxHash";
	
	%join = (
		'JOIN import_photo_software_hardware ipsh' => { 'ipsh.photo_id' => 'ip.id' }, 
		'JOIN import_software_hardware ish' => { 'ish.id' => 'ipsh.import_sh' } 
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @photo;
	while ( $self->nextObject() ) {
		push @photo, $self->getObject();
	}
	
	return \@photo;
}

sub sortNewPhoto {
	my ( $self, $photo, $group_id, $photoId ) = @_;
	
	my $sh = Taranis::SoftwareHardware->new();
	my $softwareHardwareTypes = $sh->getBaseTypes();
	
	foreach my $type ( keys( %$softwareHardwareTypes ) ) {
		$softwareHardwareTypes->{ lc( delete( $softwareHardwareTypes->{$type} ) ) } = lc( $type ); 
	}
	
	my @import;
	PHOTOITEM:
	foreach my $photoItem ( @$photo ) {

		my $importItem_id = $photoItem->{id};
		my $producer = $photoItem->{producer};
		my $productName = $photoItem->{name};
		my $cpe_id = $photoItem->{cpe_id};
		my $type = ( $photoItem->{type} ) ? $photoItem->{type} : '';

		my $okToImport = $self->isOkToImport( $importItem_id, $photoId );

		next PHOTOITEM if ( 
			(
				defined( $okToImport ) && $okToImport == 0
			)
			|| $self->openIssueExists( $importItem_id )
		);

		# if closed issue exists of type 2 or 3, the import should take the soft_hard_id from issue
		if ( my $issue = $self->closedIssueExists( $importItem_id, $photoId ) ) {

			if ( !$issue->{create_new_issue} || ( $issue->{create_new_issue} && $self->getIssue( followup_on_issue_nr => $issue->{id} )->{status} == 3 ) ) {

				if ( $sh->countUsage( soft_hard_id => $issue->{soft_hard_id}, group_id => $group_id ) ) {
					push @import, { 
						id => $importItem_id,
						producer => $producer, 
						name => $productName, 
						cpe_id => $cpe_id, 
						type => $type,
						soft_hard_id => $issue->{soft_hard_id},
						alreadyInPhoto => 1
					};
				} else {
					push @import, { 
						id => $importItem_id,
						producer => $producer, 
						name => $productName, 
						cpe_id => $cpe_id, 
						type => $type,
						issueType => $issue->{type},
						soft_hard_id => $issue->{soft_hard_id},
						hasClosedIssue => 1
					};
				}
			}
		} elsif ( $cpe_id && $self->{dbh}->checkIfExists( { cpe_id => $cpe_id, deleted => 0 }, "software_hardware" ) ) {

			## Exact Match on CPE ID

			if ( $sh->countUsage( cpe_id => $cpe_id, deleted => 0, 'group_id' => $group_id ) ) {

				## Constituent has Software/Hardware in old photo  
				push @import, 
				{ 
					id => $importItem_id,
					producer => $producer, 
					name => $productName, 
					cpe_id => $cpe_id, 
					type => $type, 
					alreadyInPhoto => 1
				};
			} else {
				my $inUse = (
					$sh->countUsage( cpe_id => $cpe_id, deleted => 0 ) 
					|| ( defined( $okToImport ) && $okToImport ) 
				) ? 1 : 0; 

				## Constituent does NOT have Software/Hardware in old photo

				push @import,
				{ 
					id => $importItem_id,
					producer => $producer,
					name => $productName,
					cpe_id => $cpe_id,
					type => $type,
					exactMatch => 1, 
					inUse => $inUse 
				};
			}

		} elsif (
			my $count =	$self->{dbh}->countRows(
				{ 
					producer => { -ilike => $producer } , 
					name => { -ilike => $productName },
					type => $softwareHardwareTypes->{ lc( $type ) }, 
					deleted => 0 
				},
				'software_hardware'
			)
		) {

			if ( $sh->countUsage( 
					producer => { -ilike => $producer },
					name => { -ilike => $productName },
					type => $softwareHardwareTypes->{ lc( $type ) },
					deleted => 0, 
					group_id => $group_id
				)
			) {
				
				## Constituent has Software/Hardware in old photo
				
				push @import, 
				{ 
					id => $importItem_id,
					producer => $producer, 
					name => $productName, 
					cpe_id => $cpe_id, 
					type => $type, 
					alreadyInPhoto => 1
				};
			
			} else {
			
				if ( $count > 1 ) {
					push @import,
					{
						id => $importItem_id,
						producer => $producer,
						name => $productName,
						cpe_id => $cpe_id,
						type => $type,
						hasDuplicates => 1 
					};
				
				} else {

					my $inUse = (
						$sh->countUsage(
							producer => $producer,
							name => $productName,
							type => $softwareHardwareTypes->{ lc( $type ) },
							deleted => 0
						)
						|| ( defined( $okToImport ) && $okToImport )
					) ? 1 : 0;

					push @import,
					{ 
						id => $importItem_id,
						producer => $producer,
						name => $productName,
						cpe_id => $cpe_id,
						type => $type,
						exactMatch => 1,
						noCpe => 1,
						inUse => $inUse
					};
				}
			}
		} else {
			push @import,
			{
				id => $importItem_id,
				producer => $producer,
				name => $productName,
				cpe_id => $cpe_id,
				type => $type,
				noMatch => 1
			};
		}
	}
	
	return \@import;
}

sub getImportList {
	my ( $self, %settings ) = @_;

	my $select = "ip.id AS photo_id, to_char(ip.created_on, 'DD-MM-YYYY HH24:MI') AS created, cg.*, to_char(ip.imported_on, 'DD-MM-YYYY HH24:MI') AS imported";
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', $select , \%settings, 'created_on DESC' );
	
	my %join = ( 'JOIN constituent_group cg' => { 'cg.id' => 'ip.group_id' } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @groups;
	while ( $self->nextObject() ) {
		push @groups, $self->getObject();
	}
	
	return \@groups;
}

sub getImportSoftwareHardware {
	my ( $self, %settings ) = @_;
	return $self->getFromImport( "import_software_hardware", \%settings );
}

sub getImportSoftwareHardwareWithOpenIssues {
	my ( $self, %settings ) = @_;

	$settings{-or} = { 'ii.type' => 5, 'ii.status' => [0,1] };
	
	my $join = {
		'JOIN import_issue ii' => { 'ii.id' => 'ish.issue_nr' },
		'JOIN import_photo_software_hardware ipsh' => { 'ipsh.import_sh' => 'ish.id' }
	};
	
	my $select = "ish.*";
	
	return $self->getFromImport( "import_software_hardware ish", \%settings, $join, $select );
}

sub getFromImport {
	my ( $self, $table, $settings, $join, $select ) = @_;
	
	$select = ( $select ) ? $select : '*';
	
	my ( $stmnt, @bind ) = $self->{sql}->select( $table, $select, $settings );
	
	if ( $join ) {
		$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );
	}

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @import;
	while ( $self->nextObject() ) {
		push @import, $self->getObject();
	}
	
	return \@import;
}

sub getDeleteList {
	my ( $self, $sortedPhoto, $oldPhoto ) = @_;
		
	OLDITEM:
	for ( my $i = 0; $i < @$oldPhoto; $i++ ) {

		my $oldItemDesrciption = lc( $oldPhoto->[$i]->{producer} )
			. lc(  $oldPhoto->[$i]->{name} )
			. lc(  $oldPhoto->[$i]->{description} );

		NEWITEM:
		for ( my $j = 0; $j < @$sortedPhoto; $j++ ) {
		
			my $newItemDesrciption = lc( $sortedPhoto->[$j]->{producer} )
				. lc( $sortedPhoto->[$j]->{name} )
				. lc( $sortedPhoto->[$j]->{type} );

			if (
				$sortedPhoto->[$j]->{alreadyInPhoto}
				&& (
					(
						$oldPhoto->[$i]->{cpe_id} ne ""	
						&& $oldPhoto->[$i]->{cpe_id}
					 	&& $oldPhoto->[$i]->{cpe_id} =~ /^\Q$sortedPhoto->[$j]->{cpe_id}\E$/i
					)
					||
					$newItemDesrciption =~ /^\Q$oldItemDesrciption\E$/i
				) 
			) {
				delete  $oldPhoto->[$i];
				next OLDITEM;
			}
		}
	}
	
	return $oldPhoto;
}

sub setImportPhoto {
	my ( $self, $update, $where ) = @_;
	undef $self->{errmsg};
	return $self->setObject( 'import_photo', $update, $where  );	
}

sub deleteIssue {
	my ( $self, %delete ) = @_;
	return $self->deleteFromImport( 'import_issue', \%delete ); 
} 

sub deleteImportPhoto {
	my ( $self, %delete ) = @_;
	return $self->deleteFromImport( 'import_photo', \%delete ); 
}

sub unlinkSoftwareHardware {
	my ( $self, %unlink ) = @_;
	undef $self->{errmsg};
	return $self->deleteFromImport( 'import_photo_software_hardware', \%unlink );
}

sub deleteFromImport {
	my ( $self, $table, $delete ) = @_;
	undef $self->{errmsg};
	
	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, $delete );
	$self->{dbh}->prepare( $stmnt );
 
	if ( $self->{dbh}->executeWithBinds(@bind) > 0 ) {
		return 1;
	}

	if ( my $msg = $self->{dbh}->{db_error_msg} ) {
		$self->{errmsg} = $msg;
		return 0;
	}

	# In rare cases, the same line appears twice in the import.  When removed,
	# the first call to this method will return both... so there is nothing
	# to be removed the second time.  Not a fatal flaw.  Issue#196
	warn "WARNING: Import item to be deleted not found: ", join(';', %$delete);
	return 1;
} 

sub isOkToImport {
	my ( $self, $sh_id, $photo_id ) = @_;
	
	my %where = ( import_sh => $sh_id, photo_id => $photo_id );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo_software_hardware', 'ok_to_import', \%where );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $okToImport = $self->{dbh}->fetchRow();
	
	if ( exists( $okToImport->{ok_to_import} ) ) {
		return $okToImport->{ok_to_import};
	} else {
		return 0
	}
}

sub setOkToImport {
	my ( $self, $photo_id, $import_sh, $is_ok ) = @_;
	
	my %where = ( photo_id => $photo_id, import_sh => $import_sh );
	my %update = ( 'ok_to_import' => $is_ok );

	return $self->setObject( 'import_photo_software_hardware', \%update, \%where );
}

sub countOpenImports {
	my ( $self, $issueNr ) = @_;

	my $isNull = "IS NULL";
	
	my $where = { 'ish.issue_nr' => $issueNr, 'ip.imported_on' => \$isNull };
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', 'COUNT(*) as cnt', $where );
	
	tie my %join, "Tie::IxHash";
	
	%join = (
		'JOIN import_photo_software_hardware ipsh' => { 'ipsh.photo_id' => 'ip.id' },
		'JOIN import_software_hardware ish' => { 'ish.id' => 'ipsh.import_sh' }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my $result = $self->{dbh}->fetchRow();

	if ( defined( $result->{cnt} ) ) {
		return $result->{cnt};
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getGroupsByIssueNr {
	my ( $self, $issueNr ) = @_;
	
	my $where = {  
		'ish.issue_nr' => $issueNr,
		'ip.imported_on' => \"IS NOT NULL"
	};

	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', 'cg.*', $where );
	tie my %join, 'Tie::IxHash';
	
	%join = (  
		'JOIN import_photo_software_hardware ipsh' => { 'ipsh.photo_id' => 'ip.id' },
		'JOIN import_software_hardware ish' => { 'ish.id' => 'ipsh.import_sh' },
		'JOIN constituent_group cg' => { 'cg.id' => 'ip.group_id' }		
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my @groups;

	while ( $self->nextObject() ) {
		push @groups, $self->getObject();
	}

	return \@groups;
}

sub getPhotosForIssue {
	my ( $self, %where ) = @_;
	
	my $select = "ip.*, cg.name, to_char(imported_on, 'DD-MM-YYYY') AS imported";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_photo ip', $select, \%where, 'cg.name' );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		'JOIN constituent_group cg' => { 'cg.id' => 'ip.group_id' },
		'JOIN import_photo_software_hardware ipsh' => { 'ipsh.photo_id' => 'ip.id' },
		'JOIN import_software_hardware ish' => { 'ish.id' => 'ipsh.import_sh' }
	);
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my @photos; 

	while ( $self->nextObject() ) {
		push @photos, $self->getObject();
	}
	
	return \@photos;
}

sub importSoftwareHardware {
	my ( $self, $group_id, $soft_hard_id ) = @_;
	undef $self->{errmsg};

	my $inserts = { 'group_id' => $group_id, soft_hard_id => $soft_hard_id };
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( 'soft_hard_usage', $inserts ); 

	$self->{dbh}->prepare( $stmnt );
	
	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}	
}

sub removeSoftwareHardwareUsage {
	my ( $self, $group_id, $soft_hard_id ) = @_;
	
	return $self->deleteFromImport( 'soft_hard_usage', { group_id => $group_id, soft_hard_id => $soft_hard_id } );
}

################### ISSUE TYPES ########################
# 1. Not in use by other constituents, search source
# 2. Duplicates found in Taranis
# 3. No match found
# 4. Inform constituent
# 5. Don't import
########################################################

sub openIssueExists {
	my ( $self, $import_sh ) = @_;
	return $self->issueExists( { 'ish.id' => $import_sh, 'ii.status' => [ 0, 1 ] } );
}

sub closedIssueExists {
	my ( $self, $import_sh, $photoId ) = @_;
	return $self->issueExists( { 'ish.id' => $import_sh, 'ii.status' => [ 2, 3 ],  'ipsh.photo_id' => $photoId } );
}

sub issueExists {
	my ( $self, $where) = @_;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_software_hardware ish', 'ii.*', $where );

	my %join = ( 'JOIN import_issue ii' => { 'ii.id' => 'ish.issue_nr' } );

	foreach my $key ( keys %$where ) {
		if ( $key =~ /^ipsh/ ) {
			$join{ 'JOIN import_photo_software_hardware ipsh'} = { 'ipsh.import_sh' => 'ish.id' };
		}
	}

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $issue = $self->{dbh}->fetchRow();
	
	if ( defined( $issue->{id} ) ) {
		return $issue;
	} else {
		return 0;
	}
}

sub groupIssues($) {
	my ($self, $group) = @_;
	my $groupId = ref $group ? $group->{id} : $group;

	Database->simple->query( <<'__GROUP_ISSUES', $groupId )->hashes;
SELECT ii.*, ish.producer, ish.name, ish.type AS sh_type
  FROM import_issue                        AS ii
       JOIN import_software_hardware       AS ish   ON ish.issue_nr   = ii.id
       JOIN import_photo_software_hardware AS ipsh  ON ipsh.import_sh = ish.id
       JOIN import_photo                   AS ip    ON ip.id          = ipsh.photo_id
 WHERE ip.group_id = ?
   AND ( ii.status = 0 OR ii.status = 1 )
__GROUP_ISSUES
}

sub linkToIssue {
	my ( $self, $issueNr, $import_sh ) = @_;
	
	my $update = { issue_nr  => $issueNr };
	my $where  = { id => $import_sh };
	
	return $self->setObject( 'import_software_hardware', $update, $where );
}

sub unlinkFromIssue {
	my ( $self, $issueNr ) = @_;
	
	my $update = { issue_nr => undef };
	my $where  = { issue_nr => $issueNr };
	
	return $self->setObject( 'import_software_hardware', $update, $where );
}

sub setConstituentUsage {
	my ( $self, %ids ) = @_;
	undef $self->{errmsg};
	
	if ( !$ids{oldId} || !$ids{newId} ) {
		$self->{errmsg} = "Invalid ID.";
		return 0;
	}
	
	my $update = { soft_hard_id => $ids{newId} };
	my $where  = { soft_hard_id => $ids{oldId} };
	
	return $self->setObject( 'soft_hard_usage', $update, $where ); 
}

sub setIssue {
	my ( $self, $update, $where ) = @_;
	undef $self->{errmsg};
	
	return $self->setObject( 'import_issue', $update, $where );
}

sub createIssue {
	my ( $self, $description, $issueType, $comments, $followUpOnIssue ) = @_;
	
	$issueType = ( $issueType =~ /^[1-5]$/ ) ? $issueType : '0';
	$comments = ( $comments ) ? $comments : '';
	$followUpOnIssue = ( $followUpOnIssue ) ? $followUpOnIssue : undef;
	
	my $insert = {
		status => 0,
		description => $description,
		type => $issueType,
		comments => $comments,
		followup_on_issue_nr => $followUpOnIssue
	};
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( 'import_issue', $insert );
	
	$self->{dbh}->prepare( $stmnt );

	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return $self->{dbh}->getLastInsertedId( 'import_issue' );
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getIssue {
	my ( $self, %where ) = @_;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'import_issue', '*', \%where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	return $self->{dbh}->fetchRow();
}

# Above method does not provide all details we get with getIssues(), but we do want
# a simplification when getIssues() is used to lookup only a single issue.
sub getIssueDetails($) {
	my ($self, $issueNr) = @_;
	my $issue = $self->getIssues(issueNr => $issueNr);
	$issue ? $issue->[0] : ();
}

sub getIssues {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};
		
	my %where1;
	my ( @nests1, @nests2, @issues );
	
	my @search_status = @{ $searchFields{status} } if ( exists $searchFields{status} );
	delete $searchFields{status} if ( exists $searchFields{status} );

	my $start_date = delete $searchFields{start_date};
	my $end_date = delete $searchFields{end_date};

	my $limit  = sanitizeInput( "only_numbers", delete ( $searchFields{hitsperpage} ) ) if ( $searchFields{hitsperpage} );
	my $offset = sanitizeInput( "only_numbers", delete ( $searchFields{offset} ) ) if ( defined $searchFields{offset} );

	if ( $start_date && $end_date ) {
		$where1{'ii.created_on'} = {-between => [$start_date." 000000", $end_date." 235959"] };
	} elsif ( $start_date ) {
		$where1{'ii.created_on'} = { '>=' => $start_date." 000000"}
	} elsif ( $end_date) {
		$where1{'ii.created_on'} = { '<=' => $end_date." 235959"}
	}

	if ( @search_status ) {
		my ( @status1, @status2 ) ;
		foreach (  @search_status ) {
			push @status1, 'ii.status' => $_;
			push @status2, 'ii2.status' => $_;
		}
		push @nests1, \@status1;
		push @nests2, \@status2;
	}		
	
	if ( $searchFields{search} ne "" ) {
		my ( @search1, @search2 );
		push @search1, "ii.description" => { -ilike => "%".trim($searchFields{search})."%" };
		push @search1, "ii.comments" 		=> { -ilike => "%".trim($searchFields{search})."%" };
		push @search1, "ish.producer || ' ' || ish.name" => { -ilike => "%".trim($searchFields{search})."%" };
		
		push @search2, "ii2.description" => { -ilike => "%".trim($searchFields{search})."%" };
		push @search2, "ii2.comments"		 => { -ilike => "%".trim($searchFields{search})."%" };
		push @search2, "ish.producer || ' ' || ish.name" => { -ilike => "%".trim($searchFields{search})."%" };
				
		push @nests1, \@search1;
		push @nests2, \@search2;
	}

	$where1{'ii.id'} = $searchFields{issueNr} if ( $searchFields{issueNr} );

	$where1{'ipsh.photo_id'} = $searchFields{ photo_id }	if ( defined( $searchFields{ photo_id } ) );
	
	tie my %where2, "Tie::IxHash";
	%where2 = %where1;

	$where1{-and} = \@nests1 if ( @nests1 );	
	$where1{ 'ii.followup_on_issue_nr' } = \"IS NULL";
	
	my $select1 = "DISTINCT( ii.id ) AS ii_id, ii.status, ii.description, ii.type AS issueType, " 
		. "ii.comments, ii.soft_hard_id, ii.resolved_on, to_char( ii.created_on, 'DD-MM-YYYY HH24:MI' ) AS created, " 
		. "ii.create_new_issue, ii.followup_on_issue_nr, ish.producer, ish.name, ish.type, ish.cpe_id, " 
		. "resolved.fullname AS resolvedby, ish.id AS sh_id, to_char( ii.resolved_on, 'DD-MM-YYYY HH24:MI' ) AS resolvedon";

	my ( $stmnt1, @bind1 ) = $self->{sql}->select( 'import_issue ii', $select1, \%where1 );
	tie my %join1, "Tie::IxHash";
	%join1 = (
		'LEFT JOIN import_software_hardware ish' => { 'ish.issue_nr' => 'ii.id' },
		'LEFT JOIN users AS resolved' => { 'resolved.username' => 'ii.resolved_by' }
	);
	
	if ( defined( $searchFields{ photo_id } ) ) {
		$join1{ 'JOIN import_photo_software_hardware ipsh' } = { 'ipsh.import_sh' => 'ish.id' };
	}
	
	$stmnt1 = $self->{dbh}->sqlJoin( \%join1, $stmnt1 );

	my $select2 = $select1;
	$select2 =~ s/ii\./ii2\./g;

	tie my %join2, "Tie::IxHash";

	%join2 = %join1;
	
	foreach my $key ( keys %where2 ) {
		my $value = delete( $where2{ $key } );
		$key =~ s/ii\./ii2\./;
		$where2{ $key } = $value;
	}
	
	$where2{-and} = \@nests2 if ( @nests2 );
	
	$join2{ 'JOIN import_issue ii2'} = { 'ii2.followup_on_issue_nr' => 'ii.id' };
	
	my ( $stmnt2, @bind2 ) = $self->{sql}->select( 'import_issue ii', $select2, \%where2 );
	
	$stmnt2 = $self->{dbh}->sqlJoin( \%join2, $stmnt2 );
	
	my $orderBy = 'status, ii_id DESC, resolved_on DESC, created DESC';
	
	my $stmnt = "SELECT ii_id, status, description, issueType, " 
		. "comments, soft_hard_id, resolved_on, created, " 
		. "create_new_issue, followup_on_issue_nr, producer, name, type, cpe_id, " 
		. "resolvedby, sh_id, resolvedon "
		. "FROM ( $stmnt1 UNION $stmnt2 ) AS ISSUES ORDER BY $orderBy";
						 
#		SELECT DISTINCT( ii_id ) AS ii_id, status, created, producer, name, type, cpe_id, type AS issueType, resolvedby, sh_id, resolved_on  FROM (
#		
#		SELECT DISTINCT( ii.id ) AS ii_id, ii.status, to_char( ii.created_on, 'DD-MM-YYYY HH24:MI:SS' ) AS created, ish.producer, ish.name, ish.type, ish.cpe_id, ii.type AS issueType, resolved.fullname AS resolvedby, ish.id AS sh_id, ii.resolved_on 
#		FROM import_issue ii 
#		LEFT JOIN import_software_hardware ish ON ish.issue_nr = ii.id 
#		LEFT JOIN users AS resolved ON resolved.username = ii.resolved_by 
#		WHERE ( ( ii.status = 0 OR ii.status = 1 OR ii.status = 3 ) )
#		AND ii.followup_on_issue_nr IS NULL 
#		
#		UNION
#		
#		SELECT DISTINCT( ii2.id ) AS ii_id, ii2.status, to_char( ii2.created_on, 'DD-MM-YYYY HH24:MI:SS' ) AS created, ish.producer, ish.name, ish.type, ish.cpe_id, ii2.type AS issueType, resolved.fullname AS resolvedby, ish.id AS sh_id, ii2.resolved_on 
#		FROM import_issue ii 
#		LEFT JOIN import_software_hardware ish ON ish.issue_nr = ii.id 
#		LEFT JOIN users AS resolved ON resolved.username = ii.resolved_by 
#		JOIN import_issue ii2 ON ii2.followup_on_issue_nr = ii.id
#		WHERE ( ( ii2.status = 0 OR ii2.status = 1 OR ii2.status = 3 ) )
#		
#		) AS FOO
#		
#		ORDER BY status, resolved_on DESC, created DESC

	$self->{result_count} = $self->{dbh}->getResultCount( $stmnt, @bind1, @bind2 );

	if ( $limit && defined( $offset ) ) {
		$stmnt .= " LIMIT $limit OFFSET $offset";
	}

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind1, @bind2 );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	while ( $self->nextObject() ) {
		push @issues, $self->getObject();
	}
	return \@issues;
	
}

#TODO: split the two queries up.
sub getDuplicates {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};
	
	my @duplicates;
	
	my $sh = Taranis::SoftwareHardware->new();
	my $softwareHardwareTypes = $sh->getBaseTypes();
	
	foreach my $baseType ( keys( %$softwareHardwareTypes ) ) {
		$softwareHardwareTypes->{ lc( delete( $softwareHardwareTypes->{ $baseType } ) ) } = lc( $baseType );
	}
	
	my $producer = $settings{producer};
	my $product = $settings{product};
	my $type = $softwareHardwareTypes->{ lc( $settings{type} ) };
	
	my $where = {
		producer => { -ilike => $producer },
		name => { -ilike => $product },
		type => $type,
		deleted => 0
	};
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'software_hardware', '*', $where );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	while (  $self->nextObject() ) {
		push @duplicates, $self->getObject();
	}

	my $totalUsageCount = 0;
	foreach my $duplicate ( @duplicates ) {
		$duplicate->{usageCount} = $sh->countUsage( 'shu.soft_hard_id' => $duplicate->{id} );
		$totalUsageCount += $duplicate->{usageCount};
	}
	
	return \@duplicates, $totalUsageCount;
}

## HELPERS
sub setObject {
	my ( $self, $table, $update, $where ) = @_;
	undef $self->{errmsg};

	my ( $stmnt, @bind ) = $self->{sql}->update( $table, $update, $where );
	
	$self->{dbh}->prepare( $stmnt );

	my $result = $self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $result ) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		} 
	} else {
		$self->{errmsg} = "Update failed, corresponding id not found in database.";
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

Taranis::ImportPhoto

=head1 SYNOPSIS

  use Taranis::ImportPhoto;

  my $obj = Taranis::ImportPhoto->new( $oTaranisConfig );

  $obj->addToImport( $table, \%inserts );

  $obj->addImportPhoto( %photoSettings );

  $obj->addImportPhotoEntry( %photoSettings );

  $obj->addImportSoftwareHardware( %softwareHardware );

  $obj->closedIssueExists( $softwareHardwareID, $photoID );

  $obj->countOpenImports( $issueNumber );

  $obj->createIssue( $issueDescription, $issueType, $comments, $followUpOnIssue );

  $obj->deleteFromImport( $table, \%where );

  $obj->deleteImportPhoto( %where );

  $obj->deleteIssue( %where );

  $obj->getDeleteList( \@sortedPhoto, \@oldPhoto );

  $obj->getDuplicates( { producer => $poducer, product => $product, type => $type } );

  $obj->getFromImport( $table, \%where, \%join, $select );

  $obj->getGroupsByIssueNr( $issueNumber );

  $obj->getImportList( %where );

  $obj->getImportSoftwareHardware( %where );

  $obj->getImportSoftwareHardwareWithOpenIssues( %where );

  $obj->getIssue( %where );

  $obj->getIssues( %where );

  $obj->groupIssues($groupId);

  $obj->groupHasIssues($groupId);

  $obj->getNewPhoto( %where );

  $obj->getPhotoDetails( $photoID );

  $obj->getPhotosForIssue( %where );

  $obj->importSoftwareHardware( $constituentGroupID, $softwareHardwareID );

  $obj->isOkToImport( $softwareHardwareID, $photoID );

  $obj->issueExists( \%where );

  $obj->linkToIssue( $issueNumber, $softwareHardwareImportID );

  $obj->openIssueExists( $softwareHardwareImportID );

  $obj->removeSoftwareHardwareUsage( $constituentGroupID, $softwareHardwareID );

  $obj->setConstituentUsage( { oldId => $oldSoftwareHardwareID, newId => $newSoftwareHardwareID } );

  $obj->setImportPhoto( \%update, \%where );

  $obj->setIssue( \%update, \%where );

  $obj->setObject( $table, \%update, \%where );

  $obj->setOkToImport( $photoID, $softwareHardwareImportID, $is_ok );

  $obj->sortNewPhoto( \@photo, $constituentGroupID, $photoID );

  $obj->unlinkFromIssue( $issueNumber );

  $obj->unlinkSoftwareHardware( %where );

=head1 DESCRIPTION

All functionality for importing photo for a constituent group is bundled in this module.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::ImportPhoto> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::ImportPhoto->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 addToImport( $table, \%inserts )

Generic method for adding new items to database.

    $obj->addToImport( 'import_photo', { group_id => 34 } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 addImportPhoto( %photoSettings )

Add a new photo. Uses C<addToImport()>.

    $obj->addToImport( 'import_photo', { group_id => 34 } );

Returns output of C<addToImport()>.

=head2 addImportPhotoEntry( %photoSettings )

Adds software/hardware from importlist to a photo. Uses C<addToImport()>. 

    $obj->addImportPhotoEntry( photo_id => 34, import_sh => 57 );

Returns output of C<addToImport()>.

=head2 addImportSoftwareHardware( %softwareHardware )

Adds software/hardware to importlist. Uses C<addToImport()>.

    $obj->addImportSoftwareHardware( producer => 'ncsc', name => 'taranis', cpe_id => 'cpe:/a:ncsc:taranis:3.2', type => 'a' );

Returns output of C<addToImport()>.

=head2 closedIssueExists( $softwareHardwareID, $photoID )

Checks whether a closed issue exists for the given combination software/hardware and photo.

    $obj->closedIssueExists( 345, 5 );

Returns the issue as HASH reference or returns FALSE.

=head2 countOpenImports( $issueNumber )

Counts how many photos are not imported yet for given issue.

    $obj->countOpenImports( 89 );

If successfull returns a number. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 createIssue( $issueDescription, $issueType, $comments, $followUpOnIssue )

Adds a new issue. Parameters C<$comments> and C<$followUpOnIssue> are optional. 
Parameter C<$issueType> can be one of the following options:

=over

=item 1

Not in use by other constituents, search source

=item 2

Duplicates found in Taranis

=item 3

No match found

=item 4

Inform constituent

=item 5

Don't import

=back

    $obj->createIssue( 'Not in use by constituents (search for new source?)', 1, 'some comments', 875 );

If successful returns the issue ID. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteFromImport( $table, \%where )

Generic method for adding new items to database.

    $obj->deleteFromImport( 'import_photo', { id => 34 } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >>.

=head2 deleteImportPhoto( %where )

Deletes a photo, but will not delete all software/hardware associated with a photo.

    $obj->deleteImportPhoto( id => 34 );

Returns output of C<deleteImportPhoto()>.

=head2 deleteIssue( %where )

Deletes an issue.

    $obj->deleteIssue( id => 384 );

Returns output of C<deleteImportPhoto()>.

=head2 getDeleteList( \@sortedPhoto, \@oldPhoto )

Compares the old and new photo of a constituent and returns a list of items which will be deleted at pohot import.

    $obj->getDeleteList( \@newPhoto, \@oldPhoto );

Returns an ARRAY reference.

=head2 getDuplicates( { producer => $poducer, product => $product, type => $type } )

Retrieves software/hardware with set producer, product(name) and type. 
Also counts how many constituents have these software/hardware in use.

    $obj->getDuplicates( { producer => 'ncsc', product => 'taranis', type => 'a' } );

Returns two values at same time. First value is an ARRAY reference C<\@duplicates>. Second is a number representing the usage count.

=head2 getFromImport( $table, \%where, \%join, $select )

Generic query method. 

    $obj->getFromImport( 'import_software_hardware', { producer => 'ncsc' }, undef, '*' );

Returns an ARRAY reference.

=head2 getGroupsByIssueNr( $issueNumber )

Retrieve constituent groups which are linked to a specific issue.

    $obj->getGroupsByIssueNr( 234 );

Returns an ARRAY reference.

=head2 getImportList( %where )

Retrieve import lists.

    $obj->getImportList( imported_by => 'some user' );

Returns an ARRAY reference.

=head2 getImportSoftwareHardware( %where )

Retrieve software/hardware from import list.

    $obj->getImportSoftwareHardware( id => 34 );

Returns an ARRAY reference.

=head2 getImportSoftwareHardwareWithOpenIssues( %where )

Retrieve software/hardware from import list with open issues (status = 0 || 1).

    $obj->getImportSoftwareHardwareWithOpenIssues( photo_id => 34 );

Returns an ARRAY reference.

=head2 getIssue( %where )

Retrieve a single issue.

    $obj->getIssue( id => 87 );

Returns an HASH reference.

=head2 getIssues( %where )

Retrieves a list of issues. Useful for searching issues.
There are possibilities to search issues:

    $obj->getIssues( status => [0,3], search => 'search text', start_date => '20140131 1800', end_date => '20140331 1900', hitsperpage => 100, offset => 200 );

    $obj->getIssueDetails(78);

    $obj->getIssues( issueNr => 78 );

    $obj->getIssues( status => [2], photo_id => 5 );

    $obj->getIssues();

Returns a list of issues where each issue contains the following keys: 

=over

=item *

ii_id = issue ID 

=item *

status = issue status

=item *

created = formatted date of issue creation 'DD-MM-YYYY HH24:MI'

=item *

producer = software/hardware producer name

=item *

name = software/hardware product name

=item *

type = software/hardware type

=item *

cpe_id = software/hardware CPE ID

=item *

issueType = type of issue

=item *

resolvedby = username of user who resolved the issue

=item *

sh_id = software/hardware ID

=item *

resolved_on = formatted date of when issue was resolved 'DD-MM-YYYY HH24:MI'

=back

Returns an ARRAY reference.

=head2 getNewPhoto( %where )

Retrieves the software/hardware of a photo.

    $obj->getNewPhoto( group_id => 23, imported_on => undef ); # get photo of group 23 which has not been imported yet 

OR

    $obj->getNewPhoto( photo_id => 34, ok_to_import => 0 ); # get the items of photo with ID 34 which will not be imported 

Returns an ARRAY reference.

=head2 getPhotoDetails( $photoID )

Retrieves photo details which are all columns of table C<import_photo>, constituent group name and name of person who did the import.

    $obj->getPhotoDetails( 78 );

Returns an HASH reference.

=head2 getPhotosForIssue( %where )

Retrieves a list of photos which are associated to an issue.

    $obj->getPhotosForIssue( issue_nr => 78 );

Returns an ARRAY reference.

=head2 importSoftwareHardware( $constituentGroupID, $softwareHardwareID )

Add software/hardware to photo of constituent group.

    $obj->importSoftwareHardware( 67, 344 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 isOkToImport( $softwareHardwareID, $photoID )

Retrieves the ok_to_import setting for software/hardware with ID C<$softwareHardwareID> in photo with ID C<$photoID>.

    $obj->isOkToImport( 854, 3 ); 

Returns TRUE/FALSE.

=head2 issueExists( \%where )

Checks whether an issue exists and returns matching issue.

    $obj->issueExists( { 'ish.id' => 34, 'ii.status' => [ 2, 3 ],  'ipsh.photo_id' => 45 } ); 

Returns the issue as HASH reference or returns FALSE.

=head2 linkToIssue( $issueNumber, $softwareHardwareImportID )

Set the issue number for software/hardware in import list.

    $obj->linkToIssue( 34, 989 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 openIssueExists( $softwareHardwareImportID )

Same as issueExists() but sets C<ish.id> to C<$softwareHardwareImportID> and C<status> to C<[0,1]>.

    $obj->openIssueExists( 87 ); 

Returns the issue as HASH reference or returns FALSE.

=head2 removeSoftwareHardwareUsage( $constituentGroupID, $softwareHardwareID )

Removes software/hardware from current constituent group photo.

    $obj->removeSoftwareHardwareUsage( 23, 98 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setConstituentUsage( { oldId => $oldSoftwareHardwareID, newId => $newSoftwareHardwareID } )

Replaces software/hardware with ID C<$oldSoftwareHardwareID> for software/hardware with ID C<$newSoftwareHardwareID> in table C<soft_hard_usage>.
If several constituent groups are using software/hardware with ID C<$oldSoftwareHardwareID>, then all photos will be updated. 

    $obj->setConstituentUsage( { oldId => 34, newId => 56 } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setImportPhoto( \%update, \%where )

Updates table C<import_photo>.

    $obj->setImportPhoto( { imported_by => 'some user', imported_on => \"NOW()"}, { id => 908 } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setIssue( \%update, \%where )

Updates table C<import_issue>.

    $obj->setIssue( { status => 3 }, { id => $issue } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setObject( $table, \%update, \%where )

Generic update method.

    $obj->setObject( 'import_issue', { status => 3 }, { id => $issue } );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setOkToImport( $photoID, $softwareHardwareImportID, $is_ok )

Updates column C<ok_to_import> of table C<import_photo_software_hardware>.

    $obj->setOkToImport( 98, 232, 1 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 sortNewPhoto( \@photo, $constituentGroupID, $photoID )

Will sort the photo in a way that the list can presented with extra details about duplicates, usage and linked issues. 
It will add flags like C<alreadyInPhoto>, C<hasClosedIssue>, C<exactMatch>, C<inUse>, C<exactMatch>, C<noCpe> and C<noMatch>.

    $obj->sortNewPhoto( [list of software/hardware which retrieved by getNewPhoto()], 34, 56 );

Returns an ARRAY reference.

=head2 unlinkFromIssue( $issueNumber )

Sets column C<issue_nr> from records in table C<import_software_hardware> to C<NULL>.

    $obj->unlinkFromIssue( 897 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 unlinkSoftwareHardware( %where )

Deletes all entries from table C<import_photo_software_hardware>.

    $obj->unlinkSoftwareHardware( photo_id => 23 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid argument for sub!>

Caused by unlinkSoftwareHardware() when paramater is undefined.
You should input paramerte for unlinkSoftwareHardware(). 

=item *

I<Delete failed, corresponding id not found in database.> and I<Update failed, corresponding id not found in database.>

Caused by deleteFromImport() or setObject() when no records can be found.
You should check the C<$where> parameters.

=item *

I<Invalid ID.>

Caused by setConstituentUsage() when one of the two parameters is undefined.
You should check parameters C<oldId> and C<newId>.

=back

=cut
