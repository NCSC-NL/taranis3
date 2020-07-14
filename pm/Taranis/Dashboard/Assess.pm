# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Dashboard::Assess;

use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::TagCloud;
use Taranis qw(:all);
use Tie::IxHash;
use SQL::Abstract::More;
use JSON;
use HTML::Entities qw(encode_entities);
use strict;

sub new {
	my ( $class, $config, $settings ) = @_;

	bless +{
		errmsg => undef,
		dbh => Database,
		sql => Sql,
		tpl => 'dashboard_assess.tt',
		tpl_minified => 'dashboard_assess_minified.tt',
		settings => $settings,
	}, $class;
}

sub numberOfUnreadItems {
	my ($self) = @_;

	my $settings = $self->{settings} || {};
	if($settings->{categories} ) {
		my @categories = flat $settings->{categories}->{category};
		my ( $stmnt, @binds ) = $self->{sql}->select( 'item AS i', 'COUNT(i.*) AS count', { 'c.name' => \@categories, 'i.status' => '0' } );

		my %join = ( 'JOIN category c' => { 'c.id' => 'i.category' } );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
		$self->{dbh}->prepare($stmnt);
		$self->{dbh}->executeWithBinds(@binds);

	} else {
		$self->{dbh}->prepare("SELECT COUNT(*) AS count FROM item WHERE status = 0");
		$self->{dbh}->executeWithBinds;
	}

	$self->{dbh}->fetchRow->{count};
}

sub oldestUnreadItem {
	my ( $self ) = @_;

	my $select = "to_char(MIN(created), 'HH24:MI DD-MM-YYYY') AS oldest_created, FLOOR(EXTRACT(EPOCH FROM current_timestamp - MIN(created))/3600) AS hours_ago";
	my %where = (
		'item.status' => '0',
		'item.created' => { '<', \"NOW() - '2 hours'::INTERVAL" },
		'current_time' => { '>', '12:00' }
	);

	my $settings = $self->{settings} || {};
	if($settings->{categories} ) {
		my @categories = flat $settings->{categories}->{category};
		$where{'category.name'} = \@categories if @categories;
	}

	my ($stmnt, @binds) = $self->{sql}->select( 'item', $select, \%where );

	if($settings->{categories} ) {
		my %join = ( 'JOIN category' => { 'category.id' => 'item.category' } );
		$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	}
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds(@binds);
	my $oldest = $self->{dbh}->fetchRow;

	if(my $h = $oldest->{hours_ago}) {
		$oldest->{hours_ago} = $h > 168*2 ? int($h/168).'w' : $h > 24*2 ? int($h/24).'d' : $h.'h';
	}
	$oldest;
}

sub assessTagCloud {
	my ($self) = @_;

	$self->{dbh}->prepare("SELECT tag_cloud FROM statistics_assess ORDER BY timestamp DESC LIMIT 1");
	$self->{dbh}->executeWithBinds;
	my $tagCloud = $self->{dbh}->fetchRow
		or return \'{}';

	my $tc      = Taranis::TagCloud->new;
	my $tagList = $tc->sortList(from_json( $tagCloud->{tag_cloud} ));
	my $list    = $tc->resizeList( list => $tagList, maximumUniqWords => 20, level => 20 );

	 +{ type => 'tagcloud',
		name => 'assessTagCloud',
		data => $list,
		link => 'assess/assess/displayAssess/searchkeywords=',
	  };
}

sub createAssessTagCloudList {
	my ( $self ) = @_;

	my $stmnt = "SELECT MAX(timestamp) AS last_count FROM statistics_assess WHERE timestamp > NOW() - '20 minutes'::INTERVAL;";
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds();

	return 1
		if $self->{dbh}->fetchRow->{last_count};

	my %where = ( 'i.created' => { '>', \"NOW() - '1 day'::INTERVAL"} );

	my $settings = $self->{settings} || {};
	if($settings->{categories} ) {
		my @categories = flat $settings->{categories}->{category};
		$where{'c.name'} = \@categories if @categories;
	}

	my ( $stmnt, @bind ) = $self->{sql}->select( 'item i', 'i.title', \%where );

	my %join = ( 'JOIN category c' => { 'c.id' => 'i.category' } );
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );

	my $text = '';
	while(my $item = $self->{dbh}->nextRecord) {
		$text .= $item->{title} . ' ';
	}

	my $tc = Taranis::TagCloud->new();
	my $list = $tc->createTagsListFromText( text => $text );

	tie my %resizedList, 'Tie::IxHash';
	foreach my $tag (grep ! $tc->isBlacklisted($_), keys %$list ) {
		$resizedList{encode_entities $tag} = $list->{$tag};
	}

	my ( $addListStmnt, @tagListBind ) = $self->{sql}->insert( "statistics_assess", { tag_cloud => to_json( \%resizedList ) } );
	$self->{dbh}->prepare( $addListStmnt );
	$self->{dbh}->executeWithBinds(@tagListBind);
	return 1;
}

1;

=head1 NAME

Taranis::Dashboard::Assess

=head1 SYNOPSIS

  use Taranis::Dashboard::Assess;

  my $obj = Taranis::Dashboard::Assess->new( $oTaranisConfig, $settings );

  $obj->numberOfUnreadItems();

  $obj->assessTagCloud();

  $obj->createAssessTagCloudList();

  $obj->oldestUnreadItem();

=head1 DESCRIPTION

Controls the content of the Assess section of the dashboard.

=head1 METHODS

=head2 new( $objTaranisConfig, $settings )

Constructor of the C<Taranis::Dashboard::Assess> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

Optionally category settings which can be set to be used by numberOfUnreadItems() and assessTagCloud(). These settings are a HASH reference with structure like C<< { categories => { category => [ 'cat1', 'cat2', etc...] } } >>.

    my $obj = Taranis::Dashboard::Assess->new( $objTaranisConfig, $settings );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Sets the template of the Assess section of the dashboard:

    $obj->{tpl}

Sets the template of the Assess section of the minified dashboard:

    $obj->{tpl_minified}

Sets the custom settings:

    $obj->{settings}

Returns the blessed object.

=head2 numberOfUnreadItems()

Retrieves the number of assess items with C<status> 'unread'.

Returns a number.

=head2 assessTagCloud()

Creates a datastructure which can be used by jQuery plugin 'jQCloud'.

Returns an HASH reference.

=head2 createAssessTagCloudList()

Inserts a new entry in table C<statistics_assess> every 20 minutes. The entry is a JSON string of wordcounts of the descriptions of assess items of the last 24 hours.

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 oldestUnreadItem()

Retrieves timestamp and calculated hours between NOW and oldest unread assess item.
Timestamp is formatted: '16:35 31-11-2014'.

Returns { oldest_created => '16:35 31-11-2014', hours_ago => 4 }

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=cut
