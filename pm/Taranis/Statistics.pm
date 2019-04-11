# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Statistics;

use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use Time::Local;
use Tie::IxHash;

use File::Basename;
our $chartDirectorAvailable = eval {use perlchartdir; 1;};

use strict;
use POSIX;
use JSON;
use HTML::Entities qw(decode_entities);

#TODO: check of de binds kloppen op andere systemen vanwege willekeurige volgorde in de WHERE hash
#TODO: decode_entities voor text van de stats img
sub new {
	my ( $class, $config ) = @_;
	$config ||= Taranis::Config->new;
	
	my $statImageDir = find_config
		( $config->{custom_stats} ||
		  $config->{customstats_imagepath});   # old name

	-d $statImageDir or mkdir $statImageDir
		or die "ERROR: cannot create $statImageDir: $!\n";

	my $self = {
		errmsg => undef,
		statImageName => undef,
		statImageWidth => 720,
		statImageHeight => 500,
		statImageDir => $statImageDir.'/',
		statInfo => undef,
		pieChartRotateAngle => 0,
		pieChartRadius => 130,
		xAxisFontAngleAlternative => 30,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub loadCollection {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my @stats;

	my %where = $self->{dbh}->createWhereFromArgs( %args );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "statsimages", "*", \%where, "source" );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	
	while ( $self->nextObject() ) {
		push @stats, $self->getObject();
	}
	
	return \@stats;
}

#TODO: NOT IN USE ANYMORE?
sub setStatsTypeForUser {
  my ( $self, $statstype, $user ) = @_;
	undef $self->{errmsg};
	
  my ( $stmnt, @bind ) = $self->{sql}->update( "users", { statstype => $statstype }, { username => $user } );
  
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
		$self->{errmsg} = "Action failed, corresponding id not found in database.";
		return 0;		
	}  
}

sub getStatsCategories {
	my ( $self ) = @_;
	undef $self->{errmsg};
	my @categories;
	
	my $stmnt = "SELECT DISTINCT category FROM statsimages ORDER BY category;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		push @categories, $self->getObject()->{category};
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};
	return \@categories;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

####### custom statistics #######
# ASSESS
sub getItemsCollectedPerCategoryClustered {
	my ( $self, $clusters, $categories, $searchInArchive ) = @_;
	tie my %stats, "Tie::IxHash";

	undef $self->{errmsg};
	
	my %where;
	
	$where{created} = {-between => [ '20090101 000000', '20090101 235959' ] };
	$where{category} = '0';
	
	my @tables = ( 'item' );

	push @tables, 'item_archive' if ( $searchInArchive );

	my $firstRun = 1;

	foreach my $table ( @tables ) {

		my ( $stmnt, @bind ) = $self->{sql}->select( $table, 'COUNT(*) AS collected', \%where ); 

		$self->{dbh}->prepare( $stmnt );

		foreach my $category ( @$categories ) {
			
			tie %{ $stats{ $category->{name} } }, "Tie::IxHash" if ( $firstRun );

			foreach my $cluster ( @$clusters ) {

				$bind[0] = $category->{id};
				$bind[1] = $cluster->{startDate} . ' 000000';
				$bind[2] = $cluster->{endDate} . ' 235959';

				$self->{dbh}->executeWithBinds( @bind );
	
				my $stat = $self->{dbh}->fetchRow();
				
				$stats{ $category->{name} }->{ $cluster->{cluster} } += $stat->{collected};

			}
		}
		
		$firstRun = 0;
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;
}

sub getTotalOfItemsCollectedPerCategory {
	my ( $self, $startDate, $endDate, $categories, $searchInArchive ) = @_;
	my ( %where );
	
	undef $self->{errmsg};
	
	tie my %stats, "Tie::IxHash";
	
	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}	

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;
	
	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	$where{created} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	$where{category} = 0;
	
	my @tables = ( 'item' );
	
	push @tables, 'item_archive' if ( $searchInArchive );
	
	foreach my $table ( @tables ) {
		my ( $stmnt, @bind ) = $self->{sql}->select( $table, 'COUNT(*) AS collected', \%where ); 
		
		$self->{dbh}->prepare( $stmnt );
	
		foreach my $category ( @$categories ) {
			$bind[0] = $category->{id};
	
			$self->{dbh}->executeWithBinds( @bind );
	
			my $stat = $self->{dbh}->fetchRow();
			$stats{ $category->{name} } += ( exists( $stat->{collected} ) ) ? $stat->{collected} : 0;
		}
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	return \%stats;	
}

sub getTotalOfItemsCollectedPerStatus {
	my ( $self ) = @_;
	my $stats;
#TODO: ook in archive?	
	my $stmnt = "SELECT status, COUNT(*) AS cnt FROM item GROUP BY status";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		for ( $record->{status} ) {
			if (/0/) { $record->{statusName} = 'unread'; }
			elsif (/1/) {$record->{statusName} = 'read'; }
			elsif (/2/) {$record->{statusName} = 'important'; }
			elsif (/3/) {$record->{statusName} = 'analysis'; }
			else { $record->{statusName} = 'unknown'; }
		}
		$stats->{ $record->{statusName} } = $record->{cnt};
	}

	return $stats;
}

sub getSourcesMailed {
	my ( $self, $startDate, $endDate, $searchInArchive ) = @_;
	tie my %stats, "Tie::IxHash";
	
	undef $self->{errmsg};
	
	my %where;

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	my @tables = ( 'item' );

	push @tables, 'item_archive' if ( $searchInArchive );

	foreach my $table ( @tables ) {

		$where{created} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
		$where{is_mailed} = 1;

		my ( $stmnt, @bind ) = $self->{sql}->select( $table, 'COUNT(*) AS cnt, source', \%where ); 
		
		$stmnt .= ' GROUP BY source ORDER BY cnt DESC, source';
		
		$self->{dbh}->prepare( $stmnt );

		$self->{dbh}->executeWithBinds( @bind );

		while ( $self->nextObject() ) {
			my $record = $self->getObject();
			
			$stats{ $record->{source} } += $record->{cnt};
		}
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;		
} 

sub searchInArchive {
	my ( $self, $startDate ) = @_;
	#startDate in format dd-mm-yyyy
	
	my ( $day, $month, $year ) = split( "-", $startDate );
	
	$day = '0' . $day if ( length( $day ) != 2 );
	$month = '0' . $month if ( length( $month ) != 2 );
	
	my $yyyymmdd = $year . $month . $day;
	
	my $stmnt = "SELECT to_char( max(created), 'YYYYMMDD' ) AS maxdate FROM item_archive";

	$self->{dbh}->prepare( $stmnt );
	
	$self->{dbh}->executeWithBinds();
	
	my $date = $self->{dbh}->fetchRow();

	if ( $date->{maxdate} && $yyyymmdd < $date->{maxdate} ) {
		return 1;
	} else {
		return 0;
	}
}

# ANALYZE
sub getAnalysesClustered {
	my ( $self, $clusters ) = @_;
	
	tie my %stats, "Tie::IxHash";
	
	undef $self->{errmsg};
	
	my %where;
	
	$where{orgdatetime} = {-between => [ '20090101 000000', '20090101 235959' ] };
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'analysis', 'COUNT(*) AS collected', \%where ); 
	
	$self->{dbh}->prepare( $stmnt );

	foreach my $cluster ( @$clusters ) {

		$bind[0] = $cluster->{startDate} . ' 000000';
		$bind[1] = $cluster->{endDate} . ' 235959';

		$self->{dbh}->executeWithBinds( @bind );

		my $stat = $self->{dbh}->fetchRow();
		$stats{ $cluster->{cluster} } = ( exists( $stat->{collected} ) ) ? $stat->{collected} : 0;
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return \%stats;	
}

sub getTotalOfAnalysesPerStatus {
	my ( $self, $statuses ) = @_;
	tie my %stats, "Tie::IxHash";
	
	undef $self->{errmsg};

	my %where = ( status => { -ilike => $statuses } );
	my ( $stmnt, @bind ) = $self->{sql}->select( 'analysis', 'status, COUNT(*) AS cnt', \%where );
	
	$stmnt .= ' GROUP BY status ORDER BY cnt DESC';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$stats{ lc( $record->{status} ) } += $record->{cnt};
	}
	
	foreach my $status ( @$statuses ) {
		$stats{ lc( $status ) } = '0' if ( !exists( $stats{ lc( $status ) } ) );
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;
}

#TODO: delen door 3600 ook opnemen in database query
sub getAnalysesCreatedClosed {
	my ( $self, $clusters, $statuses ) = @_;

	tie my %stats, "Tie::IxHash";

	undef $self->{errmsg};
	
	my %where;
	
	$where{orgdatetime} = {-between => [ '01-01-2009 000000', '01-01-2009 235959' ] };

	$where{status} = { -ilike => \@$statuses };

	my ( $stmnt, @bind ) = $self->{sql}->select( 'analysis', 'AVG( AGE( last_status_change, orgdatetime) )', \%where ); 

	$stmnt = "SELECT EXTRACT( EPOCH FROM ( " . $stmnt . " ) ) AS epoch_average";

	$self->{dbh}->prepare( $stmnt );

	foreach my $cluster ( @$clusters ) {

		$bind[0] = $cluster->{startDate} . ' 000000';
		$bind[1] = $cluster->{endDate} . ' 235959';

		$self->{dbh}->executeWithBinds( @bind );

		my $stat = $self->{dbh}->fetchRow();

		$stats{ $cluster->{cluster} } = ( exists( $stat->{epoch_average} ) ) ? $stat->{epoch_average} / 3600 : 0;
		
		$stats{ $cluster->{cluster} } =~ s/(.*?\.\d).*$/$1/;
		
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return \%stats;	
}

sub getSourcesUsedInAnalyses {
	my ( $self, $startDate, $endDate ) = @_;
	tie my %stats, "Tie::IxHash";
	
	undef $self->{errmsg};
	
	my %where;
	
	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}		

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;
	
	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;

	$where{orgdatetime} = {-between => [  $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'analysis an', 'COUNT(an.*) AS sourcecount, it.source', \%where );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		'JOIN item_analysis ia' => { 'ia.analysis_id' => 'an.id' }, 
		'JOIN item it' => { 'it.digest' => 'ia.item_id' }
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= ' GROUP BY source ORDER BY sourceCount DESC';
	
	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );
	
	my $other = 0;
	my $count = 0;
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		
		$count++;
		
		if ( $count < 10 ) {
			$stats{ $record->{source} } = $record->{sourcecount};	
		} else {
			$other += $record->{sourcecount};
		}
	}

	$stats{other} = $other if ( $other > 0 );	

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;
}

