# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::DB;
use base 'DBIx::Simple';

# This module is backported from T4, to simplify database access.  In T3,
# this will only get introduced where components will get re-tested: no
# global change!

use strict;
use warnings;

use DBIx::Simple  ();
use Scalar::Util  qw(weaken blessed);
use Carp          qw(croak);

use Taranis       qw(flat);
use Taranis::FunctionalWrapper qw(Sql);

=head1 NAME

Taranis::DB - database access via DBIx::Simple

=head1 INHERITANCE

 Taranis::DB
   isa DBIx::Simple

=head1 SYNOPSIS

 my $db    = Database->simple;
 my @objs  = $db->query($query, @binds)->hashes;

=head1 DESCRIPTION

This module wraps L<DBIx::Simple>, to facilitate other classes to access
the database.

=head1 METHODS

This object offers all methods from L<DBIx::Simple>.  Only extensions
and modifications are described in this page.

=head2 Constructors

=over 4

=item my $db = $class->new(%options);

Create a database access object.  See L<DBIx::Simple> for all methods
you can use.

=cut

sub new(@) {
	my $class = shift;
    my $args  = @_ == 1 ? shift : +{ @_ };

	my $self  = $class->SUPER::new($args->{dbh});
	$self->init($args);
}

sub init($) {
	my ($self, $args) = @_;

	$self->{TD_old} = $args->{old_style};
	weaken $self->{TD_old};

    # use SQL::Abstract::More, not the default SQL::Abstract.
	$self->{abstract} = Sql;

    $self;
}


=back

=head2 Transactions

Transactions are to be used for multiple database updates which depend
on each other.  When one fails, all earlier updates must be revoked.

Taranis v4 replaced the C<withTransaction()> function wuth a guard.  Read
for the advantages and usage below, in the L</DETAILS> section of this
manual page.

=over 4

=item my $guard = $db->beginWork;

You need to catch the result of this method in a scoped variable.  If
you forget to rollback or commit in the same scope.

=cut

# Like WithTransaction, but no need for to pass a code block.  Variables
# collected by the database are much nicer scoped.

my $guard;
sub beginWork() {
	my $self = shift;
	defined wantarray
		or croak "You have to use the result of beginWork as guard.";

	if($guard) {
		# already in a transaction
		return 'nested';
	}

	$self->SUPER::begin_work;
	my $give = $guard = Taranis::DB::Guard->new($self, [caller]);

	weaken $guard;
	$give;
}

{ no warnings;
  *begin = \&beginWork;
}
sub begin_work() { croak "use method beginWork" }


=item $db->commit($guard);

Commit the transaction.  There can only be one transaction active at
any moment (per process)

=cut

# The required $guard parameter is only to explicitly related the
# beginWork() and commit().  It makes clear why you need to catch the
# result of beginWork, so refactorers will not remove that variable.

sub commit($) {
	my ($self, $given) = @_;
	undef $_[1];
	return if $given eq 'nested';

	blessed $given && $given->isa('Taranis::DB::Guard')
		or croak "commit() requires a guard";

	$given->clear([caller]);
	$self->SUPER::commit;

	undef $guard;
}


=item $db->rollback($guard);

Cancel the database changes (the transaction).

=cut

sub rollback($) {
	my ($self, $guard) = @_;
	blessed $guard && $guard->isa('Taranis::DB::Guard')
		or croak "rollback() requires a guard";

	$guard->clear([caller]);
	$self->SUPER::rollback;
}


=item my $guard = $db->activeGuard();

Returns the Taranis::DB::Guard object of the outer transaction scope.

=cut

sub activeGuard() { $guard }


=back

=head2 Storing BLOBs

Binary Large Objects (BLOBs) are created in a special way in PSQL (other
databases treat them as a normal type)

Probably we even do not need them, because TEXT fields can be unlimited
in size as well.  Anyway: it is being used, so let's do it here.

=over 4

=item my ($oid, $size) = $db->addBlob($binary, %args);

Add a binary as large object to database.  Raw bytes should be passed with
the 'binary' option.  Returned are the C<oid> (database internat object
sequence number) and a C<size> (storage size).

=cut

