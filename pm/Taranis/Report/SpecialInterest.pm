# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Report::SpecialInterest;

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
	};
	return( bless( $self, $class ) );
}

sub getSpecialInterest {
	my ( $self, %where ) = @_;
	
	my $limit = ( exists( $where{limit} ) && $where{limit} =~ /^\d+$/ ) ? delete $where{limit} : undef;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( 'report_special_interest', '*', \%where, 'date_end DESC, date_start DESC' );
	
	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	my @specialInterests;
	while ( $self->{dbh}->nextRecord() ) {
		push @specialInterests, $self->{dbh}->getRecord();
	}
	return \@specialInterests;
}

sub addSpecialInterest {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'report_special_interest', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setSpecialInterest {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'report_special_interest', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteSpecialInterest {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->deleteObject( 'report_special_interest', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}


1;

=head1 NAME

Taranis::Report::SpecialInterest

=head1 SYNOPSIS

  use Taranis::Report::SpecialInterest;

  my $obj = Taranis::Report::SpecialInterest->new( $oTaranisConfig );

  $obj->getSpecialInterest( %where );

  $obj->addSpecialInterest( %specialInterest );

  $obj->setSpecialInterest( %specialInterest );

  $obj->deleteSpecialInterest( %where );

=head1 DESCRIPTION

CRUD functionality for report special interest.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Report::SpecialInterest> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Report::SpecialInterest->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 getSpecialInterest( %where )

Retrieves a list of special interests. Filtering can be done by setting one or more key-value pairs. Filter keys are:

=over

=item *

id: number

=item *

requestor: string

=item *

topic: string

=item *

action: string

=item *

date_start: date

=item *

date_end: date

=item *

timestamp_reminder_sent: date

=back

Also limit can be set to limit the number of results.

    $obj->getSpecialInterest( id => 23 );

Returns an ARRAY reference.

=head2 addSpecialInterest( %SpecialInterest )

Adds a spectial interest.

    $obj->addSpecialInterest( requestor => 'some_email_address@tarani3', topic => 'everything about Taranis', action => 'forward to everyone', date_start => 20141105, date_end => 20141119 );

If successful returns the ID of the newly added special interest. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setSpecialInterest( %SpecialInterest )

Updates a special interest. Key C<id> is mandatory.

    $obj->setSpecialInterest( id => 3, action => 'forward to almost everyone' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteSpecialInterest( %where )

Deletes a special interest.

    $obj->deleteSpecialInterest( id => 6 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setSpecialInterest() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