# ADVISORIES
sub getAdvisoriesByClassificationClustered {
	my ( $self, $clusters ) = @_;

	tie my %stats, "Tie::IxHash";
	
	undef $self->{errmsg};
	
	my %classification = (
		1 => 'H',
		2 => 'M',
		3 => 'L'
	);

	my %where = ( deleted => 0, status => 3 );

	foreach my $version ( '1.00', { '!=' => '1.00' } ) {
		
		my $isVersion = ( $version eq '1.00' ) ? '1.00' : '>1.00';
		
		tie %{ $stats{ $isVersion } }, "Tie::IxHash";
		
		$where{version} = $version;
		
		foreach my $cluster ( @$clusters ) {
			
			$where{published_on} = {-between => [ $cluster->{startDate} . ' 000000', $cluster->{endDate}. ' 235959' ] };
			
			my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', 'COUNT(*) AS advisorycount, probability, damage', \%where );
			my %join = ( 'JOIN publication p' => { 'p.id' => 'pa.publication_id' } );
			
			$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
			
			$stmnt .= ' GROUP BY probability, damage ORDER BY probability, damage';

			$self->{dbh}->prepare( $stmnt );
			$self->{dbh}->executeWithBinds( @bind );
			
			tie %{ $stats{$isVersion}->{ $cluster->{cluster} } }, "Tie::IxHash";
			
			while ( $self->nextObject() ) {
				my $record = $self->getObject();

				my $combinedClassification = $classification{ $record->{probability} } . '/' . $classification{ $record->{damage} };

				$stats{ $isVersion }->{ $cluster->{cluster} }->{ $combinedClassification } = $record->{advisorycount};
				
			}
		}
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;
}

sub getAdvisoriesByClassification {
	my ( $self, $startDate, $endDate ) = @_;
	tie my %stats, "Tie::IxHash";
	undef $self->{errmsg};

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}	

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;
	
	my %classification = (
		1 => 'H',
		2 => 'M',
		3 => 'L'
	);

	my %where = ( deleted => 0, status => 3 );
	
	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	$where{published_on} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', 'COUNT(*) AS advisorycount, probability, damage', \%where );
	my %join = ( 'JOIN publication p' => { 'p.id' => 'pa.publication_id' } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= ' GROUP BY probability, damage ORDER BY probability, damage';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();

		my $combinedClassification = $classification{ $record->{probability} } . '/' . $classification{ $record->{damage} };

		$stats{ $combinedClassification } += $record->{advisorycount};
		
	}

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;
}

sub getAdvisoriesSentToCount {
	my ( $self, $startDate, $endDate ) = @_;
	tie my %stats, "Tie::IxHash";
	undef $self->{errmsg};

	my ( $dayStart, $monthStart, $yearStart ) = $self->splitDate( $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = $self->splitDate( $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}

	$self->{statInfo}->{start} = $dayStart . '-' . $monthStart . '-' . $yearStart;
	$self->{statInfo}->{end} = $dayEnd . '-' . $monthEnd . '-' . $yearEnd;

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;

	my %where = ( 'p2c.channel' => 1, timestamp => { -between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] } );
	my $select = "COUNT(*) AS advisorycount, ( pa.govcertid || ' [v' || pa.version || ']' ) AS advisoryid";
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication2constituent p2c', $select, \%where );
	my %join = ( 'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p2c.publication_id' } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= 'GROUP BY pa.govcertid, pa.version ORDER BY advisorycount DESC';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$stats{ $record->{advisoryid} } = $record->{advisorycount};
	}
	
	return \%stats;
}

sub getAdvisoriesByAuthorClustered {
	my ( $self, $clusters ) = @_;

	my %stats;
	tie my %join, "Tie::IxHash";
	
	undef $self->{errmsg};
	
	%join = (
		'JOIN publication p' => { 'p.id' => 'pa.publication_id' },
		'JOIN users u' => { 'u.username' => 'p.created_by' }  
	);

	# 1. get all author names who have created an advisory within the given period 

	my $startDate = $clusters->[0]->{startDate};
	my $endDate = $clusters->[$#$clusters]->{endDate};

	my %authorWhere = ( 
		'pa.deleted' => 0, 
		'p.status' => 3, 
		published_on => { 
			-between => [
				$startDate . ' 000000',
				$endDate . ' 235959'
			]
		}
	 );
	
	my ( $authorStmnt, @authorBind ) = $self->{sql}->select( 'publication_advisory pa', 'DISTINCT( username ) AS author, fullname', \%authorWhere );
	
	$authorStmnt = $self->{dbh}->sqlJoin( \%join, $authorStmnt );

	$self->{dbh}->prepare( $authorStmnt );
	$self->{dbh}->executeWithBinds( @authorBind );
	
	my %authors;
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$authors{ $record->{author} } = $record->{fullname};
	}

	# 2. count the advisories created by authors per cluster
	
	tie my %where, "Tie::IxHash";

	$where{published_on} = {-between => [ '01-01-2009 000000', '01-01-2009 235959' ] };
	$where{created_by} = 'dummy';
	$where{'pa.deleted'} = 0;
	$where{'p.status'} = 3;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', 'COUNT(*) AS advisories', \%where ); 

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );

	foreach my $username ( keys %authors ) {

		$bind[0] = $username;

		foreach my $cluster ( @$clusters ) {
	
			$bind[3] = $cluster->{startDate} . ' 000000';
			$bind[4] = $cluster->{endDate} 	 . ' 235959';

			$self->{dbh}->executeWithBinds( @bind );
 
			my $record = $self->{dbh}->fetchRow();

			tie %{ $stats{ $authors{ $username } } }, "Tie::IxHash" if ( !exists( $stats{ $authors{ $username } } ) );

			$stats{ $authors{ $username } }->{ $cluster->{cluster} } = ( exists( $record->{advisories} ) ) ? $record->{advisories} : 0;	
		}
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return \%stats;	
}

sub getAdvisoriesByAuthor {
	my ( $self, $startDate, $endDate ) = @_;
	
	my %stats;
	
	tie my %where, "Tie::IxHash";
	tie my %join, "Tie::IxHash";
	
	undef $self->{errmsg};

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;

	%join = (
		'JOIN publication p' => { 'p.id' => 'pa.publication_id' },
		'JOIN users u' => { 'u.username' => 'p.created_by' }
	);
	
	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	$where{published_on} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	$where{'pa.deleted'} = 0;
	$where{'p.status'} = 3;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', 'COUNT(*) AS advisories, fullname', \%where ); 

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$stmnt .= 'GROUP BY fullname';

	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );
			
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		
		$stats{ $record->{fullname} } = $record->{advisories};
	}
			
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return \%stats;	
	
}

