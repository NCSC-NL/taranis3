# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Publish;

use 5.010;
use strict;

use Taranis qw(:all);
use Taranis::Database;
use Taranis::Config;
use Taranis::Publication;
use Taranis::FunctionalWrapper qw(Config Database Sql);
use Taranis::Mail ();

use Carp;
use SQL::Abstract::More;
use Tie::IxHash;
use HTML::Entities;
use Encode;
use MIME::Base64;
use List::Util qw(max);
use List::MoreUtils qw(uniq);
use Array::Utils qw(intersect);

sub new {
	my ($class, $config) = @_;

	my $self = {
		errmsg 	=> undef,
		dbh => Database,
		sql => Sql,
		config => $config || Config,
	};
	return( bless( $self, $class ) );
}

# getNextAdvisoryId: retrieve a new, unused advisory ID, directly following the last advisory ID, for instance
# 'NCSC-2014-004'.
# The first time this method is called in a new year the ID will change the year and the sub number to 'NCSC-2015-001'.
sub getNextAdvisoryId {
	my $advisoryPrefix = Config->{advisory_prefix} // die "no advisory_prefix configured";
	my $advisoryIdLength = Config->{advisory_id_length} // die "no advisory_id_length configured";
	my $currentYear = nowstring(6);

	return sprintf "%s-%d-%0${advisoryIdLength}d",
		$advisoryPrefix,
		$currentYear,
		max(
			0,
			_maxIdInTable('publication_advisory',         $advisoryPrefix, $currentYear),
			_maxIdInTable('publication_advisory_forward', $advisoryPrefix, $currentYear),
		) + 1;

	sub _maxIdInTable {
		my ($table, $advisoryPrefix, $currentYear) = @_;
		return scalar Database->simple->select(
			-from => $table,
			-columns =>
				# FOO-2015-0013 => 0013 => 13
				q{cast(regexp_replace(govcertid, '.*-', '') as integer)|id_as_int},
			-where => {
				govcertid => {
					-ilike =>     "$advisoryPrefix-$currentYear%",
					-not_ilike => "$advisoryPrefix-$currentYear-X%",
				},
			},
			-order_by => {-desc => 'id_as_int'
			},
			-limit => 1
		)->list;
	}
}

# my $adv = $publist->getPriorAdvisory($certid, [$table, $db]);
# Return the record which shows the advisory details for the advisory
# which came before $certid.  This may cross year boundaries.  The $adv
# may be from a different $table (e.g. publication_advisory_website), but
# defaults to 'publication_advisory'.
#
# Tested in t/400-web-prevadv.t
#XXX This method is not used anymore, but might be useful in the future.
sub _previousAdvisoryId($;$$) {
	my ($self, $advisory_id, $table, $db) = @_;
	$table ||= 'publication_advisory';
	$db    ||= Database->simple;

	my ($prefix, $year, $sequence_number) = split /\-/, $advisory_id;

	if($sequence_number == 1) {
		# First release of this year, check last of previous year.
		# The CAST is needed when the seqnr changes length during a year.
		my $last_year = $year - 1;
		return scalar $db->query( <<__LAST_OF_PREVIOUS_YEAR )->list;
SELECT govcertid
  FROM $table
 WHERE govcertid ILIKE '$prefix-$last_year-%'
   AND govcertid NOT ILIKE '$prefix-$last_year-X%'
 ORDER BY CAST(REGEXP_REPLACE(govcertid, '.*-', '') AS INTEGER) DESC
 LIMIT 1
__LAST_OF_PREVIOUS_YEAR
	}

	my $prev  = $sequence_number - 1;
	scalar $db->query( <<__LAST_OF_THIS_YEAR )->list;
SELECT govcertid
  FROM $table
 WHERE govcertid ~ '^$prefix-$year-0*$prev\$'
 LIMIT 1
__LAST_OF_THIS_YEAR
}

