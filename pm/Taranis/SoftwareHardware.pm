# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::SoftwareHardware;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Config;
use Taranis qw(:util);
use SQL::Abstract::More;
use XML::XPath;
use XML::XPath::XMLParser;
use strict;

sub new {
	my ( $class, $config ) = @_;
	
	my $cfg = ( $config ) ? $config : Taranis::Config->new();
	
	my $self = {
		cfg => $cfg,
		errmsg => undef,
		dbh => Database,
		sql => Sql,
	};
	return( bless( $self, $class ) );
}

sub addObject {
	my ( $self, %inserts ) = @_;
	undef $self->{errmsg};

	$inserts{deleted} 	= 0 if ( !exists( $inserts{deleted} ) );
	$inserts{monitored} = 0 if ( !exists( $inserts{monitored} ) );

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'software_hardware', \%inserts );
	$self->{dbh}->prepare( $stmnt );

	if ( defined( $self->{dbh}->executeWithBinds( @bind ) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteObject {
	my ( $self, %delete ) = @_;
	undef $self->{errmsg};
	
	my $table = ( $delete{table} ) ? delete( $delete{table} ) : 'software_hardware';
	
	my ( $stmnt, @bind ) = $self->{sql}->delete( $table, \%delete );
	
	$self->{dbh}->prepare( $stmnt );
	
	if ( $self->{dbh}->executeWithBinds( @bind) > 0 ) {
		return 1;
	} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		$self->{errmsg} = "Delete failed, corresponding id not found in database.";
		return 0;
	}
}

sub getDistinctList {
	my ($self, %where) = @_;
	my ( $stmnt, @bind ) = $self->{sql}->select( 'software_hardware', 'DISTINCT producer', \%where, 'producer' );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	$self->{errmsg} = $self->{dbh}->{sth}->errstr;

	my @softwareHardware;
	while ( my $array_ref = $self->{dbh}->{sth}->fetchrow_arrayref() ) {
		push @softwareHardware, @$array_ref;
	}
	return @softwareHardware;
}

sub getList {
	my ( $self, %where ) = @_;
	undef $self->{errmsg};

	my $offset = delete $where{offset};
	my $limit  = delete $where{limit};
	my $inUse  = delete $where{in_use};
	my $get_single_record = 0;

	if ( defined( $where{id} ) ) {
		# get_single_record to return only 1 record.
		$get_single_record = 1;
		$where{'sh.id'} = delete $where{id};
	}

	# Ignore empty search strings.
	if ( $where{producer} eq '' ) {
		delete $where{producer};
	}
	if ( $where{type} eq '' ) {
		delete $where{type};
	}
	
	if ( defined( $where{name} ) && $where{name} ) {
		my $search = delete $where{name};
		$where{"producer || ' ' || name"} = ( { -ilike => [ '%' . trim($search) . '%' ] } );
	} else {
		delete $where{name};
	}

	my $select = "sh.producer, sh.name, sh.version, sht.description, sh.id, sh.type, count(shu.soft_hard_id) AS in_use, sh.cpe_id, sh.monitored ";

	my ( $stmnt, @bind ) = $self->{sql}->select( "software_hardware AS sh", $select, {%where, deleted => 0} );

	my $join = {
		"JOIN soft_hard_type sht" => { "sh.type" => "sht.base" },
		"LEFT JOIN soft_hard_usage shu" => { "shu.soft_hard_id" => "sh.id" }
	 };
	$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );

	$stmnt .= " GROUP BY sh.producer, sh.name, sh.version, sht.description, sh.id, sh.type, sh.cpe_id, sh.monitored";
	$stmnt .= ' HAVING COUNT(shu.soft_hard_id) > 0 ' if ( $inUse );
	$stmnt .= " ORDER BY sh.producer, sh.name, sh.version";
	
	$stmnt .= defined( $limit ) ? ' LIMIT ' . $limit : '';
	$stmnt .= defined( $offset ) ? ' OFFSET ' . $offset  : '';

	$self->{dbh}->prepare( $stmnt );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		if ( $get_single_record ) {
			# want just a single_record
			# so process locally and return a hash;
			$self->{dbh}->executeWithBinds( @bind );
			$self->nextObject();
			return $self->getObject();
		}
		return $self->{dbh}->executeWithBinds( @bind );
	}
}