sub getAdvisoriesByDate {
	my ( $self, $clusters, $type ) = @_;
	undef $self->{errmsg};
	tie my %stats, "Tie::IxHash";
	my %where;

	if ( $type =~ /(pie)/ ) {
		$self->{statInfo}->{start} = 'week ' . $clusters->[0]->{cluster};
		$self->{statInfo}->{end} = 'week ' . $clusters->[$#$clusters]->{cluster};
	} 

	$where{published_on} = {-between => [ '20090101 000000', '20090101 235959' ] };
	$where{deleted} = 'f';
	$where{status} = 3;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', 'COUNT(*) AS advisorycount', \%where );
	my %join = ( 'JOIN publication p' => { 'p.id' => 'pa.publication_id' } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	
	foreach my $cluster ( @$clusters ) {

		my $day = substr( $cluster->{startDate}, 6, 2 );
		my $month = substr( $cluster->{startDate}, 4, 2 );
		my $year = substr( $cluster->{startDate}, 0, 4 );
		
		my $week = $cluster->{cluster};
		
		tie %{ $stats{ 'week ' . $week } }, "Tie::IxHash" if ( $type =~ /(bar|text)/ );
		
		my $timeStamp = timelocal( 0, 0, 0, $day, $month - 1, $year );
		
		for ( my $i = 1; $i <= 7; $i++ ) {
			
			my $date = strftime( "%Y%m%d", localtime( $timeStamp ) );
			my $dayOfWeek = strftime( "%A", localtime( $timeStamp ) );
			 
			$bind[1] = $date . ' 000000';
			$bind[2] = $date . ' 235959';
			
			$self->{dbh}->executeWithBinds( @bind );
			
			my $stat = $self->{dbh}->fetchRow();
			
			if ( $type =~ /(bar|text)/ ) {
				$stats{ 'week ' . $week }->{ $dayOfWeek } = $stat->{advisorycount};
			} else {
				$stats{ $dayOfWeek } += $stat->{advisorycount};
			}
			
			$timeStamp += 86400; # add one day
		}
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return \%stats;
}

sub getAdvisoriesByPlatformClustered {
	my ( $self, $clusters, $platforms ) = @_;
	undef $self->{errmsg};
	tie my %stats, "Tie::IxHash";
	tie my %join, "Tie::IxHash";
	tie my %other, "Tie::IxHash";
	
	%join = (
		'JOIN publication p' => { 'p.id' => 'pa.publication_id' },
		'JOIN platform_in_publication pip' => { 'pip.publication_id' => 'p.id' },
		'JOIN software_hardware sh' => { 'sh.id' => 'pip.softhard_id' }
	);
	
	foreach my $cluster ( @$clusters ) {
		
		my %where;
		
		$where{'p.published_on'} = {-between => [ $cluster->{startDate} . ' 000000', $cluster->{endDate} . ' 235959' ] };
		$where{'pa.deleted'} = 0;
		$where{'p.status'} = 3;
		$where{'pa.version'} = '1.00';
		
		$where{'sh.id'} = $platforms if ( $platforms );
		
		my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', "COUNT(*) as cnt, sh.producer||' '||sh.name AS platform", \%where );
		
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		
		$stmnt .= ' GROUP BY platform ORDER BY cnt DESC, platform ';

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
		my $i = 1;
		
		while ( $self->nextObject() ) {
			my $record = $self->getObject();
			
			if ( $i <= 3 ) {
				$stats{ $record->{platform} }->{ $cluster->{cluster} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
			} else {
				$other{ $cluster->{cluster} } += ( $record->{cnt} ) ? $record->{cnt} : 0;
			}
			$i++;
		}
	}
	
	$stats{other} = \%other;

	return \%stats;
}

sub getAdvisoriesByPlatform {
	my ( $self, $startDate, $endDate, $platforms ) = @_;

	undef $self->{errmsg};
	tie my %stats, "Tie::IxHash";
	tie my %join, "Tie::IxHash";
	my %where;

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate."; #$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate."; #$@;
		return 0;
	}		

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
		
	$where{'p.published_on'} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	$where{'pa.deleted'} = 0;
	$where{'p.status'} = 3;
	$where{'pa.version'} = '1.00';
	
	$where{'sh.id'} = $platforms if ( $platforms );
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication_advisory pa', "COUNT(*) as cnt, sh.producer||' '||sh.name AS platform", \%where );
	
	%join = (
		'JOIN publication p' => { 'p.id' => 'pa.publication_id' },
		'JOIN platform_in_publication pip' => { 'pip.publication_id' => 'p.id' },
		'JOIN software_hardware sh' => { 'sh.id' => 'pip.softhard_id' }
	);
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= ' GROUP BY platform ORDER BY cnt DESC, platform ';

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my $i = 1;
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		
		if ( $i <= 5 ) {
			$stats{ $record->{platform} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
		} else {
			$stats{other} += ( $record->{cnt} ) ? $record->{cnt} : 0;
		}
		$i++;
	}	

	return \%stats;
} 

sub getListOfShPlatforms {
	my ( $self ) = @_;
	
	tie my %list, "Tie::IxHash";
	
	my $stmnt = 
		"SELECT id, producer||' '||name AS fullname FROM software_hardware"
		. " WHERE type = 'o' AND deleted = 'f'"
		. " ORDER BY fullname";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		
		$list{ $record->{id} } = $record->{fullname};	
	}
	
	return \%list;
}

sub getAdvisoriesPerShTypeClustered {
	my ( $self, $clusters ) = @_;
	undef $self->{errmsg};

	tie my %stats, "Tie::IxHash";
	my %where;	
	
	my @shTypes = ( 
		{ table => 'platform_in_publication', alias => 'pl'},
		{ table => 'product_in_publication', alias => 'pr'},
	);
	
	foreach my $shType ( @shTypes ) {
		
		foreach my $cluster ( @$clusters ) {

			$where{'p.published_on'} = {-between => [ $cluster->{startDate} . ' 000000', $cluster->{endDate} . ' 235959' ] };
			$where{'pa.deleted'} = 0;
			$where{'p.status'} = 3;
			$where{'pa.version'} = '1.00';

			my $select = 'COUNT(DISTINCT(' . $shType->{alias} . '.publication_id)) AS cnt, sht.description';
			my ( $stmnt, @bind ) = $self->{sql}->select( 'soft_hard_type sht', $select, \%where );
			
			tie my %join, "Tie::IxHash";
			%join = ( 
				'JOIN software_hardware sh' => { 'sh.type' => 'sht.base'},
				'JOIN ' . $shType->{table} . ' ' . $shType->{alias} => { $shType->{alias} . '.softhard_id' => 'sh.id' },
				'JOIN publication p' => { 'p.id' => $shType->{alias} . '.publication_id' },
				'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p.id' } 
			);
		
			$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
			
			$stmnt .= 'GROUP BY sht.description ORDER BY sht.description';

			$self->{dbh}->prepare( $stmnt );
			$self->{dbh}->executeWithBinds( @bind );
			
			while ( $self->nextObject() ) {
				my $record = $self->getObject();

				$stats{ $record->{description} }->{ $cluster->{cluster} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
			}
		}
	}

	return \%stats;
}

sub getAdvisoriesPerShType {
	my ( $self, $startDate, $endDate ) = @_;
	undef $self->{errmsg};
	
	tie my %stats, "Tie::IxHash";
	my %where;	

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate.";
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate.";
		return 0;
	}		

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;

	my @shTypes = ( 
		{ table => 'platform_in_publication', alias => 'pl'},
		{ table => 'product_in_publication', alias => 'pr'},
	);

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	foreach my $shType ( @shTypes ) {

		$where{'p.published_on'} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
		$where{'pa.deleted'} = 0;
		$where{'p.status'} = 3;
		$where{'pa.version'} = '1.00';

		my $select = 'COUNT(DISTINCT(' . $shType->{alias} . '.publication_id)) AS cnt, sht.description';
		my ( $stmnt, @bind ) = $self->{sql}->select( 'soft_hard_type sht', $select, \%where );
		
		tie my %join, "Tie::IxHash";
		%join = ( 
			'JOIN software_hardware sh' => { 'sh.type' => 'sht.base'},
			'JOIN ' . $shType->{table} . ' ' . $shType->{alias} => { $shType->{alias} . '.softhard_id' => 'sh.id' },
			'JOIN publication p' => { 'p.id' => $shType->{alias} . '.publication_id' },
			'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p.id' } 
		);
	
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		
		$stmnt .= 'GROUP BY sht.description ORDER BY sht.description';

		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
		
		while ( $self->nextObject() ) {
			my $record = $self->getObject();

			$stats{ $record->{description} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
		}
	}

	return \%stats;
}

sub getAdvisoriesPerConstituentTypeClustered {
	my ( $self, $clusters ) = @_;
	undef $self->{errmsg};

	tie my %stats, "Tie::IxHash";
	my %where;	
	
	foreach my $cluster ( @$clusters ) {

		$where{'p.published_on'} = {-between => [ $cluster->{startDate} . ' 000000', $cluster->{endDate} . ' 235959' ] };
		$where{'pa.deleted'} = 0;
		$where{'p.status'} = 3;

		my $select = 'COUNT(DISTINCT(p.id)) AS cnt, type_description';
		my ( $stmnt, @bind ) = $self->{sql}->select( 'constituent_type ct', $select, \%where );
		
		tie my %join, "Tie::IxHash";
		%join = ( 
			'JOIN constituent_group cg' => { 'cg.constituent_type' => 'ct.id'},
			'JOIN membership m' => { 'm.group_id' => 'cg.id' },
			'JOIN publication2constituent p2c' => { 'p2c.constituent_id' => 'm.constituent_id' },
			'JOIN publication p' => { 'p.id' => 'p2c.publication_id'},
			'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p.id' } 
		);
	
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		
		$stmnt .= 'GROUP BY type_description';
		
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
		
		while ( $self->nextObject() ) {
			my $record = $self->getObject();

			$stats{ $record->{type_description} }->{ $cluster->{cluster} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
		}
	}

	return \%stats;	
}

sub getAdvisoriesPerConstituentType {
	my ( $self, $startDate, $endDate ) = @_;
	undef $self->{errmsg};
	
	tie my %stats, "Tie::IxHash";
	my %where;	

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate.";
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate.";
		return 0;
	}
	
	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;

	$where{'p.published_on'} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	$where{'pa.deleted'} = 0;
	$where{'p.status'} = 3;

	my $select = 'COUNT(DISTINCT(p.id)) AS cnt, type_description';
	my ( $stmnt, @bind ) = $self->{sql}->select( 'constituent_type ct', $select, \%where );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		'JOIN constituent_group cg' => { 'cg.constituent_type' => 'ct.id'},
		'JOIN membership m' => { 'm.group_id' => 'cg.id' },
		'JOIN publication2constituent p2c' => { 'p2c.constituent_id' => 'm.constituent_id' },
		'JOIN publication p' => { 'p.id' => 'p2c.publication_id'},
		'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p.id' } 
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= 'GROUP BY type_description';
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();

		$stats{ $record->{type_description} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
	}

	return \%stats;	
}

