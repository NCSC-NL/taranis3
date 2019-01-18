# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Database;

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
		tpl => 'dashboard_database.tt',
		tpl_minified => 'dashboard_database_minified.tt'
	};
	return( bless( $self, $class ) );
}

sub numberOfLiveItems {
	my ( $self ) = @_;
	
	my $stmnt = "SELECT COUNT(*) AS count FROM item;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return $self->{dbh}->fetchRow()->{count};
}

# Returns an educated guess at the approximate(!) number of items in the archive.
sub numberOfArchivedItems {
	my ( $self ) = @_;
	
	# pg_class.reltuples gives us a rough guesstimate of the number of rows in table `item_archive` (see e.g.
	# https://wiki.postgresql.org/wiki/Slow_Counting).
	# Use this instead of COUNT(*) because COUNT(*) is a pretty heavy/slow operation in PostgreSQL.
	my $stmnt = "SELECT reltuples::numeric AS count FROM pg_class WHERE relname='item_archive';";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return Taranis::roundToSignificantDigits( $self->{dbh}->fetchRow()->{count}, 2 );
}

sub graphNumberOfLiveItems {
	my ( $self ) = @_;
	
	my ( @graphDataPoints );
	
	# the * 1000 is needed because javascript timestamp is in miliseconds
	my $stmnt = "SELECT EXTRACT(EPOCH FROM timestamp) * 1000  AS timestamp_epoch, items_count"
		. " FROM statistics_database"
		. " WHERE timestamp > NOW() - '1 month'::INTERVAL"
		. " ORDER BY timestamp DESC;";
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->{dbh}->nextRecord() ) {
		my $record = $self->{dbh}->getRecord();
		push @graphDataPoints, [ int $record->{timestamp_epoch}, int $record->{items_count}];
	}
	
	@graphDataPoints = reverse @graphDataPoints;
	
	my %graphSettings = ( 
		type => 'graph', 
		data => \@graphDataPoints, 
		name => 'graphNumberOfLiveItems',
		yaxisname => 'items',
		options => {
			xaxis => {
				mode => 'time',
				timezone => 'browser',
				timeformat => '<div class="center">%e %b</div>',
				monthNames => ["<br>Jan", "<br>Feb", "<br>Mar", "<br>Apr", "<br>May", "<br>Jun", "<br>Jul", "<br>Aug", "<br>Sep", "<br>Oct", "<br>Nov", "<br>Dec"]
			},
			yaxis => { 
				minTickSize => 1,
				tickFormatter => 'tickFormatterSuffix' 
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
sub countNumberOfLiveItems {
	my ( $self ) = @_;
	
	my $stmnt = "SELECT MAX(timestamp) AS last_count FROM statistics_database WHERE timestamp > NOW() - '1 day'::INTERVAL;";
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	if ( !$self->{dbh}->fetchRow()->{last_count} ) {
		my $itemsCount = $self->numberOfLiveItems();
		
		my ( $addCountStmnt, @bind ) = $self->{sql}->insert( "statistics_database", { items_count => $itemsCount } );
		$self->{dbh}->prepare( $addCountStmnt );
		
		if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
			return 1;
		} else {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		return 1;
	}
}

1;

=head1 NAME

Taranis::Dashboard::Database

=head1 SYNOPSIS

  use Taranis::Dashboard::Database;

  my $obj = Taranis::Dashboard::Database->new( $oTaranisConfig );

  $obj->numberOfLiveItems();

  $obj->numberOfArchivedItems();

  $obj->graphNumberOfLiveItems();

  $obj->countNumberOfLiveItems();
  
=head1 DESCRIPTION

Controls the content of the Database section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Dashboard::Database> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Dashboard::Database->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the template of the Database section of the dashboard:

    $obj->{tpl}

Sets the template of the Database section of the minified dashboard:

    $obj->{tpl_minified}

Returns the blessed object.

=head2 numberOfLiveItems()

Counts the number of records in table C<item>.  

Returns a number.

=head2 numberOfArchivedItems()

Counts the number of records in table C<item_archive>.  

Returns a number.

=head2 graphNumberOfLiveItems()

Creates a datastructure which can be used by jQuery plugin 'Flot'. The resulting data represents a graph showing the number of items in table C<item> per day over a period of one month.

Returns an HASH reference.

=head2 countNumberOfLiveItems()

Inserts a new entry in table C<statistics_database> every day. The entry is a count of the number of items in table C<item>.

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
