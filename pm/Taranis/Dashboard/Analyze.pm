# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Analyze;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		tpl => 'dashboard_analyze.tt',
		tpl_minified => 'dashboard_analyze_minified.tt'
	};
	return( bless( $self, $class ) );
}

sub numberOfPendingAnalyses {
	my ( $self ) = @_;
	my $stmnt = "SELECT COUNT(*) AS count FROM analysis WHERE status = 'pending';";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return $self->{dbh}->fetchRow()->{count};	
}

sub numberOfPendingAnalysesWithoutOwner {
	my ( $self ) = @_;
	my $stmnt = "SELECT COUNT(*) AS count FROM analysis WHERE status = 'pending' AND owned_by IS NULL;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return $self->{dbh}->fetchRow()->{count};
}

sub graphNumberOfPendingAnalysesPerHour {
	my ( $self ) = @_;
	
	my ( @graphDataPoints );
	
	# the * 1000 is needed because javascript timestamp is in miliseconds
	my $stmnt = "SELECT EXTRACT(EPOCH FROM timestamp) * 1000  AS timestamp_epoch, pending_count"
		. " FROM statistics_analyze"
		. " WHERE timestamp > NOW() - '2 days'::INTERVAL"
		. " ORDER BY timestamp DESC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->{dbh}->nextRecord() ) {
		my $record = $self->{dbh}->getRecord();
		push @graphDataPoints, [ int $record->{timestamp_epoch}, int $record->{pending_count}];
	}
	
	@graphDataPoints = reverse @graphDataPoints;
	
	my %graphSettings = ( 
		type => 'graph', 
		data => \@graphDataPoints, 
		name => 'graphNumberOfPendingAnalysesPerHour',
		yaxisname => 'pending analysis', 
		options => {
			xaxis => {
				mode => 'time',
				timezone => 'browser',
				timeformat => '%H:%M',
				minTickSize => [1, 'hour']
			},
			yaxis => { 
				minTickSize => 1,
				tickDecimals => 0,
				min => 0
			},
			series => {
				points => { show => 1 }, 
				lines => { show => 1 }
			},
			grid => { hoverable => 1 }
		} 
	);
	return \%graphSettings;	
}

# should always return TRUE or FALSE 
sub countNumberOfPendingAnalysesPerHour {
	my ( $self ) = @_;
	
	my $stmnt = "SELECT MAX(timestamp) AS last_count FROM statistics_analyze WHERE timestamp > NOW() - '1 hour'::INTERVAL;";
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	if ( !$self->{dbh}->fetchRow()->{last_count} ) {
		
		my $stmnt = "SELECT to_char( NOW(), 'YYYYMMDD HH24:00' ) AS datetime_hour;";
		$self->{dbh}->prepare( $stmnt );
		$self->{dbh}->executeWithBinds();
		my $datetimeHour = $self->{dbh}->fetchRow()->{datetime_hour};
		
		my $pendingCount = $self->numberOfPendingAnalyses();
		
		my ( $addCountStmnt, @bind ) = $self->{sql}->insert( "statistics_analyze", { pending_count => $pendingCount, timestamp =>  $datetimeHour } );
		$self->{dbh}->prepare( $addCountStmnt );
		
		if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
			return 1;
		} else {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			print $self->{errmsg};
			return 0;
		}
	} else {
		return 1;
	}
}

1;

=head1 NAME

Taranis::Dashboard::Analyze

=head1 SYNOPSIS

  use Taranis::Dashboard::Analyze;

  my $obj = Taranis::Dashboard::Analyze->new( $oTaranisConfig );

  $obj->numberOfPendingAnalyses();

  $obj->numberOfPendingAnalysesWithoutOwner();

  $obj->graphNumberOfPendingAnalysesPerHour();

  $obj->countNumberOfPendingAnalysesPerHour();

=head1 DESCRIPTION

Controls the content of the Analyze section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Analyze> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Analyze->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the template of the Analyze section of the dashboard:

    $obj->{tpl}

Sets the template of the Analyze section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 numberOfPendingAnalyses()

Retrieves the number of analyses with status C<pending>.

Returns a number.

=head2 numberOfPendingAnalysesWithoutOwner()

Retrieves the number of analyses with C<status> 'pending' and C<owned_by> set to NULL.

Returns a number.

=head2 graphNumberOfPendingAnalysesPerHour()

Creates a datastructure which can be used by jQuery plugin 'Flot'. The resulting data represents a graph showing the number of analyses with C<status> 'pending' of the last 2 days.

Returns an HASH reference.

=head2 countNumberOfPendingAnalysesPerHour()

Inserts a new entry in table C<statistics_analyze> every hour. The entry is a count of analyses with C<status> 'pending'.

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