sub getAdvisoriesByDamageDescriptionClustered {
	my ( $self, $clusters ) = @_;
	undef $self->{errmsg};

	tie my %stats, "Tie::IxHash";
	my %where;	

	foreach my $cluster ( @$clusters ) {

		$where{'p.published_on'} = {-between => [ $cluster->{startDate} . ' 000000', $cluster->{endDate} . ' 235959' ] };
		$where{'pa.deleted'} = 0;
		$where{'p.status'} = 3;
		$where{'dd.deleted'} = 0;

		my $select = 'COUNT(DISTINCT(p.id)) AS cnt, dd.description';
		my ( $stmnt, @bind ) = $self->{sql}->select( 'damage_description dd', $select, \%where );
		
		tie my %join, "Tie::IxHash";
		%join = ( 
			'JOIN advisory_damage ad' => { 'ad.damage_id' => 'dd.id'},
			'JOIN publication_advisory pa' => { 'pa.id' => 'ad.advisory_id' },
			'JOIN publication p' => { 'pa.publication_id' => 'p.id' } 
		);
	
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		
		$stmnt .= 'GROUP BY dd.description';
	
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
		
		while ( $self->nextObject() ) {
			my $record = $self->getObject();

			$stats{ $record->{description} }->{ $cluster->{cluster} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
		}
	}

	return \%stats;
}

sub getAdvisoriesByDamageDescription {
	my ( $self, $startDate, $endDate ) = @_;
	undef $self->{errmsg};
	tie my %stats, "Tie::IxHash";
	my %where;	

	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate.";
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate.";
		return 0;
	}

	$self->{statInfo}->{start} = $startDate;
	$self->{statInfo}->{end} = $endDate;

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;

	$where{'p.published_on'} = {-between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] };
	$where{'pa.deleted'} = 0;
	$where{'p.status'} = 3;
	$where{'dd.deleted'} = 0;

	my $select = 'COUNT(DISTINCT(p.id)) AS cnt, dd.description';
	my ( $stmnt, @bind ) = $self->{sql}->select( 'damage_description dd', $select, \%where );
	
	tie my %join, "Tie::IxHash";
	%join = ( 
		'JOIN advisory_damage ad' => { 'ad.damage_id' => 'dd.id'},
		'JOIN publication_advisory pa' => { 'pa.id' => 'ad.advisory_id' },
		'JOIN publication p' => { 'pa.publication_id' => 'p.id' } 
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= 'GROUP BY dd.description';
		
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();

		$stats{ $record->{description} } = ( $record->{cnt} ) ? $record->{cnt} : 0;
	}

	return \%stats;			
}

# OTHER
sub getPublicationsTimeTillPublished {
	my ( $self, $clusters ) = @_;
	tie my %stats, "Tie::IxHash";
	undef $self->{errmsg};
	
	my %publicationTypes;
	
	my $publicationTypeStmnt = 
		"SELECT DISTINCT(p.type), pt.title FROM publication p"
		. " JOIN publication_type pt ON pt.id = p.type";

	$self->{dbh}->prepare( $publicationTypeStmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$publicationTypes{ $record->{type} } = $record->{title};
	}
	
	my %where;
	$where{created_on} = {-between => [ '20090101 000000', '20090101 235959' ] };

	$where{type} = 1;

	my ( $stmnt, @bind ) = $self->{sql}->select( 'publication', 'AVG( AGE( published_on, created_on ) )', \%where ); 

	$stmnt = "SELECT ( SELECT EXTRACT( EPOCH FROM ( " . $stmnt . " ) ) ) / 3600 AS epoch_average";

	$self->{dbh}->prepare( $stmnt );

	foreach my $publicationType ( keys %publicationTypes ) {
		
		tie %{ $stats{ $publicationTypes{ $publicationType}  } }, "Tie::IxHash";
		
		$bind[2] = $publicationType;
	
		foreach my $cluster ( @$clusters ) {
	
			$bind[0] = $cluster->{startDate} . ' 000000';
			$bind[1] = $cluster->{endDate} . ' 235959';

			$self->{dbh}->executeWithBinds( @bind );
	
			my $stat = $self->{dbh}->fetchRow();

			$stats{ $publicationTypes{ $publicationType } }->{ $cluster->{cluster} } = ( $stat->{epoch_average} ) ? $stat->{epoch_average} : 0;
			
			$stats{ $publicationTypes{ $publicationType } }->{ $cluster->{cluster} } =~ s/(.*?\.\d).*$/$1/;
			
		}
	}
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	return \%stats;	

#	SELECT (
#		SELECT EXTRACT( EPOCH FROM ( 
#			SELECT AVG( AGE( published_on, created_on ) )
#			FROM publication 
#			WHERE ( created_on BETWEEN '20090101' AND '20091101') 
#			AND type = 22
#		)	)  
#	) / 3600 AS epoch_average
}

sub getSentToConstituentsPhotoUsage {
	my ( $self, $startDate, $endDate ) = @_;
	undef $self->{errmsg};
	tie my %stats, "Tie::IxHash";
	tie my %join, "Tie::IxHash";

	%join = (
		'JOIN membership m' => { 'm.group_id' => 'cg.id' },
		'JOIN publication2constituent p2c' => { 'p2c.constituent_id' => 'm.constituent_id' },
		'JOIN publication p' => { 'p.id' => 'p2c.publication_id' }, 
		'JOIN publication_advisory pa' => { 'pa.publication_id' => 'p.id' }
	);

	my ( $dayStart, $monthStart, $yearStart ) = $self->splitDate( $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate.";
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = $self->splitDate( $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate.";
		return 0;
	}		

	$self->{statInfo}->{start} = $dayStart . '-' . $monthStart . '-' . $yearStart;
	$self->{statInfo}->{end} = $dayEnd . '-' . $monthEnd . '-' . $yearEnd;

	my $dbAcceptableStartDate = $yearStart . $monthStart . $dayStart;
	my $dbAcceptableEndDate = $yearEnd . $monthEnd . $dayEnd;
	
	my %photoUsage = ( 'photo in use' => 1, 'photo not in use' => 0 );
	
	foreach my $hasPhoto ( keys %photoUsage ) {
		
		tie %{ $stats{ $hasPhoto } }, "Tie::IxHash";
		
		my %where = (
			'cg.use_sh' => $photoUsage{ $hasPhoto }, 
			'pa.deleted' => 0,
			'p2c.channel' => 1,
			'p.status' => 3,
			'cg.status' => { '!=' => 1 },
			'p.published_on' => { -between => [ $dbAcceptableStartDate . ' 000000', $dbAcceptableEndDate . ' 235959' ] }
		);
		
		my $select = "COUNT( DISTINCT( cg.id ) ) AS cnt, pa.govcertid||' [v'||pa.version||']' AS advisoryid";
		my ( $stmnt, @bind ) = $self->{sql}->select( 'constituent_group cg', $select, \%where );
		
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		
		$stmnt .= 'GROUP BY advisoryid ORDER BY advisoryid';
		
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds( @bind );
		
		while ( $self->nextObject() ) {
			my $record = $self->getObject();
			
			$stats{ $hasPhoto }->{ $record->{advisoryid} } = $record->{cnt}; 
		}
	}

	return \%stats;
}

sub getTop10ShConstituents {
	my ( $self ) = @_;

	tie my %stats, "Tie::IxHash";
	my $stmnt = 	
		"SELECT COUNT( soft_hard_id ) AS cnt, sh.producer||' '||sh.name AS fullname FROM soft_hard_usage shu"
		. " JOIN software_hardware sh ON sh.id = shu.soft_hard_id"
		. " GROUP BY fullname"
		. " ORDER BY cnt DESC, fullname" 
		. " LIMIT 10";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		my $record = $self->getObject();
		$stats{ $record->{fullname} } = $record->{cnt};
	}
	
	return \%stats;	
}
## subs for calculating clustering dates
sub createClusters {
	my ( $self, $startDate, $endDate, $clustering ) = @_;
	my ( $statInfo );
	
	my @clusters;
	
	my ( $dayStart, $monthStart, $yearStart ) = split( "-", $startDate );
	if ( !$self->checkDate( $startDate) ) {
		$self->{errmsg} = "Invalid date given: $startDate.";#$@;
		return 0;
	}
	
	my ( $dayEnd, $monthEnd, $yearEnd ) = split( "-", $endDate );
	if ( !$self->checkDate( $endDate ) ) {
		$self->{errmsg} = "Invalid date given: $endDate.";#$@;
		return 0;
	}
	
	my $endDateInt = 0;
	my $date = $startDate;	
	my $addYear = ( $yearStart ne $yearEnd ) ? 1 : 0;
	
	my $timeStampStart = timelocal( 0, 0, 0, $dayStart, $monthStart - 1, $yearStart);
	my $timeStampEnd = timelocal( 0, 0, 0, $dayEnd, $monthEnd- 1, $yearEnd);
	
	for ( $clustering ) {
		if (/week/) {
			
			$statInfo->{type} = 'week';
			$statInfo->{start} = strftime( "%V", localtime($timeStampStart) );
			$statInfo->{end} = strftime( "%V", localtime($timeStampEnd) );;
			$statInfo->{startYear} = strftime( "%Y", localtime($timeStampStart) );
			$statInfo->{endYear} = strftime( "%Y", localtime($timeStampEnd) );
			
			while ( strftime( "%Y%m%d", localtime($timeStampEnd) ) > $endDateInt ) {
				my $tempSave = $self->calcStartEndOfWeek( $date, $addYear );

				$endDateInt = strftime( "%Y%m%d", localtime( $tempSave->{endDateTimeStamp} ) );
				
				push @clusters, { startDate => $tempSave->{startDate}, endDate => $tempSave->{endDate}, cluster => $tempSave->{weekNumber} };
				
				$timeStampStart += 7 * 86400; # add 7 days
			 	$date = strftime( "%d-%m-%Y", localtime($timeStampStart) );
			}

		} elsif (/month/) {
			
			$statInfo->{type} = 'month';
			$statInfo->{start} = strftime( "%B", localtime($timeStampStart) );
			$statInfo->{end} = strftime( "%B", localtime($timeStampEnd) );
			$statInfo->{startYear} = strftime( "%Y", localtime($timeStampStart) );
			$statInfo->{endYear} = strftime( "%Y", localtime($timeStampEnd) );
			
			while ( strftime( "%Y%m%d", localtime($timeStampEnd) ) > $endDateInt ) {
				my $tempSave = $self->calcStartEndOfMonth( $date, $addYear );

				$endDateInt = strftime( "%Y%m%d", localtime($tempSave->{endDateTimeStamp}) );

				push @clusters, { startDate => $tempSave->{startDate}, endDate => $tempSave->{endDate}, cluster => $tempSave->{month} };

				$timeStampStart += ( 86400 * 31 );  # simulates behavior of DateTime->add( months => 1 )

			 	$date = strftime( "%d-%m-%Y", localtime($timeStampStart) );
			}
			
		} elsif (/day/) {
			
			$statInfo->{type} = 'day';
			$statInfo->{start} = strftime( "%d-%m-%Y", localtime($timeStampStart) );
			$statInfo->{end} = strftime( "%d-%m-%Y", localtime($timeStampEnd) );

			while ( strftime( "%Y%m%d", localtime($timeStampEnd) ) > $endDateInt ) {
				my $tempSave = $self->calcStartEndOfDay( $date );

				$endDateInt = strftime( "%Y%m%d", localtime($tempSave->{endDateTimeStamp} ) );

				push @clusters, { startDate => $tempSave->{startDate}, endDate => $tempSave->{endDate}, cluster => $tempSave->{day} };
			 	
			 	$timeStampStart += 86400;
			 	$date = strftime( "%d-%m-%Y", localtime($timeStampStart) );
			}
						
		} else { 
			$self->{errmsg} = "Invalid cluster given.";
			return 0;
		}
	}
	
	$self->{statInfo} = $statInfo; 
	
	return \@clusters;
}