sub getListCount {
	my ($self, %where) = @_;

	# &getList may or may not return a value (depending on whether it thinks we want 1 or multiple rows), but either
	# way it'll use Database->executeWithBinds, so we can just run &getList and then look at Database->{sth}->rows.
	$self->getList(%where);
	return $self->{dbh}->{sth}->rows;
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}

sub setObject {
	my ( $self, %update ) = @_;
	undef $self->{errmsg};

	my %where;

	if ( $update{id} ) {
		$where{id} = delete $update{id};
	} elsif ( $update{cpe_id} ) {
		$where{cpe_id} = delete $update{cpe_id};
	} else {
		$self->{errmsg} = "No unique id given to identify record.";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->update( 'software_hardware', \%update, \%where );
	$self->{dbh}->prepare( $stmnt );

	$self->{dbh}->executeWithBinds( @bind );

	if ( defined( $self->{dbh}->{db_error_msg} ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		return 1;
	}
}

sub getBaseTypes {
	my ( $self ) = @_;
	undef $self->{errmsg};

	my $sql = 'SELECT description AS base_description, base AS base_char FROM soft_hard_type';

	$self->{dbh}->prepare( $sql );
	$self->{dbh}->executeWithBinds();

	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );

	my $ret_hash;

	while ( $self->nextObject() ) {
		my $result = $self->getObject();
		$ret_hash->{ $result->{base_char} } = $result->{base_description};
	}
	
	return $ret_hash;
}

sub getShType {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	my %where;
	my $return_hash;
	if ( defined( $args{base} ) || defined( $args{description} ) ) {
		$where{base} = delete $args{base} if ( defined( $args{base} ) );
		$where{description} = delete $args{description} if ( defined( $args{description} ) );
		$return_hash = 1;
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'soft_hard_type', '*', \%where, 'substr(sub_type,0,1) desc, description' );

	$self->{dbh}->prepare($stmnt);
	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{sth}->errstr ) ) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		if ( $return_hash ) {
			return $self->{dbh}->fetchRow();
		}
		return 1;
	}
}

sub getSuperTypeDescription {
	my ( $self, $base ) = @_;
	undef $self->{errmsg};

	my $where = { 'sub.base' => $base };
	my ( $stmnt, @bind ) = $self->{sql}->select( 'soft_hard_type sub', 'super.description', $where );
	
	my %join = ( 'JOIN soft_hard_type super' => { 'super.base' => 'sub.sub_type' } );
	
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
		
	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return $self->{dbh}->fetchRow();
}

sub setShType {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	if ( !$args{description} ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}

	my %check = (
		description => $args{description},
		sub_type    => $args{sub_type},
	);

	if ( $self->{dbh}->checkIfExists( \%check, 'soft_hard_type' ) ) {
		$self->{errmsg} = 'entry exists';
		return 0;
	}
	
	my %where = ( base => delete $args{base} );
	
	my ( $stmnt, @bind ) = $self->{sql}->update( 'soft_hard_type', \%args, \%where );
	my $sth = $self->{dbh}->prepare($stmnt);

	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{sth}->errstr ) ) {
		$self->{errmsg} = 'DB update error' . $self->{dbh}->{sth}->errstr;
		return 0;
	} else {
		return 1;
	}
}