sub getPriorPublication($$;$) {
	my ($self, $certid, $table, $db) = @_;
	$table ||= 'publication_advisory';
	$db    ||= Database->simple;

	my $previousId
	   = $self->_previousAdvisoryId($certid, undef, $db)
	  || $self->_previousAdvisoryId($certid,'publication_advisory_forward',$db);

	$previousId or return;

	$db->query( <<__PUBLICATION, $previousId)->hash;
SELECT *
  FROM $table
 WHERE govcertid = ?
 ORDER BY version DESC
 LIMIT 1
__PUBLICATION
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

# getConstituentGroupsByWares(@wareList)
# Fetch all active constituent groups that care about any of the (hard|soft)ware items in @wareList, or that have the
# S/H list disabled.
# Like getConstituentGroupsByWareCombinations, but with one ware per combination.
sub getConstituentGroupsByWares {
	my ($self, @wareList) = @_;

	return $self->getConstituentGroupsByWareCombinations(
		[map [$_], @wareList]
	);
}

# getConstituentGroupsByWareCombinations(\@wareCombinations)
# Fetch all active constituent groups that care about any of the (hard|soft)ware combinations in @wareCombinations, or
# that have the S/H list disabled.
# Each element of @wareCombinations is a set (combination) of product ids to match against constituent groups'
# selections; id "X" means "any product".
sub getConstituentGroupsByWareCombinations {
	my ($self, $wareCombinations) = @_;

	my @group_ids = (
		@{ _fuzzilyGetConstituentGroupsForWareCombinations($wareCombinations) },
		Database->simple->query(
			"SELECT id from constituent_group WHERE use_sh = 'false' AND status = '0'"
		)->flat,
	);
	return [uniq @group_ids];
}

# _fuzzilyGetConstituentGroupsForWareCombinations( [[1, 2], [5, "X"]] )
# Run _fuzzilyGetConstituentGroupsForWareCombination over a bunch of (hard|soft)ware sets, combine the results
# (OR-style).
sub _fuzzilyGetConstituentGroupsForWareCombinations {
	my ($wareCombinations) = @_;

	my @group_ids;

	for my $wareCombination (@$wareCombinations) {
		push @group_ids, @{ _fuzzilyGetConstituentGroupsForWareCombination($wareCombination) };
	}
	return [uniq @group_ids];
}

# _fuzzilyGetConstituentGroupsForWareCombination([1, 4, 8, "X"])
# Fetch all active constituent groups that care about all the (hard|soft)ware items in @$wareCombination.
# Do it "fuzzily" in that caring about a "related" item (see _getRelatedWares) also counts.
# Elements equal to "X" or "x" are ignored (for historical reasons, "X" means "any hard/software item").
#
# For example, if ware 1 = Bugzilla v3.2 rc1, and ware 2 = Linux kernel v3.3.0, then
#     _fuzzilyGetConstituentGroupsForWareCombination([1, 2, "X"])
# will try to fetch the groups that care about some ware related to Bugzilla 3.2 rc1, *AND* care about some ware
# related to Linux kernel 3.3.0. (The "X", meaning "any ware", is ignored because everyone cares about something.)
# See _getRelatedWares for the definition of "related".
sub _fuzzilyGetConstituentGroupsForWareCombination {
	my ($wareCombination) = @_;

	## 1) Start with all groups.
	my @group_ids = Database->simple->select(
		-from => 'constituent_group',
		-columns => 'id',
		-where => {
			status => 0,  # 0 = active, 1 = deleted
		},
	)->flat;

	## 2) Per ware, filter out the groups that aren't interested in that ware.
	foreach my $ware (@$wareCombination) {
		# 'X' means 'anything', so we can ignore it.
		next if lc $ware eq 'x';

		# Remove groups that don't like this ware.
		@group_ids = intersect(
			@{ _getConstituentGroupsForWareList(_getRelatedWares($ware)) },
			@group_ids
		);
	}

	## 3) Return the survivors.
	return [
		# &Array::Utils::intersect casts our ints to strings; undo that.
		map {int} @group_ids
	];
}

# Given a (hard|soft)ware item $ware_id, fetch "related" products for fuzzy matching against constituent groups'
# hard/software lists.
sub _getRelatedWares{
	my ($ware_id) = @_;

	my $ware = Database->simple->select(
		-from => 'software_hardware',
		-columns => [qw/name producer version/],
		-where => {id => $ware_id},
	)->hash;

	my $where = {
		name => {-ilike => trim($ware->{name}) . '%'},
		producer => $ware->{producer},
		deleted => 0,
	};
	$where->{version} = [undef, ''] if $ware->{version};

	return [
		Database->simple->select(
			-from => 'software_hardware',
			-columns => 'id',
			-where => $where,
		)->flat
	];
}

# _getConstituentGroupsForWareList([1, 2, 3])
# Fetch all active constituent groups that care about any of the (hard|soft)ware items in @$soft_hard_ids.
sub _getConstituentGroupsForWareList {
	my ($soft_hard_ids) = shift;

	return [ Database->simple->select(
		-from => [-join => qw/
			constituent_group|cg
				cg.id=group_id soft_hard_usage|shu
		/],
		-columns => [-distinct => 'cg.id'],
		-where => {
			'shu.soft_hard_id' => {-in => $soft_hard_ids},
			'cg.status' => 0,  # 0 = active, 1 = deleted
		},
	)->flat ];
}

# getConstituentGroupsForPublication($publication_type_id): Retrieve all enabled groups for specific publication type.
sub getConstituentGroupsForPublication {
	my ($self, $publication_type_id) = @_;

	return [ Database->simple->select(
		-from => [-join => qw/
			constituent_group|cg
				constituent_type=constituent_type_id   type_publication_constituent|tpc
		/],
		-columns => 'cg.*',
		-where => {
			'tpc.publication_type_id' => $publication_type_id,
			'cg.status' => 0,
		},
		-order_by => 'cg.name',
	)->hashes ];
}

# getIndividualsForSending($publication_type_id, \@constituent_group_ids)
# Retrieve sending details of constituent individuals which are member of the given groups (@constituent_group_ids) and
# want to receive publications of the supplied publication type.
#     $obj->getIndividualsForSending( 23, [ 45, 78, 88, 89, 94 ] );
sub getIndividualsForSending {
	my ($self, $publication_type_id, @groups) = @_;

	return [ Database->simple->select(
		-from => [-join => qw/
			constituent_individual|ci
				ci.id=constituent_id  constituent_publication|cp
				ci.id=constituent_id  membership|m
		/],
		-columns => [-distinct => 'ci.*'],
		-where => {
			'ci.status' => 0,
			'cp.type_id' => $publication_type_id,
			'm.group_id' => \@groups,
			'ci.emailaddress' => {'!=', ''}
		},
		-order_by => 'ci.lastname',
	)->hashes ];
}

# getEmailsForEodWhite()
# EodWhite is sent to all valid addresses... but this will probably
# change during testing ;-)
sub getEmailsForEodWhite() {
	my $self = shift;

	# status=1 means 'deleted'
	return [ Database->simple->query(<<'__ALL_ADDRESSES')->flat ];
SELECT DISTINCT emailaddress
  FROM constituent_individual
 WHERE status = 0
   AND emailaddress NOT NULL
   AND emailaddress != ''
__ALL_ADDRESSES
}

# sendPublication: send the publication by email.
#
# Parameters are:
#
# addresses = \@email_addresses (list of addresses)
# subject = $email_subject
# msg = $email_message_text (email body)
# pub_type = $publication_type ('eow', 'eos', 'eod', 'eod_public' or 'advisory')
# attach_xml = $attach_xml (flag for adding XML publication, 0 or 1)
# xml_description = $xml_description (sets the 'Content-description' of the XML part of the email)
# xml_filename = $xml_filename
# xml_content => $xml_txt
# from_name = $sender_name
# from_address = $sender_email_address
# attachments = $arrayref
#
# $obj->sendPublication(
#     addresses  => [ 'john.doe@domain.com', 'jane.doe@domain.com' ],
#     subject    => 'subject of email message',
#     msg        => 'email message',
#     pub_type   => 'advisory',
#     attach_xml => 0
# );
#
# OR
#
# $obj->sendPublication(
#     addresses       => [ 'john.doe@domain.com', 'jane.doe@domain.com' ],
#     subject         => 'subject of email message',
#     msg             => 'email message',
#     pub_type        => 'advisory',
#     attach_xml      => 1,
#     xml_description => 'my xml file description',
#     xml_filename    => 'my_advisory.xml',
#     xml_content     => $xml_content_string
# );
#
# OR
#
# $obj->sendPublication(
#     addresses    => [ 'john.doe@domain.com', 'jane.doe@domain.com' ],
#     subject      => 'subject of email message',
#     msg          => 'email message',
#     pub_type     => 'eow',
#     attach_xml   => 0,
#     from_name    => 'James Doe',
#     from_address => 'james.doe@domain.com'
# );
#
# Note: All addresses will be put in the BCC field of the email.
#
# Returns 'OK' if sending was successful or an error string if the SMTP server rejected the email.
sub sendPublication {
	my ($self, %args) = @_;

	my $fromto_by_type = {
		eow => {
			to_address   => Config->{publish_eow_to},
			from_address => Config->{publish_eow_from},
			from_name    => HTML::Entities::decode($args{from_name}),
		},
		eod => {
			to_address   => Config->{publish_eod_to},
			from_address => Config->{publish_eod_from},
			from_name    => HTML::Entities::decode($args{from_name}),
		},
		eod_public => {
			to_address   => Config->{publish_eod_to_public},
			from_address => Config->{publish_eod_from},
			from_name    => HTML::Entities::decode($args{from_name}),
		},
		eod_white => {
			to_address   => Config->{publish_eod_white_to},
			from_address => Config->{publish_eod_from},
			from_name    => HTML::Entities::decode($args{from_name}),
		},
		eos => {
			to_address   => Config->{publish_eos_to},
			from_address => Config->{publish_eos_from},
			from_name    => HTML::Entities::decode($args{from_name}),
		},
		advisory => {
			to_address   => $args{attach_xml} ? Config->{publish_xml_advisory_to} : Config->{publish_advisory_to},
			from_address => Config->{publish_advisory_from_address},
			from_name    => Config->{publish_advisory_from_name},
		},
	};
	my $fromto = $fromto_by_type->{ $args{pub_type} } or croak "invalid publication type '$args{pub_type}'";
	for (keys %$fromto) {
		return "No $_ configured for $args{pub_type} publication." unless $fromto->{$_};
	}

	my @attachments;
	if($args{attach_xml}) {
		my $filename = $args{xml_filename};
		$filename   .= '.xml' if $filename !~ /\.xml$/i;

		push @attachments, Taranis::Mail->attachment(
			data        => $args{xml_content},
			description => $args{xml_description},
			filename    => $filename,
			mime_type   => 'text/xml',
		);
	}

	push @attachments, Taranis::Mail->attachment(
		data       => $_->{binary},
		filename   => $_->{filename},
		mime_type  => $_->{mimetype},
	) for @{$args{attachments} || []};

	my $msg = Taranis::Mail->build(
		From       => "$fromto->{from_name} <$fromto->{from_address}>",
		To         => $fromto->{to_address},
		Bcc        => $args{addresses} // [],
		Subject    => $args{subject},
		plain_text => $args{msg},
		attach     => \@attachments,
	);
	$msg->send;

	"OK";
}

sub setSendingResult {
	my ($self, %inserts) = @_;
	
	Database->simple->insert("publication2constituent", \%inserts);
}

# getPublishDetails: retrieve the results of a published publication.
#     $obj->getPublishDetails( 34, 'advisory' );
#     $obj->getPublishDetails( 35, 'eow' );
sub getPublishDetails {
	my ($self, $publication_id, $publication_type) = @_;

	return {
		receivers_list => [
			Database->simple->select(
				-from => [-join => qw/
					publication2constituent|p2c
						constituent_id=id     constituent_individual|ci
						id=constituent_id     membership
						group_id=id           constituent_group|cg
				/],
				-columns => [
					"array_to_string(array_agg(cg.name), ', ')|groupname",  # group names, joined by ', '
					'ci.id|ci_id',
					'ci.firstname',
					'ci.lastname',
					'ci.emailaddress',
					"to_char(p2c.timestamp, 'DD-MM-YYYY HH24:MI:SS')|timestamp_str",
				],
				-where => {'p2c.publication_id' => $publication_id, 'p2c.channel' => 1},
				-group_by => [qw/ci.id ci.firstname ci.lastname ci.emailaddress timestamp_str p2c.id/],
				-order_by => [qw/lastname firstname/],
			)->hashes
		],

		publication => Database->simple->select(
			-from => lc($publication_type) eq 'advisory'
				? [-join => qw/publication|pu   id=publication_id   publication_advisory|pa/]
				: 'publication as pu',

			-columns => [
				'pu.approved_by', 'pu.published_by',
				"to_char(pu.approved_on,  'DD-MM-YYYY HH24:MI:SS')|approved_on_str",
				"to_char(pu.published_on, 'DD-MM-YYYY HH24:MI:SS')|published_on_str",

				lc($publication_type) eq 'advisory'
					? ('pa.title|pub_title', 'pa.damage', 'pa.probability')
					: ('pu.title|pub_title'),
			],
			-where => {'pu.id' => $publication_id},
		)->hash,
	};
}

# setAnalysisToDoneStatus( $publicationId, $namedPublicationId )
#
# Sets linked analyses to status 'done' and adds a comment to the analysis comments.
#
#    $obj->setAnalysisToDoneStatus( 89, 'NCSC-2014-0001' );
#
# If successful returns the number of analyses which are set to 'done'.
# If unsuccessful returns FALSE and sets $obj->{errmsg} to Taranis::Database->{db_error_msg}.
sub setAnalysisToDoneStatus {
	my ( $self, $publicationId, $namedPublicationId ) = @_;
	undef $self->{errmsg};
	
	my $error = '';
	my $openDoneStatusSettings = ( $self->{config} )
		? $self->{config}->{analyze_published_status}
		: Taranis::Config->getSetting( "analyze_published_status" );

	my $openDoneStatusSettingsCopy = $openDoneStatusSettings;
	
	$openDoneStatusSettingsCopy =~ s/\s//g;
	
	if ( $openDoneStatusSettingsCopy !~ /^([^:,]+:[^:,]+,)*[^:,]+:[^:,]+$/ || !$openDoneStatusSettingsCopy ) {	
		$self->{errmsg} = "Incorrect setting found. Cannot change the status of linked analysis. Please check the setting analyze_published_status in the main configuration.";
		return 0;
	} 
	
	my @openDoneStatusPairs = split( /,/, $openDoneStatusSettings ); 
	
	my %openDoneRegister;
	foreach my $pair ( @openDoneStatusPairs ) {
		$pair = trim $pair;
		$pair =~ /(.*?):(.*?)$/;

		my $openStatus = $1;
		my $doneStatus = $2;

		$openDoneRegister{ trim( lc( $openStatus ) ) } = trim( lc( $doneStatus ) );
	}

	my %analyzeWhere = ( 'ap.publication_id' => $publicationId );

	my ( $analyzeStmnt, @analyzeBind ) = $self->{sql}->select( 'analysis a', 'a.id, a.status', \%analyzeWhere );
	my %join = ( 'JOIN analysis_publication ap' => { 'ap.analysis_id' => 'a.id'} );
	
	$analyzeStmnt = $self->{dbh}->sqlJoin( \%join, $analyzeStmnt );

	$self->{dbh}->prepare( $analyzeStmnt );
	$self->{dbh}->executeWithBinds( @analyzeBind );
	
	my @analysis;
	while ( $self->nextObject() ) {
		push @analysis, $self->getObject();
	}
	
	my @doneStatuses = values( %openDoneRegister );

	my $analysisCount = 0;
	
	ANALYSIS:
	foreach my $analyze ( @analysis ) {
		
		next ANALYSIS if ( grep( /^$analyze->{status}$/i, @doneStatuses ) ); 
		
#		my $doneStatus = ( exists( $openDoneRegister{ lc( $analyze->{status} ) } ) ) ? $openDoneRegister{ lc( $analyze->{status} ) } : 'done';

		my %where = ( id => $analyze->{id}, 'upper(status)' => uc( $analyze->{status} ) );

		my $dateTime = nowstring(7);
#		my $appendComments = "comments || '\n\n[== Taranis ( $dateTime CET) ==]\n Set to status Done, publication $namedPublicationId has been published.'";
		my $appendComments = "comments || '\n\n[== Taranis ( $dateTime CET) ==]\n Publication $namedPublicationId has been published.'";

# it was requested to disable the done status, but keep the comment field.
#		my ( $updateStmnt, @updateBind ) = $self->{sql}->update( 'analysis', { status => $doneStatus, comments => \$appendComments }, \%where );
		my ( $updateStmnt, @updateBind ) = $self->{sql}->update( 'analysis', { comments => \$appendComments }, \%where );
		
		$self->{dbh}->prepare( $updateStmnt );
	
		if ( defined( $self->{dbh}->executeWithBinds( @updateBind ) ) < 1 ) {
			$error = $self->{dbh}->{db_error_msg} . "\n";
		} else {
			$analysisCount++;
		}
	}

	if ( $error ) {
		$self->{errmsg} = $error;
		return 0;
	} else {
		return $analysisCount;
	}
}

# getUnpublishedCount()
#
# Counts the number of publications with status 'Approved' per publication type.
# Returns an ARRAY reference with entries like { approved_count => $count, title => $publicationType }.
sub getUnpublishedCount {
	return [ Database->simple->select(
		-from => [-join => qw/ publication|p  type=id  publication_type|pt /],
		-columns => ['count(*)|approved_count', 'pt.title'],
		-where => {status => 2},
		-group_by => "pt.title",
	)->hashes ];
}

1;