sub calcStartEndOfWeek {
	my ( $self, $date, $addYear ) = @_; # format: dd-mm-yyyy
	my %returnDates;
	
	undef $self->{errmsg};
	my ( $day, $month, $year ) = split( "-", $date );
	my $timeStamp = timelocal( 0, 0, 0, $day, $month - 1, $year );

	if ( $self->checkDate( $date ) ) {
		
		my $weekday = strftime( "%u", localtime($timeStamp) );

		my $startOfWeekDay = $weekday - 1;
		my $startDateTimeStamp = $timeStamp - ( $startOfWeekDay * 86400 );
		
		$returnDates{startDate} = strftime( "%Y%m%d", localtime($startDateTimeStamp) );
		
		$timeStamp = timelocal( 0, 0, 0, $day, $month - 1, $year ); # reset timestamp
		
		my $endOfWeekDay = 7 - $weekday;
		my $endDateTimeStamp = $timeStamp + ( $endOfWeekDay * 86400 );
		
		$returnDates{endDateTimeStamp} = $endDateTimeStamp;
		$returnDates{endDate} = strftime( "%Y%m%d", localtime($endDateTimeStamp) );
		
		$returnDates{weekNumber} = strftime( "%V", localtime($timeStamp) );
		$returnDates{weekNumber} .= ' ' . strftime( "%Y", localtime($endDateTimeStamp) ) if ( $addYear );
	
		return \%returnDates;
	} else {
		$self->{errmsg} = 'Invalid date given.';
		logErrorToSyslog( "calcStartEndOfWeek error: " . $self->{errmsg} );
		return 0;
	}
}

sub calcStartEndOfMonth {
	my ( $self, $date, $addYear ) = @_; # format: dd-mm-yyyy
	my %returnDates;
	my $dt;
	
	undef $self->{errmsg};
	
	my ( $day, $month, $year ) = split( "-", $date );	
	my $timeStamp = timelocal( 0, 0, 0, $day, $month - 1, $year );
	
	if ( $self->checkDate( $date ) ) {		
		$returnDates{startDate} = $year . $month . "01";
		
		my $lastDayOfMonth;
		
		for ( my $i = 28; $i < 32; $i++ ) {
			eval{
				my $checkDate = timelocal( 0, 0, 0, $i, $month - 1, $year );
			};
			
			if ( !$@ ) {
				$lastDayOfMonth = $i;
			}
		}

		$returnDates{endDate} = $year . $month . $lastDayOfMonth;
		
		my $endDateTimeStamp = timelocal( 0, 0, 0, $lastDayOfMonth, $month - 1, $year );
		
		$returnDates{endDateTimeStamp} = $endDateTimeStamp;
		$returnDates{month} = strftime( "%B", localtime($endDateTimeStamp) );
		$returnDates{month} .= ' ' . strftime( "%Y", localtime($endDateTimeStamp) ) if ( $addYear );
				
		return \%returnDates;	
	} else {
		$self->{errmsg} = 'Invalid date given.';
		logErrorToSyslog( "calcStartEndOfMonth error: " . $self->{errmsg} );
		return 0;		
	}
}

sub calcStartEndOfDay {
	my ( $self, $date ) = @_; # format: dd-mm-yyyy
	my %returnDates;

	undef $self->{errmsg};
	
	my ( $day, $month, $year ) = split( "-", $date ); 
	my $timeStamp = timelocal( 0, 0, 0, $day, $month - 1, $year );
	
	if ( $self->checkDate( $date ) ) {
		
		$returnDates{startDate} = strftime( "%Y%m%d", localtime($timeStamp) );
		$returnDates{endDate} = strftime( "%Y%m%d", localtime($timeStamp) );
		$returnDates{endDateTimeStamp} = $timeStamp;
		$returnDates{day} = strftime( "%d-%m-%Y", localtime($timeStamp) );
		
		return \%returnDates;
	} else {
		$self->{errmsg} = 'Invalid date given.';
		logErrorToSyslog( "calcStartEndOfDay error: " . $self->{errmsg} );
		return 0;		
	}
}

## subs for creation of stats presentation

sub createBarPresentation {
	my ( $self, $stats, $title, $barType, $xAxisFontAngle ) = @_;

	my ( $subTitle, $return, $statInfo );
	
	if ( $self->{statInfo} ) {
		$statInfo = $self->{statInfo};
		$subTitle = $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{start};
		$subTitle .= ' ' . $statInfo->{startYear} if ( exists $statInfo->{startYear} );
		$subTitle .= ' - ';
		$subTitle .= $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{end};
		$subTitle .= ' ' . $statInfo->{endYear} if ( exists $statInfo->{startYear} );
		
		$title .= ' / ' . $statInfo->{type} if ( exists( $statInfo->{type} ) );
		$title .= "\n <* size=10, font=arial.ttf *> ( $subTitle )";
	}

	for ( $barType ) {
		if (/^stackedMultiBar$/) {
			if ( !$self->createStackedMultiBarChart( $stats, { title => decode_entities( $title ) }, $xAxisFontAngle ) ) {
				$return->{error} = $self->{errmsg};
			} else {
				$return->{statImageName} = $self->{statImageName};
				$return->{type} = 'bar';
			}
		}	elsif (/^multiBar$/) {
			if ( !$self->createMultiBarChart( $stats, { title => decode_entities( $title ) }, $xAxisFontAngle ) ) {
				$return->{error} = $self->{errmsg};
			} else {
				$return->{statImageName} = $self->{statImageName};
				$return->{type} = 'bar';
			}
		}	elsif (/^percentageBar$/) {
			if ( !$self->createPercentageBarChart( $stats, { title => decode_entities( $title ) }, $xAxisFontAngle ) ) {
				$return->{error} = $self->{errmsg};
			} else {
				$return->{statImageName} = $self->{statImageName};
				$return->{type} = 'bar';
			}
		} else {
			if ( !$self->createBarChart( $stats, { title => decode_entities( $title ) }, $xAxisFontAngle ) ) {
				$return->{error} = $self->{errmsg};
			} else {
				$return->{statImageName} = $self->{statImageName};
				$return->{type} = 'bar';
			}
		}
	}

	$return->{json} = to_json( { 
																stats 				 => $stats, 
																title 				 => $title, 
																barType 			 => $barType, 
																xAxisFontAngle => $xAxisFontAngle, 
																jsonHashOrder  => $self->getHashOrder( $stats ) 
														} );

	return $return;	
}