sub addShType {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	if ( !$args{description} || !$args{sub_type} ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}

	my %check = (
		description => $args{description},
		sub_type    => $args{sub_type}
	);

	if ( $self->{dbh}->checkIfExists( \%check, 'soft_hard_type' ) ) {
		$self->{errmsg} = 'Type already exists.';
		return 0;
	}

	my $sql = 'SELECT substr(max(base),1,1) AS firstchar, substr(max(base),2,1) AS lastchar FROM soft_hard_type WHERE character_length(base) >1';
	$self->{dbh}->prepare($sql);
	$self->{dbh}->executeWithBinds();
	if ( $self->{dbh}->{sth}->errstr ) { $self->{errmsg} = $self->{dbh}->{sth}->errstr; }
	my $newchar = 0;

	if ( $self->{dbh}->nextRecord() ) {
		my $result = $self->{dbh}->getRecord();
		if ( defined( $result->{firstchar} ) ) {
			$newchar = &_getNewChar( $result->{firstchar}, $result->{lastchar} );
			if ( $newchar =~ /zz/ ) {
				$self->{errmsg} = "You have reached the maxium possible type descriptions (aa-zz).";
				return 0;
			}
		} else {
			$newchar = 'aa';
		}
	}

	my %add = (
		base => $newchar,
		description => $args{description},
		sub_type => $args{sub_type}
	);

	my ( $stmnt, @bind ) = $self->{sql}->insert( 'soft_hard_type', \%add );
	my $sth = $self->{dbh}->prepare($stmnt);
	if ( $self->{dbh}->executeWithBinds(@bind) ) {
		return $newchar;
	} else {
		$self->{errmsg} = $self->{dbh}->{sth}->errstr;
		return 0;
	}
}

sub delShType {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};

	if ( !$args{base} ) {
		$self->{errmsg} = 'Missing mandatory parameter!';
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->delete( 'soft_hard_type', { base => $args{base} } );
	my $sth = $self->{dbh}->prepare($stmnt);

	$self->{dbh}->executeWithBinds(@bind);

	if ( defined( $self->{dbh}->{sth}->errstr ) ) {
		$self->{errmsg} =  $self->{dbh}->{db_error_msg};
		return 0;
	} else {
		return 1;
	}
}

sub _getNewChar($$) {
	# generate a base_type character.
	# values range from aa to zz
	# given firstchar b and lastchar y, return value would be 'bz'
	# 676 max available combinations
	my $firstchar = $_[0];
	my $lastchar  = $_[1];
	my ( $location_first, $location_last, $newchar );
		
	my @alpha = ( "a" .. "z" );
	my $alfa  = "@alpha";
	$alfa =~ s/ //g;
	my $num = scalar(@alpha);

	while ( $alfa =~ m/$firstchar/g ) {
		$location_first = pos($alfa) - 1;
	}
	while ( $alfa =~ m/$lastchar/g ) {
		$location_last = pos($alfa) - 1;
	}

	if ( $location_last < $num - 1 ) {
		my $nextchar = $alpha[ $location_last + 1 ];
		$newchar  = $firstchar . $nextchar;
	} elsif ( $location_last == $num - 1 ) {
		$newchar = $alpha[ $location_first + 1 ] . 'a';
	} else {
		return 0;    #$newchar = 'OUT OF COMBINATIONS';
	}
	return $newchar;
}

# key options for %args input variable are:
# search, which is used to search name and producer column of table software_hardware;
# types, which is an array types. It searches column 'sub_type' and 'base' of table soft_hard_type;
# not_type, holds one type which is excluded in the search. It searches column 'sub_type' and 'base' 
# of table soft_hard_type and includes records that have a NULL value in column soft_hard_type.sub_type;
sub searchSH {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	my @nests;
			
	my $search = delete $args{search};
	my %where = (
		"producer || ' ' || name" => { -ilike => "%".trim($search)."%" },
		deleted => 'f'
	);

	if ( exists( $args{types} ) ) {
		push @nests, [ 
			"sht.sub_type" => \@{ $args{types} },
			"sht.base" => \@{ $args{types} }
		];
	}
	
	if ( exists( $args{not_type} ) ) {
		my $is_null = "IS NULL";
		
		foreach my $not_type ( @{ $args{not_type} } ) {
			push @nests, [
				 "sht.sub_type" => { "!=" => $not_type },
				 "sht.sub_type" => \$is_null
			 ],
			 { "sht.base" => { "!="  => $not_type } };
		}
	}

	$where{-and} = \@nests if ( @nests );

	my $select = "sh.*, sht.*, count(shu.soft_hard_id) AS in_use";
	my $order_by = " ORDER BY sh.producer, sh.name, sh.version";
	my $group_by = " GROUP BY sh.producer, sh.name, sh.version, sh.deleted, sh.monitored, sh.id, sh.type, sh.cpe_id, sht.description, sht.base, sht.sub_type";
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "software_hardware AS sh", $select, \%where );	
	my %join = ( 
		"JOIN soft_hard_type AS sht" => { "sh.type" => "sht.base" },
		"LEFT JOIN soft_hard_usage shu" => { "shu.soft_hard_id" => "sh.id" }
	);
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$stmnt .= $group_by . $order_by;

	$self->{dbh}->prepare( $stmnt );
	my $result = $self->{dbh}->executeWithBinds( @bind );

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
 	return $result;	
}

