# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Report::ToDo;

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

sub getToDo {
	my ( $self, %where ) = @_;
	
	my $limit = ( exists( $where{limit} ) && $where{limit} =~ /^\d+$/ ) ? delete( $where{limit} ) : undef;
	my $orderBy = 'CASE WHEN done_status = 100 THEN 1 ELSE 0 END, due_date';
	my ( $stmnt, @binds ) = $self->{sql}->select( 'report_todo', '*', \%where, $orderBy );
	
	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );
	my @todos;
	while ( $self->{dbh}->nextRecord() ) {
		push @todos, $self->{dbh}->getRecord();
	}
	return \@todos;
}

sub addToDo {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};  
	
	if ( my $id = $self->{dbh}->addObject( 'report_todo', \%inserts, 1 ) ) {
		return $id;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setToDo {
	my ( $self, %settings ) = @_;
	undef $self->{errmsg};  
	
	if ( !exists( $settings{id} ) ) {
		$self->{errmsg} = 'Missing parameter!';
		return 0;
	}
	
	my $id = delete( $settings{id} );
	
	if ( $self->{dbh}->setObject( 'report_todo', { id => $id }, \%settings ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteToDo {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};  
	
	if ( $self->{dbh}->deleteObject( 'report_todo', \%where ) ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

1;

=head1 NAME

Taranis::Report::ToDo

=head1 SYNOPSIS

  use Taranis::Report::ToDo;

  my $obj = Taranis::Report::ToDo->new( $oTaranisConfig );

  $obj->getToDo( %where );

  $obj->addToDo( %toDo );

  $obj->setToDo( %toDo );

  $obj->deleteToDo( %where );

=head1 DESCRIPTION

CRUD functionality for report to-do.

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::Report::ToDo> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::Report::ToDo->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Returns the blessed object.

=head2 getToDo( %where )

Retrieves a list of to-dos. Filtering can be done by setting one or more key-value pairs. Filter keys are:

  id serial NOT NULL,
  due_date timestamp with time zone,
  description text,
  notes text,
  done_status integer DEFAULT 0,

=over

=item *

id: number

=item *

due_date: date

=item *

description: string

=item *

action: string

=item *

notes: string

=item *

done_status: number between 0 and 100

=back

Also limit can be set to limit the number of results.

    $obj->getToDo( id => 23 );

Returns an ARRAY reference.

=head2 addToDo( %ToDo )

Adds a to-do.

    $obj->addToDo( description => 'add perl doc to modules', due_date => 20141231, done_status => 75 );

If successful returns the ID of the newly added to-do. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>. 

=head2 setToDo( %ToDo )

Updates a to-do. Key C<id> is mandatory.

    $obj->setToDo( id => 3, done_status => 100 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 deleteToDo( %where )

Deletes a to-do.

    $obj->deleteToDo( id => 6 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setToDo() when C<id> is not set.
You should check C<id> setting. They cannot be 0 or undef!

=back

=cut
