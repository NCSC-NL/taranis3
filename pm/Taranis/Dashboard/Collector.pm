# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Collector;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Config;
use Taranis::Lock;

use SQL::Abstract::More;
use strict;
use Taranis qw(:util);

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		tpl => 'dashboard_collector.tt',
		tpl_minified => 'dashboard_collector_minified.tt'
	};
	return( bless( $self, $class ) );
}

sub collectorStatus {
	my ( $self ) = @_;
	Taranis::Lock->processIsRunning('collector');
}

sub lastSuccessfulRun {
	my ( $self ) = @_;
	
	my $stmnt = "SELECT to_char( MAX(finished), 'HH24:MI DD-MM-YYYY' ) AS last_successful_run FROM statistics_collector;";
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return $self->{dbh}->fetchRow()->{last_successful_run};
}

sub graphNumberOfErrorsPerRun {
	my ( $self ) = @_;
	
	my ( @collectorRuns, $previousRunStart, %graphs );
	
	# the * 1000 is needed because javascript timestamp is in miliseconds 
	my $stmnt = "SELECT EXTRACT(EPOCH FROM sc.started) * 1000  AS started_epoch, sc.started, sc.finished, c.description"
		. " FROM statistics_collector AS sc"
		. " JOIN collector AS c ON c.id = sc.collector_id"
		. " WHERE sc.started > NOW() - '1 day'::INTERVAL"
		. " ORDER BY sc.started DESC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->{dbh}->nextRecord() ) {
		my $run = $self->{dbh}->getRecord();
		
		if ( !$run->{finished} ) {
			$run->{finished} = $previousRunStart;
		}
		
		$previousRunStart = $run->{started};
		push @collectorRuns, $run;
	}

	my %where = ( time_of_error => {-between => ['000000 0000', '000000 0000'] } );
	my ( $preparedStmnt, @bind ) = $self->{sql}->select( 'errors', 'COUNT(*) AS error_count', \%where );
	$self->{dbh}->prepare( $preparedStmnt );

	foreach my $run ( @collectorRuns ) {
		next if ( !$run->{finished} );
		
		my @binds = ( $run->{started}, $run->{finished} );
		$self->{dbh}->executeWithBinds( @binds );
		
		my $count = $self->{dbh}->fetchRow()->{error_count};
		push @{ $graphs{ $run->{description} } }, [ int $run->{started_epoch}, int $count ];
	}
	
	my %graphSettings = ( 
		type => 'graph', 
		data => [], 
		name => 'graphNumberOfErrorsPerRun',
		yaxisname => 'errors', 
		options => {
			xaxis => {
				mode => 'time',
				timezone => 'browser',
				timeformat => '%H:%M'
			},
			yaxis => {
				minTickSize => 1,
				tickDecimals => 0
			},
			series => {
				points => { show => 1 } 
			},
			grid => { hoverable => 1 },
			legend => {
				show => 1,
				container => 'graphErrorPerRun-legend',
				noColumns => 0
			}			
		} 
	);
	
	my @colors = ( '#f86d79', '#f30c20', '#a20815', '#61050d', '#310206' );
	my @symbols = ('triangle', 'circle', 'square', 'diamond', 'cross');
	
	foreach my $graph ( keys %graphs ) {
		my $color = shift( @colors ) || '#0a400f';
		
		push @{ $graphSettings{data} }, {
			data => $graphs{$graph},
			label => $graph,
			points => { symbol => shift( @symbols ) || 'triangle' },
			color => $color,
			threshold => [
			{
				below => 1,
				color => "#0a400f"
			}]
		};
	}	
	
	
	return \%graphSettings;
}

sub graphDurationPerRun {
	my ( $self ) = @_;

	# the * 1000 is needed because javascript timestamp is in miliseconds 
	my $stmnt = "SELECT TO_CHAR(AGE(finished, started), 'MI.SS') AS run_duration, EXTRACT(EPOCH FROM started) * 1000  AS started_epoch, c.description" 
		. " FROM statistics_collector AS sc"
		. " JOIN collector AS c ON c.id = sc.collector_id"
		. " WHERE started > NOW() - '1 day'::INTERVAL"
		. " ORDER BY started DESC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	my %graphs;
	while ( $self->{dbh}->nextRecord() ) {
		my $run = $self->{dbh}->getRecord();
		
		if ( !$run->{run_duration} ) {
			$run->{run_duration} = 0;
		}
		
		push @{ $graphs{ $run->{description} } }, [ int $run->{started_epoch}, $run->{run_duration} ];
	}

	my %graphSettings = ( 
		type => 'graph',
		data => [], 
		name => 'graphDurationPerRun',
		yaxisname => 'minutes', 
		options => {
			xaxis => {
				mode => 'time',
				timezone => 'browser',
				timeformat => '%H:%M'
			},
			yaxis => { 
				minTickSize => 1,
				tickDecimals => 0 
			},
			series => {
				points => { show => 1 } 
			},
			grid => { hoverable => 1 },
			legend => {
				show => 1,
				container => 'graphDurationPerRun-legend',
				noColumns => 0
			}
		} 
	);

	my @colors = ( '#53e561', '#158a20', '#c9f7cd', '#70e97c', '#0a400f' );
	my @symbols = ('triangle', 'circle', 'square', 'diamond', 'cross');
	
	foreach my $graph ( keys %graphs ) {
		my $color = shift( @colors ) || '#0a400f';
		
		push @{ $graphSettings{data} }, {
			data => $graphs{$graph},
			label => $graph,
			points => { symbol => shift( @symbols ) || 'triangle' },
			color => $color,
			threshold => [
			{
				below => 0.01,
				color => "#f30c20"
			}, 
			{
				below => 15,
				color => $color
			},
			{
				below => 1000,
				color => '#fa7505'
			}]
		};
	}
	
	return \%graphSettings;
}

1;

=head1 NAME

Taranis::Dashboard::Collector

=head1 SYNOPSIS

  use Taranis::Dashboard::Collector;

  my $obj = Taranis::Dashboard::Collector->new( $oTaranisConfig );

  $obj->collectorStatus();

  $obj->graphDurationPerRun();

  $obj->graphNumberOfErrorsPerRun();

  $obj->lastSuccessfulRun();
  
=head1 DESCRIPTION

Controls the content of the Collector section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Collector> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Collector->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the template of the Collector section of the dashboard:

    $obj->{tpl}

Sets the template of the Collector section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 collectorStatus()

Checks whether the collector process is running.
Returns TRUE if collector process is running. Returns FALSE if it's not running.

=head2 graphDurationPerRun()

Creates a datastructure which can be used by jQuery plugin 'Flot'. The resulting data represents a graph showing how many minutes a collector has run.

Returns an HASH reference.

=head2 graphNumberOfErrorsPerRun()

Creates a datastructure which can be used by jQuery plugin 'Flot'. The resulting data represents a graph showing how many errors a collector produced during a run.

Returns an HASH reference.

=head2 lastSuccessfulRun()

Retrieves a timestamp of the last successful run of the collector.

Returns a formated timestamp: '12:00 01-01-2014' 

=cut