sub getConstituentUsage {
	my ( $self, $sh_id ) = @_;
	undef $self->{errmsg};
	
	my %where = ( "cg.status" => { "!=" => 1 }, soft_hard_id => $sh_id );
	my @cg_data;
	
	my ( $stmnt, @binds ) = $self->{sql}->select( "constituent_group AS cg", "cg.*, ct.type_description", \%where, "cg.name" );
	
	my %join = ( 
		"JOIN soft_hard_usage AS shu" => { "shu.group_id" => "cg.id"	},
		"JOIN constituent_type AS ct" => { "ct.id" => "cg.constituent_type" }
	);

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @binds );

	while ( $self->nextObject ) {
		push( @cg_data, $self->getObject );
	}
		
	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	return \@cg_data;
}

sub countUsage {
	my ( $self, %where ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'soft_hard_usage shu', 'COUNT(shu.*) as cnt', \%where );
	my %join = ( 'JOIN software_hardware sh' => { 'shu.soft_hard_id' => 'sh.id' } );	

	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg};

	my $count = $self->{dbh}->fetchRow()->{cnt};
	return $count;	
}

sub loadCollection {
	my ( $self, %where ) = @_;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( 'software_hardware', '*', \%where, 'producer, name, version' );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	my @softwareHardware;
	while ( $self->nextObject() ) {
		push @softwareHardware, $self->getObject();
	}
	
	return \@softwareHardware;
}

1;

=head1 NAME 

Taranis::SoftwareHardware

=head1 SYNOPSIS

  use Taranis::SoftwareHardware;

  my $obj = Taranis::SoftwareHardware->new( $oTaranisConfig );

  $obj->addObject( %softwareHardware );

  $obj->addShType( description => $typeDescription, sub_type => $subType );

  $obj->countUsage( %where );

  $obj->deleteObject( table => $table, %where );

  $obj->delShType( base => $baseType );

  $obj->getBaseTypes();

  $obj->getConstituentUsage( $softwareHardwarID );

  $obj->getDistinctList();

  $obj->getList( offset => $offset, limit => $limit, %where );

  $obj->getListCount( %where );

  $obj->getShType( base => $baseType, description => $typeDescription );

  $obj->getSuperTypeDescription( $baseType );

  $obj->loadCollection( %where );

  $obj->searchSH( search => $searchText, not_type => \@notTypesList, types => \@typesList );

  $obj->setObject( %softwareHardware );

  $obj->setShType( %softwareHardwareType );

=head1 DESCRIPTION

Module for managing software/hardware data and software/hardware type settings.
Taranis comes with three default software/hardware types: 'Application' (a), 'Operating System' (o) and 'Hardware' (h).
Only 'o' (Operating System) and its subtypes, if any, are considered platforms; all others are considered products.

=head1 METHODS

=head2 new( $oTaranisConfig )

Constructor of the C<Taranis::SoftwareHardware> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::SoftwareHardware->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{cfg};

Returns the blessed object.

=head2 addObject( %softwareHardware )