sub createMultiBarChart {
	my ( $self, $stats, $titleSettings, $xAxisFontAngle ) = @_;
	undef $self->{errmsg};

	my $testRun = 0;
	
	my $legendBoxHeight = 0;
	
	until ( $testRun == 2 ) {
		$testRun++;
		
		my @colors = ( 0xFF0000, 0x00FFFF, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FF00, 0xFFA200, 0x9300FF, 0x008CFF, 0x066F00, 0x6F3C00 );
		
		my @labels =  keys %{ ( values %$stats )[0] };
	
		my $angle = ( $xAxisFontAngle ) ? $self->{xAxisFontAngleAlternative} : 0;
	
		my $c = XYChart->new( $self->{statImageWidth}, $self->{statImageHeight} + $legendBoxHeight );
	
		$c->setPlotArea( 75 , 40 + $legendBoxHeight, 620, 400 );
		$c->xAxis()->setTickOffset( 0.5 );
		$c->xAxis()->setLabels( \@labels )->setFontAngle( $angle );
		
		$c->yAxis()->setTitle( $titleSettings->{yAxisTitle} ) if ( exists $titleSettings->{yAxisTitle} );
		$c->xAxis()->setTitle( $titleSettings->{xAxisTitle} ) if ( exists $titleSettings->{xAxisTitle} );
		
		$c->addTitle( $titleSettings->{title} ) if ( exists $titleSettings->{title} );
		
		my $legendBox = $c->addLegend( 50, 40, 0, "", 10 );
		$legendBox->setBackground( $perlchartdir::Transparent );
		
		my $layer = $c->addBarLayer2( $perlchartdir::Side, 6 );

		$layer->setBorderColor(
														$perlchartdir::Transparent, 
														perlchartdir::softLighting( $perlchartdir::Top )
													);
		
		foreach my $bar ( keys %$stats ) {
			my @data = values %{ $stats->{ $bar } };
			my $color = shift @colors;
	
			$layer->addDataSet( \@data, $color, decode_entities( $bar ) );
#			$layer->setBorderColor( $perlchartdir::Transparent );
		}
		
		if ( $testRun == 1 ) {
			my $test;
			eval{ $test = $c->makeChart2( 0 ) };
			$legendBoxHeight = $legendBox->getHeight() + 10;
			
			if ( !$test ) {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;				
			}
			
		} else {
			my $imgName = 'chart' . nowstring(2) . '.png';
			my $test;
			eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
		
			if ( $test ) {
				$self->{statImageName} = $imgName;
				return 1;
			} else {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;
			}
		}
	}
}

sub createStackedMultiBarChart {
	my ( $self, $stats, $titleSettings, $xAxisFontAngle ) = @_;
	undef $self->{errmsg};

	my $testRun = 0;
	my $legendBoxHeight = 0;

	my $labels = delete $stats->{labels};
	
	until ( $testRun == 2 ) {
		$testRun++;
		
		my @colors = ( 
									 0xFF0000, 0x00FFFF, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FF00, 0xFFA200, 0x9300FF, 0x066F00, 
									 0xFF8F8F, 0xAFFFFF, 0xFEFFAF, 0x9FA0FF, 0xFF9FFF, 0xAFFFAF, 0xFFDC9F, 0xE4BFFF, 0x85AF83	
								 );
		
		my $angle = ( $xAxisFontAngle ) ? $self->{xAxisFontAngleAlternative} : 0;
		
		my $c = XYChart->new( $self->{statImageWidth}, $self->{statImageHeight} + $legendBoxHeight );
	
		$c->setPlotArea( 75 , 40 + $legendBoxHeight, 620, 400 );
		$c->xAxis()->setTickOffset( 0.5 );
		$c->xAxis()->setLabels( $labels )->setFontAngle( $angle );
		
		$c->yAxis()->setTitle( $titleSettings->{yAxisTitle} ) if ( exists $titleSettings->{yAxisTitle} );
		$c->xAxis()->setTitle( $titleSettings->{xAxisTitle} ) if ( exists $titleSettings->{xAxisTitle} );
		
		$c->addTitle( $titleSettings->{title} ) if ( exists $titleSettings->{title} );
		
		my $legendBox = $c->addLegend2( 50, 40, 3, "arial.ttf", 8 );

		$legendBox->setText("{dataSetName}, version {dataGroupName}");
	
		my $layer = $c->addBarLayer2( $perlchartdir::Stack, 6 );
		
		$layer->setDataLabelStyle();
		$layer->setAggregateLabelStyle();
		
		foreach my $version ( keys %$stats ) {
	
			$layer->addDataGroup( $version );
			
			foreach my $category ( keys %{ $stats->{$version} } ) {
				
				my $data = $stats->{$version}->{$category};
	
				my $color = shift @colors;
				
				$layer->addDataSet( $data, $color, decode_entities( $category ) );
				
				$layer->setBorderColor( $perlchartdir::Transparent );
			}
		}

		if ( $testRun == 1 ) {
			my $test;
			eval{ $test = $c->makeChart2( 0 ) };
			$legendBoxHeight = $legendBox->getHeight() + 10;
			
			if ( !$test ) {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;				
			}
		} else {
		
			my $imgName = 'chart' . nowstring(2) . '.png';
			my $test;
			
			eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
			
			if ( $test ) {
				$self->{statImageName} = $imgName;
				$stats->{labels} = $labels;
				
				return 1;
			} else {
				$self->{errmsg} = "Error: cannot create stacked multibar chart.";
				return 0;
			}
		}
	}
}

sub createPercentageBarChart {
	my ( $self, $stats, $titleSettings, $xAxisFontAngle ) = @_;
	undef $self->{errmsg};

	my $testRun = 0;
	my $legendBoxHeight = 0;

	my $labels = delete $stats->{labels};
	
	until ( $testRun == 2 ) {
		$testRun++;
		
		my @colors = ( 
									 0xFF0000, 0x00FFFF, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FF00, 0xFFA200, 0x9300FF, 0x066F00, 
									 0xFF8F8F, 0xAFFFFF, 0xFEFFAF, 0x9FA0FF, 0xFF9FFF, 0xAFFFAF, 0xFFDC9F, 0xE4BFFF, 0x85AF83	
								 );
		
		my $angle = ( $xAxisFontAngle ) ? $self->{xAxisFontAngleAlternative} : 0;
		
		my $c = XYChart->new( $self->{statImageWidth}, $self->{statImageHeight} + $legendBoxHeight );
	
		$c->setPlotArea( 75 , 40 + $legendBoxHeight, 620, 400 );
		$c->xAxis()->setTickOffset( 0.5 );
		$c->xAxis()->setLabels( $labels )->setFontAngle( $angle );
		
		$c->yAxis()->setTitle( $titleSettings->{yAxisTitle} ) if ( exists $titleSettings->{yAxisTitle} );
		$c->xAxis()->setTitle( $titleSettings->{xAxisTitle} ) if ( exists $titleSettings->{xAxisTitle} );
		
		$c->addTitle( $titleSettings->{title} ) if ( exists $titleSettings->{title} );
		
		my $legendBox = $c->addLegend( 50, 40, 0, "", 10 );
		$legendBox->setBackground( $perlchartdir::Transparent );

#		$legendBox->setText("{dataSetName}, version {dataGroupName}");
	
		my $layer = $c->addBarLayer2( $perlchartdir::Percentage, 6 );
		
		$layer->setDataLabelStyle()->setAlignment($perlchartdir::Center);

		$layer->setBorderColor(
														$perlchartdir::Transparent, 
														perlchartdir::softLighting( $perlchartdir::Top )
													);		
		
		foreach my $dataSetName ( keys %$stats ) {
			
			my $data = $stats->{$dataSetName};

			my $color = shift @colors;
			
			$layer->addDataSet( $data, $color, decode_entities( $dataSetName ) );
		}

		if ( $testRun == 1 ) {
			my $test;
			eval{ $test = $c->makeChart2( 0 ) };
			$legendBoxHeight = $legendBox->getHeight() + 10;
			
			if ( !$test ) {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;				
			}
		} else {
		
			my $imgName = 'chart' . nowstring(2) . '.png';
			my $test;
			
			eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
			
			if ( $test ) {
				$self->{statImageName} = $imgName;
				$stats->{labels} = $labels;
				
				return 1;
			} else {
				$self->{errmsg} = "Error: cannot create stacked multibar chart.";
				return 0;
			}
		}
	}	
}

