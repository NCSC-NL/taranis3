# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Report::ContactLog;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use SQL::Abstract::More;
use strict;

my %CONTACTTYPEDICTIONARY = (
	1 => 'chat',
	2 => 'email',
	3 => 'phone',
	4 => 'other'
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

sub getContactLog {
	my ( $self, %where ) = @_;
	
	my $limit = ( exists( $where{limit} ) && $where{limit} =~ /^\d+$/ ) ? delete $where{limit} : undef; 

	my ( $stmnt, @binds ) = $self->{sql}->select( 'report_contact_log', '*', \%where, 'created DESC' );
	
	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	my @logs;
	while ( $self->{dbh}->nextRecord() ) {
		push @logs, $self->{dbh}->getRecord();
	}
	return \@logs;
}

sub addContactLog {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'report_contact_log', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setContactLog {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'report_contact_log', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteContactLog {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->deleteObject( 'report_contact_log', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub getContactTypeDictionary {
	return \%CONTACTTYPEDICTIONARY;
}

1;

=head1 NAME

Taranis::Report::ContactLog

=head1 SYNOPSIS

  use Taranis::Report::ContactLog;

  my $obj = Taranis::Report::ContactLog->new( $oTaranisConfig );

  $obj->getContactLog( %where );

  $obj->addContactLog( %contactLog );

  $obj->setContactLog( %contactLog );

  $obj->deleteContactLog( %where );

  $obj->getContactTypeDictionary();

  Taranis::Report::ContactLog->getContactTypeDictionary();

=head1 DESCRIPTION

CRUD functionality for report contact log.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Report::ContactLog> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Report::ContactLog->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 getContactLog( %where )

Retrieves a list of contact log entries. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

id: number

=item *

type: number

=item *

contact_details: string

=item *

created: date

=item *

notes: string

=back

Also limit can be set to limit the number of results.

    $obj->getContactLog( id => 23 );

Returns an ARRAY reference.

=head2 addContactLog( %contactLog )

Adds a contact log.

    $obj->addContactLog( contact_details => 'tel: 0612345678', notes => 'got a call from...', type => 3 );

If successful returns the ID of the newly added log entry. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setContactLog( %ContactLog )

Updates a contact log entry. Key C<id> is mandatory.

    $obj->setContactLog( id => 3, notes => 'got a call from... and...' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteContactLog( %where )

Deletes a contact log entry.

    $obj->deleteContactLog( id => 6 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getContactTypeDictionary()

Returns %CONTACTTYPEDICTIONARY as hash reference.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setContactLog() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