sub addBlob($@) {
	# Avoid copying the binary
	my ($self, undef, %args) = @_;

	# lo_* can only be used within a transaction.
	my $guard    = $self->beginWork;

	my $dbh      = $self->dbh;
	my $oid      = $dbh->func($dbh->{pg_INV_WRITE}, 'lo_creat')
		or croak "Could not create large object (lo_creat)";

	my $lobj_fd  = $dbh->func($oid, $dbh->{pg_INV_WRITE}, 'lo_open' );
	my $size     = $dbh->func($lobj_fd, $_[1], length $_[1], 'lo_write');

	$self->commit($guard);
	wantarray ? ($oid, $size) : $oid;
}


=item my $blob = $db->getBlob($oid, $size, %args);

Retrieves a binary from database, returns the binary or undef;

=cut

sub getBlob($$%) {
	my ($self, $oid, $size, %args) = @_;

	defined $oid && defined $size
		or croak;

	my $guard   = $self->beginWork;

	my $dbh     = $self->dbh;
	my $lobj_fd = $dbh->func($oid, $dbh->{pg_INV_READ}, 'lo_open');

	my $blob    = '';
	$dbh->func($lobj_fd, $blob, $size, 'lo_read');

	$self->commit($guard);
	$blob;
}


=item $db->removeBlob($oid);

Remove a BLOB.

=cut

sub removeBlob($) {
	my ($self, $oid) = @_;

	my $guard    = $self->beginWork;
	$self->dbh->func($oid, 'lo_unlink');
	$self->commit($guard);
}

=back

=head1 Records

=over 4

=item my $h = $db->getRecord($table, $id, [$key]);

Returns the HASH from a C<$table>, for the unique key C<$id> in
column C<$key> (which defaults to C<id>).

=cut

sub getRecord($$$) {
	my ($self, $table, $id, $key) = @_;
	$key ||= 'id';
	$self->query("SELECT * FROM $table WHERE $key = ?", $id)->hash;
}


=item my $id = $db->addRecord($table, \%insert [, $key|undef]);

A bit smarter than L<insert()>: the C<%insert> data gets added to the
C<$table>.

The content of the C<$key> (by default the C<id> field) gets returned.
Some tables do not have an 'id' column.  In that (rather unusual case)
you need to explicitly pass 'undef' as key.

=cut

# Like ->insert(), but returns the id of the inserted record

sub addRecord($$;$) {
	my ($self, $table, $insert, $retfield) = @_;
	$retfield ||= 'id' unless @_==4;

	my %options;
	$options{returning} = $retfield if $retfield;

	(my $id) = $self->insert($table, $insert, \%options)->flat;
	$id;
}


=item $db->setRecord($table, $id, \%update, [$key]);

Change (update) the record.  Tables which do not have an C<id>
column cannot use this method.  Give a C<$key> fieldname when C<id>
is not the selector.

=cut

sub setRecord($$$;$) {
	my ($self, $table, $id, $update, $key) = @_;
	$key ||= 'id';
    $self->update($table, $update, {$key => $id});
}


=item $db->setOrAddRecord($table, \%insert, \@unique, [$key]);

When the record does not exist, create it via C<addRecord()>.  When it
already exists, then update it via C<setRecords()>.

The C<@unique> key (pass a scalar) or keys (pass an ARRAY) specify the
database columns which define what 'double' means.  The C<$key> defaults
to C<id>, and tells which field is returned on creation.

=cut

sub setOrAddRecord($$$;$) {
    my ($self, $table, $data, $unique, $key) = @_;
    $key ||= 'id';
    confess $data if exists $data->{$key};

    my %search = map +($_ => $data->{$_}), flat $unique;
    if((my $id) = $self->select($table, [$key], \%search)->flat) {
        $self->setRecord($table, $id, $data);
        return $id;
    }

    $self->addRecord($table, $data, $key);
}


=item $db->deleteRecord($table, $id, [$key]);