sub createBarChart {
	my ( $self, $stats, $titleSettings, $xAxisFontAngle ) = @_;
	undef $self->{errmsg};

	my $testRun = 0;
	my $legendBoxHeight = 0;
	
	until ( $testRun == 2 ) {
		$testRun++;

		my @labels =  keys %$stats;
		my @data = values %$stats;
		
		my $c = XYChart->new( $self->{statImageWidth}, $self->{statImageHeight} + $legendBoxHeight );
	
		my $angle = ( $xAxisFontAngle ) ? $self->{xAxisFontAngleAlternative} : 0;
		
		$c->setPlotArea( 75 , 40 + $legendBoxHeight, 620, 400 );
		$c->xAxis()->setTickOffset( 0.5 );
		$c->xAxis()->setLabels( \@labels )->setFontAngle( $angle );
		
		$c->yAxis()->setTitle( $titleSettings->{yAxisTitle} ) if ( exists $titleSettings->{yAxisTitle} );
		$c->xAxis()->setTitle( $titleSettings->{xAxisTitle} ) if ( exists $titleSettings->{xAxisTitle} );
		
		$c->addTitle( $titleSettings->{title} ) if ( exists $titleSettings->{title} );
		my $legendBox = $c->addLegend( 55, 20, 0, "", 10 );
		
		$legendBox->setBackground( $perlchartdir::Transparent );
		
		my $layer = $c->addBarLayer( \@data, -1, "", 6 );

		$layer->setBorderColor(
														$perlchartdir::Transparent, 
														perlchartdir::softLighting( $perlchartdir::Top )
													);	
	
#		$layer->setBorderColor($perlchartdir::Transparent );

		if ( $testRun == 1 ) {
			my $test;
			eval{ $test = $c->makeChart2( 0 ) };
			$legendBoxHeight = $legendBox->getHeight() + 10;
			
			if ( !$test ) {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;				
			}
		} else {		
			my $imgName = 'chart' . nowstring(2) . '.png';
			my $test;
			eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
			if ( $test ) {
				$self->{statImageName} = $imgName;
				return 1;
			} else {
				$self->{errmsg} = "Error: cannot create bar chart.";
				return 0;
			}
		}
	}	
}

sub createPieChart {
	my ( $self, $stats, $title ) = @_;
	my ( $subTitle, $return, $statInfo );

	undef $self->{errmsg};	

	if ( $self->{statInfo} ) {
		$statInfo = $self->{statInfo};
		$subTitle = $statInfo->{start} . ' - ' . $statInfo->{end};
	
		$title .= "\n <* size=10, font=arial.ttf *> ( $subTitle )";
	}

	my $labels = decode_entities_deep [keys %$stats];
	my @data = values %$stats;
	
	my $c = PieChart->new( $self->{statImageWidth}, $self->{statImageHeight} );
	
	$c->setPieSize( 340, 210, $self->{pieChartRadius} );
	
	$c->setLabelLayout( $perlchartdir::SideLayout );
	
	$c->setData( \@data, $labels );
	$c->set3D( 20 );
	$c->setStartAngle( $self->{pieChartRotateAngle} + 135 );
	
	$c->addTitle( decode_entities( $title ) ) if ( $title );	
	
	my $t = $c->setLabelStyle( "", 10 );
	$t->setBackground( $perlchartdir::SameAsMainColor, $perlchartdir::Transparent, perlchartdir::glassEffect() );
	$t->setRoundedCorners( 5 );	
	
	my $imgName = 'chart' . nowstring(2) . '.png';
	my $test;

	eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
	if ( $test ) {
		$return->{statImageName} = $imgName;
		$return->{type} = 'pie';

		$return->{json} = to_json( { 
																	stats => $stats, 
																	title => $title, 
																	jsonHashOrder => $self->getHashOrder( $stats )
														 } );
	} else {
		$return->{error} = "Error: cannot create pie chart.";
	}
	return $return;
}

sub createMultiLineChart {
	my ( $self, $stats, $title, $xAxisFontAngle ) = @_;
	undef $self->{errmsg};
	my ( $subTitle, $statInfo, $return );

	my $testRun = 0;
	my $legendBoxHeight = 0;

	if ( $self->{statInfo} ) {
		$statInfo = $self->{statInfo};
		$subTitle = $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{start};
		$subTitle .= ' ' . $statInfo->{startYear} if ( exists $statInfo->{startYear} );
		$subTitle .= ' - ';
		$subTitle .= $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{end};
		$subTitle .= ' ' . $statInfo->{endYear} if ( exists $statInfo->{startYear} );
		
		$title .= ' / ' . $statInfo->{type} if ( exists( $statInfo->{type} ) );
		$title .= "\n <* size=10, font=arial.ttf *> ( $subTitle )";
	}

	my $labels = delete( $stats->{labels} );	

	until ( $testRun == 2 ) {
		$testRun++;
		
		my @colors = ( 
									 0xFF0000, 0x00FFFF, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FF00, 0xFFA200, 0x9300FF, 0x066F00, 
									 0xFF8F8F, 0xAFFFFF, 0xFEFFAF, 0x9FA0FF, 0xFF9FFF, 0xAFFFAF, 0xFFDC9F, 0xE4BFFF, 0x85AF83	
								 );
		
		my $angle = ( $xAxisFontAngle ) ? $self->{xAxisFontAngleAlternative} : 0;
		
		my $c = XYChart->new( $self->{statImageWidth}, $self->{statImageHeight} + $legendBoxHeight );
	
		$c->setPlotArea( 75 , 40 + $legendBoxHeight, 620, 400 );

		$c->xAxis()->setLabels( $labels )->setFontAngle( $angle );
		
		$c->addTitle( decode_entities( $title ) ) if ( $title );
		
		my $legendBox = $c->addLegend( 50, 40, 0, "", 10 );
		$legendBox->setBackground( $perlchartdir::Transparent );
		
		my $layer = $c->addLineLayer2();
		
		$layer->setLineWidth(2);
		
		foreach my $line ( keys %$stats ) {
			$line = decode_entities( $line );
			
			my $data = $stats->{$line};

			my $color = shift @colors;
			
			$layer->addDataSet( $data, $color, $line );
		}

		if ( $testRun == 1 ) {
			my $test;
			eval{ $test = $c->makeChart2( 0 ) };
			$legendBoxHeight = $legendBox->getHeight() + 10;

			if ( !$test ) {
				$self->{errmsg} = "Error: cannot create multi bar chart.";
				return 0;				
			}
		} else {
		
			my $imgName = 'chart' . nowstring(2) . '.png';
			my $test;
			
			eval{ $test = $c->makeChart( $self->{statImageDir} . $imgName ) };
			
			if ( $test ) {
				$return->{statImageName} = $imgName;
				
				$stats->{labels} = $labels;
				
				$return->{type} = 'line';
			} else {
				$return->{error} = "Error: cannot create stacked multibar chart.";
			}
		}
	}
	
	$return->{json} = to_json( { 
																stats => $stats, 
																title => $title,
																xAxisFontAngle => $xAxisFontAngle, 
																jsonHashOrder => $self->getHashOrder( $stats )
													 } );	
	
	return $return;
}

sub createTextOutput {
	my ( $self, $stats, $title, $showTotalColumnXAxis, $showTotalColumnYAxis ) = @_;
	my ( $return, $subTitle, $statInfo );
	my $text = "";
	
	if ( $self->{statInfo} ) {
		$statInfo = $self->{statInfo};
		
		$subTitle = $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{start};
		$subTitle .= ' ' . $statInfo->{startYear} if ( exists $statInfo->{startYear} );
		$subTitle .= ' - ';
		$subTitle .= $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{end};
		$subTitle .= ' ' . $statInfo->{endYear} if ( exists $statInfo->{startYear} );
		
		$title .= ' / ' . $statInfo->{type} if ( exists( $statInfo->{type} ) );
		
		$title .= "\n( $subTitle )";
	}	
	
	$stats = addTotalColumns( $stats, $showTotalColumnXAxis, $showTotalColumnYAxis ) if ( $showTotalColumnXAxis || $showTotalColumnYAxis );
	
	my @labels =  keys %{ ( values %$stats )[0] };
	my @categories = keys %$stats;
	
	############ calc column width ###############
	
	my @columnWidths;
	
	foreach my $label ( @labels ) {
		$columnWidths[0] = length( $label ) if ( $columnWidths[0] <= length( decode_entities( $label ) ) );
	}
	
	my $i = 1;
	foreach my $category ( @categories ) {
		$columnWidths[$i] = length decode_entities( $category );
		
		foreach my $label ( @labels ) {
			$columnWidths[$i] = length $stats->{$category}->{$label} if ( $columnWidths[$i] < length $stats->{$category}->{$label} );
		}
		$i++;
	}
	
	############
	
	my $border = '+';
	foreach my $columnWidth ( @columnWidths ) {
		$border .= calcDashedLine( $columnWidth + 2 );
	}
	
	$text.= $title . "\n" if ( $title );
	
	$text .= $border . "\n"; 
	$text .= '| ' . calcSpaces( '', $columnWidths[0] ) . ' | ';
	$i = 1;
	foreach my $category ( @categories ) {
		$text .= calcSpaces( $category, $columnWidths[$i] ) . $category . ' | ';
		$i++;
	}
	
	$text .= "\n" . $border . "\n";
	
	foreach my $label ( @labels ) {
		$text .= '| ' . $label . calcSpaces( $label, $columnWidths[0] ) .  ' | ';
		$i = 1;
		foreach my $category ( @categories ) {
			my $val = $stats->{$category}->{$label};
			$text .= calcSpaces( $val, $columnWidths[$i] ) . $val . ' | ';
			$i++;
		}
		
		$text .= "\n" . $border . "\n";
	}
	
	$return->{lineWidth} = length( $border );
	$text =~ s/ $//gm;
	
	$return->{text} = decode_entities( $text );
	$return->{lineCount} = @{ scalar( [ split( "\n", $text ) ] ) } + 1 ;	
	
	$return->{type} = 'text';

	return $return;
}

