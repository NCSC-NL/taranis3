# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Report::IncidentLog;

use strict;
use Taranis::Users;
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;

my %STATUSDICTIONARY = (
	1 => 'new',
	2 => 'open',
	3 => 'resolved',
	4 => 'rejected',
	5 => 'abandoned'
);

sub new {
	my ( $class, $config ) = @_;

	my $self = {
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub getIncidentLog {
	my ( $self, %where ) = @_;
	
	my $limit = ( exists( $where{limit} ) && $where{limit} =~ /^\d+$/ ) ? delete $where{limit} : undef;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'report_incident_log ril', 'ril.*, u.fullname', \%where, 'status, created DESC' );

	my %join = ( 'LEFT JOIN users u' => { 'u.username' => 'ril.owner' }	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	my @incidentLogs;
	while ( $self->{dbh}->nextRecord() ) {
		push @incidentLogs, $self->{dbh}->getRecord();
	}
	return \@incidentLogs;
}

sub addIncidentLog {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'report_incident_log', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setIncidentLog {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'report_incident_log', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteIncidentLog {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->deleteObject( 'report_incident_log', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getStatusDictionary {
	return \%STATUSDICTIONARY;
}

1;

=head1 NAME

Taranis::Report::IncidentLog

=head1 SYNOPSIS

  use Taranis::Report::IncidentLog;

  my $obj = Taranis::Report::IncidentLog->new( $oTaranisConfig );

  $obj->getIncidentLog( %where );

  $obj->addIncidentLog( %incidentLog );

  $obj->setIncidentLog( %incidentLog );

  $obj->deleteIncidentLog( %where );

  $obj->getStatusDictionary();

  Taranis::Report::IncidentLog->getStatusDictionary();

=head1 DESCRIPTION

CRUD functionality for report incident log.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Report::IncidentLog> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Report::IncidentLog->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 getIncidentLog( %where )

Retrieves a list of incident log entries. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

id: number

=item *

description: string

=item *

owner: string

=item *

ticket_number: string

=item *

created: date

=item *

status: number

=item *

constituent: string

=back

Also limit can be set to limit the number of results.

    $obj->getIncidentLog( id => 23 );

Returns an ARRAY reference.

=head2 addIncidentLog( %incidentLog )

Adds an incident log.

    $obj->addIncidentLog( description => 'some incident description', owner => 'some_user', ticket_number => '87389', status => 1 );

If successful returns the ID of the newly added log entry. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setIncidentLog( %incidentLog )

Updates an incident log entry. Key C<id> is mandatory.

    $obj->setIncidentLog( id => 3, status => 2 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteIncidentLog( %where )

Deletes an incident log entry.

    $obj->deleteIncidentLog( id => 6 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getStatusDictionary()

Returns %STATUSDICTIONARY as hash reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setIncidentLog() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