Remove a record from the C<$table>.  Tables which do not have an C<id>
column must specify the C<$key> (which defaults to C<id>.

Although possible, this method should not be used when there are
(possibly) multiple records with C<$key> in the C<$table>: the name of
this method does not suit that.

=cut

sub deleteRecord($$;$) {
	my ($self, $table, $id, $key) = @_;
	$key ||= 'id';
	$self->query("DELETE FROM $table WHERE $key = ?", $id);
}


=item my $val = $db->recordExists($table, \%where, [$key]);

Returns true if a record with a complex query exists.  If you specify a
C<$key> (often 'id') you will get that value returned.  Otherwise, true
is returned when the record is found.

=cut

sub recordExists($$$) {
	my ($self, $table, $where, $key) = @_;
	my $found = $self->select($table, $where);
	! $found ? undef : $key ? $found->{$key} : 1;
}


=item $db->isTrue($query, @binds);

Then the (complex) C<$query> (which usually starts with "SELECT 1 FROM ...")
produces a result, this will return a true value.

=cut

sub isTrue($@) {
	my $self = shift;
	!! $self->query(@_)->list;
}


=item my @names = $db->columnNames($table);

Returns a LIST of all column names in the C<$table>.  The collected
names are cached, hence fast.

=cut

sub columnNames($) {
	my ($self, $table) = @_;
	my $index = $self->{T_colnames};

	my $names = $index->{$table};
	unless($names) {
		my $r = $self->query("SELECT * FROM $table WHERE false LIMIT 0");
		$names = $index->{$table} = $r->attr('NAME');
	}
	@$names;
}

=back

=cut

##### Taranis::DB::Guard #####

package Taranis::DB::Guard;
# This class is used to detect situations where the commit or roleback
# is forgotten.

use Devel::GlobalDestruction qw(in_global_destruction);
use Carp qw(croak);

sub new($$) {
	my ($class, $db, $where) = @_;
	bless {db => $db, start_at => $where}, $class;
}

sub clear($) {
	my ($self, $where) = @_;
	delete $self->{start_at}
		or croak "DB transaction not active, ended in @$where";
	$self;
}

sub location() {
	my $start = shift->{start_at}
		or return "guard not active";
	"$start->[1] line $start->[2]";
}

sub DESTROY() {
	my $self  = shift;
	my $start = delete $self->{start_at}
		or return;

	my $loc   = "$start->[1] line $start->[2]";
	croak "transaction not complete in $loc";
	$self->{db}->rollback unless in_global_destruction;
}


=head1 DETAILS

=head2 Transactions

=head3 Changes in transactions since 3.4

Taranis before release 4 defined a C<withTransactions()> function, which
wrapped transactions in a code block: a pair of curly braces without
explicit C<sub> which is only achievable via function prototypes, not
with methods.

 use Taranis::Database 'withTransaction';
 withTransaction {    # old
   do_db_updates;
 };                   # <-- do not forget the ;

Taranis v4 moved to much stronger Object Orientation, therefore avoiding
the use of functions whenever possible.  It also uses exceptions (die)
on database queries (RaiseError) and functions.   This blunt error
handling replaces per-query error handling and C<errmsg> fields in
objects, delivering much smaller and simpler code.  Smaller and simpler
code contains fewer bugs.

So, Taranis v4 replaced the safeguard of C<withTransaction()> with an
other trick: use the automatic cleanup of variables to trigger automatic
rollback on unexpected situations.

There are a few benefits in the new implementation:

=over 4

=item .

No hidden C<eval()>, so errors will nicely pass to the eval which
knows how to handle the issue.

=item .

The database results within the transaction can be caught directly in
locally scoped variables, not in variables created outside the transaction
block.

=item .

The transaction very visibly works on the same database as the updates:
its not some weird globally available function anymore.

=back

=head3 Use of transactions

When two or more database updates need to either pass or fail together,
you need to wrap them in a I<transaction>.  The database does not know
which updates are related, so you have to be careful yourself.

This C<Taranis::DB> module is based on L<DBIx::Simple>, with a few
extensions.  In the case of using transactions, it requires you to catch
a special value on the start of the transaction, and show this again at
C<commit()> or C<rollback()>.

  my $db    = $::taranis->database;   # or $::db
  my $guard = $db->beginWork;
  $db->update(...);
  $db->insert(...);
  ...
  $db->commit($guard);

In most cases, you will not implement logic to handle the rollback
situation.  Errors (=die) which emerge between C<beginWork()> and
C<commit()> with automatically trigger a rollback.  Meanwhile, the
error will be passed on towards the closest wrapping eval.

=head3 Automatic rollback, the internal mechanism

When an error (die) is triggered between C<beginWork()> and C<commit()>,
some magic will perform a rollback.

Any C<die()> will get caught by some C<eval()>, up in the call stack.
While the C<die> is being processed, the perl interpreter cleans up
the intermediate variable scopes.  The C<$guard> (see previous example)
gets clean-up automatically as well.  But that's not a normal scalar:
it's an object with a trick.

When an object gets cleaned-up, Perl checks whether it has a DESTROY
method.  If it has one, Perl will first call it.  In this case we have
a C<Taranis::DB::Guard> object which provides a DESTROY which executes
a rollback if it hasn't seen a commit yet.  Fairly straight forward.

=cut

1;