sub createTextOutputAdvisoriesByClassification {
	my ( $self, $stats, $title ) = @_;
	my ( $return, $subTitle, $statInfo );
	my $text = "";
	
	if ( $self->{statInfo} ) {
		$statInfo = $self->{statInfo};
		
		$subTitle = $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{start};
		$subTitle .= ' ' . $statInfo->{startYear} if ( exists $statInfo->{startYear} );
		$subTitle .= ' - ';
		$subTitle .= $statInfo->{type} . ' ' if ( $statInfo->{type} eq 'week' );
		$subTitle .= $statInfo->{end};
		$subTitle .= ' ' . $statInfo->{endYear} if ( exists $statInfo->{startYear} );
		
		$title .= ' / ' . $statInfo->{type} if ( exists( $statInfo->{type} ) );
		
		$title .= "\n( $subTitle )";
	}	
	
	my @clusters =  keys %{ ( values %$stats )[0] };
	my @classifications = keys %{ ( values %{ ( values %$stats )[0] } )[0] };
	my @versions =  keys %$stats;

	############ calc column width ###############
	
	my @columnWidths;
	
	foreach my $cluster ( @clusters ) {
		$columnWidths[0] = length( $cluster ) if ( $columnWidths[0] <= length( decode_entities( $cluster ) ) );
	}
	
	my $i = 1;
	foreach my $version ( @versions ) {
		foreach my $classification ( @classifications ) {
			$columnWidths[$i] = length $classification;
			
			foreach my $cluster ( @clusters ) {
				$columnWidths[$i] = length $stats->{$version}->{$cluster}->{$classification} 
					if ( $columnWidths[$i] < length $stats->{$version}->{$cluster}->{$classification} );
			}
			$i++;
		}
	}
		
	############
	
	my $border = '+';
	foreach my $columnWidth ( @columnWidths ) {
		$border .= calcDashedLine( $columnWidth + 2 );
	}
	
	$text.= $title . "\n" if ( $title );
	
	$text .= $border . "\n"; 
	$i = 1;

	my $versionsText = '| ' . calcSpaces( '', $columnWidths[0] ) . ' | ';
	my $classificationsText = '| ' . calcSpaces( '', $columnWidths[0] ) . ' | ';

	foreach my $version ( @versions ) {
		my $versionsColumnLength = 0;
		
		foreach my $classification ( @classifications ) {
			$classificationsText .= calcSpaces( $classification, $columnWidths[$i] ) . $classification . ' | ';
			$versionsColumnLength += $columnWidths[$i] + 3;
			$i++;
		}
		$versionsColumnLength -= 3; 
		$versionsText .= $version . calcSpaces( $version, $versionsColumnLength ) . ' | ';
	}
	
	$text.= $versionsText . "\n" . $border . "\n" . $classificationsText . "\n" . $border . "\n";
	
	foreach my $cluster ( @clusters ) {
		$text .= '| ' . $cluster . calcSpaces( $cluster, $columnWidths[0] ) .  ' | ';
		$i = 1;
		foreach my $version ( @versions ) {
			foreach my $classification ( @classifications ) {
				my $val = $stats->{$version}->{$cluster}->{$classification};
				$text .= calcSpaces( $val, $columnWidths[$i] ) . $val . ' | ';
				$i++;
			}
		}		
		$text .= "\n" . $border . "\n";
	}
	
	$return->{lineWidth} = length( $border );
	$text =~ s/ $//gm;
	
	$return->{text} = decode_entities( $text );
	$return->{lineCount} = @{ scalar( [ split( "\n", $text ) ] ) } + 1 ;	
	
	$return->{type} = 'text';

	return $return;
}

## subs supporting the subs for creation of stats presentation
sub calcSpaces {
	my ( $string, $maxLength) = @_;
	
	my $spaceLength = $maxLength - length( $string ); 
	
	my $space = "";
	if ( $spaceLength > 0 ) {
		for( my $i = 0; $i < $spaceLength; $i++ ) {
			$space .= " ";
		}
	}
	return $space;
}

sub calcDashedLine {
	my ( $length ) = @_;
	my $line = "";
	
	for( my $i = 0; $i < $length; $i++ ) {
		$line .= "-";
	}
	$line .= '+';
	
	return $line;
}

sub addTotalColumns {
	my ( $stats, $totalColumnXAxis, $totalColumnYAxis ) = @_;
	
	if ( $totalColumnXAxis ) {
		my $totalColumnX;
	
		foreach my $category ( keys %$stats ) {
			$totalColumnX = 0;
			foreach my $label ( keys %{ ( values %$stats )[0] } ) {
				$totalColumnX += ( $stats->{$category}->{$label} ) ? $stats->{$category}->{$label} : 0;
			}
			$stats->{$category}->{Total} = $totalColumnX;
		}	
	}
	
	if ( $totalColumnYAxis ) {		
		my %totalColumnY;
		foreach my $label ( keys %{ ( values %$stats )[0] } ) {
			$totalColumnY{$label} = 0;
			foreach my $category ( keys %$stats ) {
				$totalColumnY{$label} += $stats->{$category}->{$label};
			}
		}
	
		$stats->{Total} = \%totalColumnY;
	}
		
	return $stats;
}

sub deletePreviousStatImages {
	my ( $self ) = @_;
	undef $self->{errmsg};
	
	my $dir = $self->{statImageDir};
	my $dh;
	opendir( $dh, $dir ) or $self->{errmsg} = "cannot open dir";
	
	my @files = readdir( $dh );
	
	chdir( $dir );
		
	foreach my $file ( @files ) {
		if ( $file =~ /(.*?\.png)$/ ) {
			$file = $1;
			if ( !unlink( $file ) ) {
				$self->{errmsg} = "Error: cannot delete previous statistics image.";
				return 0;
			} 
		} 
	}
	
	return 1;
}

sub getHashOrder {
	my ( $self, $input ) = @_;
	my @order;

	foreach my $key ( keys %$input ) {
		if ( ref( $input->{ $key } ) ne 'HASH' || ref( $input->{ $key } ) eq 'ARRAY' ) {					
			push @order, $key;
		} else {
			push @order, { $key => $self->getHashOrder( $input->{ $key } ) };
		}
	}

	return \@order;
}

sub order_from_json {
	my ( $self, $data, $hashOrder ) = @_; 

	tie my %originalData, "Tie::IxHash";

	for ( my $i = 0; $i < @$hashOrder; $i++ ) {
		if ( ref( $hashOrder->[$i] ) ne 'HASH' ) {
			$originalData{ $hashOrder->[$i] } = $data->{ $hashOrder->[$i] };			
		} else {
			$originalData{ ( keys %{ $hashOrder->[$i] } )[0] } = 
					$self->order_from_json( 
																	$data->{ ( keys %{ $hashOrder->[$i] } )[0] }, 
																	values %{ $hashOrder->[$i] } 
															 );
		}
	}
	
	return \%originalData;
}

# expects a string as dd-mm-yyyy
sub checkDate {
	my ( $self, $dateString ) = @_;

	my ( $day, $month, $year ) = split( '-', $dateString );

	eval{ 
	    timelocal(0,0,0,$day, $month-1, $year);
	};

	return ( $@ ) ? 0 : 1;
}

sub splitDate {
	my ( $self, $dateString ) = @_;
	
	my ( $day, $month, $year ) = split( '-', $dateString );
	
	for ( $day, $month ) {
		$_ = '0' . $_ if ( $_ =~ /^\d$/ );
	}
	return $day, $month, $year;
}

=head1 NAME 

Taranis::Statistics

=head1 SYNOPSIS

  use Taranis::Statistics;

  my $obj = Taranis::Statistics->new( $oTaranisConfig );

  $obj->loadCollection( %where );

  $obj->setStatsTypeForUser( $statsType, $userID );

  $obj->getStatsCategories();

=head1 DESCRIPTION

Module for managing (downloaded) statistics images and generating statistics images from queries.
POD for this module is incomplete.  

=head1 METHODS
  
=head2 new( )
  
Constructor of the Taranis::Statistics module.

    my $obj = Taranis::Statistics->new( $oTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};
	  
Clears error message for the new object. Can be accessed by:
   
    $obj->{errmsg};	  

Returns the blessed object.	

=head2 loadCollection( %where )

Retrieves records from table C<statsimages>.

    $obj->loadCollection( category => 'bot statistics', digest => 'gf1YRd/V3Pg5eRUPYIfi/w' );

If successful returns an ARRAY reference. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
  
=head2 setStatsTypeForUser( $statsType, $userID )

Updates C<statstype> setting in user profile.

    $obj->setStatsTypeForUser( 'Bot statistics', 'johnd' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.
  
=head2 getStatsCategories()

Retrieves a list of unique categories from table C<statsimages>

    $obj->getStatsCategories();

Returns an ARRAY reference. Returns a list of categories. Sets $errmsg of this object to Taranis::Database->{db_error_msg} if database execution fails.

=cut

1;