Adds software/hardware. By default C<deleted> and C<monitored> are set to FALSE.

    $obj->addObject( producer => 'NCSC', name => 'Taranis', version => '3.2', type => 'a' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 addShType( description => $typeDescription, sub_type => $subType )

Adds a new software/hardware type. All new types are a subtype of the three main types: 'Application' (a), 'Operating System' (o) and 'Hardware' (h).
All new types have a two letter identifier, ranging from 'aa' to 'zz'.

    $obj->addShType( description => 'Homegrown Application', sub_type => 'a' );

If successful returns the new identifier. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 countUsage( %where )

Counts the groups that have a specific software/hardware in use.

    $obj->countUsage( cpe_id => 'cpe:/a:ncsc:taranis:3.2' );

Returns a number.

=head2 deleteObject( table => $table, %where )

Deletes a software/hardware record. Can also be used to delete records from other tables like table C<soft_hard_usage>.

    $obj->deleteObject( cpe_id => 'cpe:/a:ncsc:taranis:3.2' );

OR

    $obj->deleteObject( table => 'soft_hard_usage', soft_hard_id => 234 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 delShType( base => $baseType )

Deletes a software/hardware type. Parameter C<base> is mandatory.

    $obj->delShType( base => 'ab' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getBaseTypes()

Retrieves all software/hardware types. Column C<sub_type> is excluded.

    $obj->getBaseTypes();

Returns an HASH reference with the keys the equal to column C<base> and the values column C<description>.

=head2 getConstituentUsage( $softwareHardwarID )

Retrieves all constituents that have C<$softwareHardwarID> in use.

    $obj->getConstituentUsage( 45 );

Returns an ARRAY reference.

=head2 getDistinctList()

Retrieves a distinct list of producers.

    $obj->getDistinctList();

Returns an ARRAY reference.

=head2 getList( offset => $offset, limit => $limit, %where )

Executes a SELECT statement on table C<software_hardware>. Parameters C<offset> and C<limit> are typically used for pagination.
If parameter C<name> is set will search a concatenation of columns C<producer> and C<name> separated by a space.

    $obj->getList( offset => 100, limit => 100, name => 'ncsc taranis' );

The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getListCount( %where )

Performs the same search as getList() without the limit and offset.

    $obj->getListCount( name => 'ncsc taranis' );

Returns the record count of the search.

=head2 getShType( base => $baseType, description => $typeDescription )

Queries for software/hardware types.

    $obj->getShType();

OR

    $obj->getShType( base => 'ac' );

If successful and no parameters are set returns TRUE; the result of query can be retrieved by using getObject() and nextObject().
If successful and parameter C<base> or C<description> is set returns an HASH reference with one software/hardware type.
If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getSuperTypeDescription( $baseType )

Retrieves a software/hardware type that matches with C<$baseType>.

    $obj->getSuperTypeDescription( 'ac' );

Returns an HASH reference.

=head2 loadCollection( %where )

Retrieves software/hardware.

    $obj->loadCollection( producer => 'NCSC' );

Returns an ARRAY reference.

=head2 searchSH( search => $searchText, not_type => \@notTypesList, types => \@typesList )

Retrieves software/hardware, same as loadCollectiont() with but with more options and more detailed results.

    $obj->searchSH( search => 'ncsc taranis', not_type => [ 'o' ] );

Besides the software/hardware details also adds constituent usage information (key C<in_use>)and software/hardware type information.

Returns an ARRAY reference.

=head2 setObject( %softwareHardware )

Updates software/hardware. Parameter C<id> or C<cpe_id> is mandatory. 

    $obj->setObject( deleted => 1, id => 83 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 setShType( base => $baseType, description => $description )

Updates software/hardware type. Both parameters are mandatory.

    $obj->setShType( base => 'aa', description => 'My Application Group' );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Delete failed, corresponding id not found in database.>

Caused by deleteObject() when there is no record can be found with set parameters. 
You should check the input parameters. 

=item *

I<No unique id given to identify record>

Caused by setObject() when parameter C<id> and C<cpe_id> is not set.
You should check parameters C<id> and C<cpe_id>.

=item *

I<Missing mandatory parameter!>

Caused by setShType(), addShType() or delShType() when a mandatory parameter is not set or not defined.
You should check input parameters.

=item *

I<Type already exists.>

Caused by addShType() when trying to add a software/hardware type which already exists.
You should check the C<description> parameter.

=item *

I<You have reached the maxium possible type descriptions (aa-zz).>

Caused by addShType() when all two letter combinations are used as software/hardware type identifier.  
You should probably rethink the way you are organizing software/hardware...

=back

=cut
