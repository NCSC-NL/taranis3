# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::MetaSearch;

use strict;
use warnings;

use Taranis qw(formatDateTimeString logDebug find_config);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database);
use Taranis::Config::XMLGeneric;
use Taranis::Config;

use HTML::Entities qw(decode_entities);

use Carp qw(confess);

#XXX value hit in extra (e.g. mail body) seems to be too high
my %word_scores_table = (
	required_words => { in_title => 20, in_text  => 10, in_extra => 50 },
	bonus_words    => { in_title => 15, in_text  =>  5, in_extra => 50 },
);
my $score_title_exact_match  = 100;
my $score_descr_exact_match  =  90;
my $score_all_words_in_title =  50;
my $score_all_words_in_descr =  25;
my $score_words_in_extra     =  50;
my $score_required_tag       =  25;
my $score_bonus_tag          =  10;
my $score_required_certid    =  50;
my $score_bonus_certid       =  25;

sub new(%) {
	my ($class, %args) = @_;

	my $id_match = $args{is_identifier};
	unless($id_match) {
		my $config      = $args{config} || Taranis::Config->new;
		my $id_config   = find_config $config->{identifiersconfig};

		my $ip = Taranis::Config::XMLGeneric->new($id_config, idname => 'ids');
		my @id_patterns = map $_->{pattern}, @{$ip->loadCollection()};
		my $id_patterns = join '|', @id_patterns;
		$id_match       = qr/^(?:$id_patterns)$/i;
	}

	my $log = $args{log_score} || sub {};
	$log = sub { logDebug $_[0] } if ref $log ne 'CODE';

	my $self = bless {
		errmsg   => undef,
		db       => $args{db} || Database->simple,
		log      => $log,
		is_identifier => $id_match,
	}, $class;

	$self;
}

### $ms->search(%settings)

sub search(%) {
	my ($self, %search) = @_;
	undef $self->{errmsg};

	my $patterns = decode_entities($search{search_field} || '');
	my $question = $self->_evaluateQuestion($patterns)
		or return;

	$search{question} = $question;

	# These share the configuration
	$search{publication_advisory_forward} ||= $search{publication_advisory};

	my $search_all_pubs = $search{publication}{searchAllProducts};
	my %results;

	# search assess items
	if(my $item_rules = $search{item}) {
		my $items = $self->_searchItems(\%search);

		my $archived_items = $item_rules->{searchArchive}
		  ? $self->_searchItems(\%search, in_archive => 1)
		  : [];

		$results{items} = $self->_sortScores(@$items, @$archived_items);
	}

	# search analysis
	if($search{analyze}{searchAnalyze}) {
		my $analyses = $self->_searchAnalyses(\%search);
		$results{analysis} = $self->_sortScores(@$analyses);
	}

	# search publication_advisory
	if($search_all_pubs || $search{publication_advisory}{searchAdvisory}) {
		my $own_advs = $self->_searchAdvisories(\%search, type => 'advisory');
		my $forwards = $self->_searchAdvisories(\%search, type => 'forward');
		$results{advisories} = $self->_sortScores(@$own_advs, @$forwards);
	}

	# search publication_endofweek
	if($search_all_pubs || $search{publication_endofweek}{searchEndOfWeek}) {
		my $eows = $self->_searchEndOfWeeks(\%search);
		$results{eow} = $self->_sortScores(@$eows);
	}

	# search publication_endofshift
	if($search_all_pubs || $search{publication_endofshift}{searchEndOfShift}) {
		my $eoses = $self->_searchEndOfShifts(\%search);
		$results{eos} = $self->_sortScores(@$eoses);
	}

	# search End-Of-Day
	if($search_all_pubs || $search{publication_endofday}{searchEndOfDay}) {
		my $eods = $self->_searchEndOfDays(\%search);
		$results{eod} = $self->_sortScores(@$eods);
	}

	# Ugly side-effect: collect the list of words which will get highlighted
	# in the HTML display by client-side javascript, used in meta_search.js
	$self->{keywords} = [
		@{$question->{required_words} || []},
		@{$question->{bonus_words}    || []},
	];

	#XXX working towards separate tabs for search categories
	# \%results;
	$self->_sortScores(map @{$results{$_} || []},
		qw/items analyses eow eos eod/ );
}

sub _getTags($$) {
	my ($self, $table, $id) = @_;
	# $id is a string

	$self->{db}->query(<<__GET_TAGS, $id, $table)->flat;
 SELECT tag.name
   FROM tag_item AS ti
        LEFT JOIN tag  ON ti.tag_id = tag.id
  WHERE ti.item_id         = ?
    AND ti.item_table_name = ?
__GET_TAGS
}

sub _getCertIds($$) {
	my ($self, $table, $digest) = @_;

	$self->{db}->query(<<__GET_CERTIDS, $digest)->flat;
 SELECT identifier
   FROM $table
  WHERE digest = ?
__GET_CERTIDS
}

sub _searchItems($%) {
	my ($self, $search, %args) = @_;
	my $is_archived  = $args{in_archive};

	my $item_table   = 'item';
	my $email_table  = 'email_item';
	my $ident_table  = 'identifier';
	if($is_archived) {
		$_ .= '_archive' for $item_table, $email_table, $ident_table;
	}

	my (@where, @binds);
	$self->_addSearchFilters(\@where, \@binds, it => $search->{item});
	$self->_addSearchDate(\@where, \@binds, $search, it => 'created');

	$search->{scoring} = $self->_addSearchQuestion(
		\@where, \@binds, $search,
		select_field => 'it.digest',
		find_words   => [ $item_table  => 'title', 'description' ],
		find_words   => [ $email_table => 'body' ],
		find_tags    => $item_table,
		find_certids_table => $ident_table,
	);

	my $where  = join "\n    AND ", @where;

	my $items  = $self->{db}->query(<<__SEARCH_ITEMS, @binds) or return;
 SELECT it.digest, it.title, it.description,
        TO_CHAR(it.created, 'DD-MM-YYYY HH24:MI:SS:MS') AS date,
        em.body AS body
   FROM $item_table  AS it
        LEFT JOIN $email_table AS em ON em.digest = it.digest
  WHERE $where
__SEARCH_ITEMS

	my @scored;

	while(my $item = $items->hash) {
		my $digest = $item->{digest};
		my $scored = $self->_score($search,
			type       => 'assess',
			id         => $digest,
			extra_text => $item->{body},
			tags       => [ $self->_getTags($item_table => $digest) ],
			cert_ids   => [ $self->_getCertIds($ident_table => $digest) ],
			%$item,
		);

		$scored->{is_archived} = $is_archived;
		push @scored, $scored;
	}

	\@scored;
}

sub _searchAnalyses($%) {
	my ($self, $search, %args) = @_;

	my (@where, @binds);
	$self->_addSearchFilters(\@where, \@binds, ana => $search->{analyze});
	$self->_addSearchDate(\@where, \@binds, $search, ana => 'orgdateTime');

	$self->_addSearchQuestion(\@where, \@binds, $search,
		select_field => 'ana.id',   # analysis.id is a text field!
		find_words   => [ analysis => 'title', 'comments' ],
		find_tags    => 'analysis',
		find_certids => [ 'ana.idstring' ],
	);

	my $where    = join "\n    AND ", @where;
	my $analyses = $self->{db}->query(<<__SEARCH_ANALYSES, @binds) or return;
 SELECT ana.id, ana.title, ana.comments AS description, ana.idstring,
        TO_CHAR(ana.orgdatetime, 'DD-MM-YYYY HH24:MI:SS:MS') AS date
   FROM analysis AS ana
  WHERE $where
__SEARCH_ANALYSES

	my @scored;
	while(my $analysis = $analyses->hash) {
		push @scored, $self->_score($search,
			type  => 'analysis',
			%$analysis,
			tags     => [ $self->_getTags(analysis => $analysis->{id}) ],
			cert_ids => [ split ' ', $analysis->{idstring} ],
		);
	}

	\@scored;
}

sub _searchAnyPublication($$%) {
	my ($self, $type, $search, %args) = @_;

	my $details       = $args{details_table} or confess;
	my @extra_fields  = @{$args{extra_fields}    || []};
	my $descr_field   = $args{description_field} || 'description';
	my @certid_fields = map "details.$_", @{$args{certid_fields} || []};

	my (@select, @where, @binds);
	push @select, map("details.$_", @extra_fields),
		'details.id  AS details_id',
		'pu.id       AS pub_id',
		'pu.contents AS extra_text',
		"TO_CHAR(pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS date",
		"TO_CHAR(pu.created_on, 'DD-MM-YYYY') AS created",
		"details.$descr_field AS description",
		;

	if($args{has_versions}) {
		push @select,
			'details.title    AS title',
			'details.version  AS version';
		push @where,
			'NOT deleted';
	} else {
		push @select,
			'pu.title         AS title';
	}

	$self->_addSearchFilters(\@where, \@binds, pu => $search->{publication});
	$self->_addSearchFilters(\@where, \@binds, details => $search->{$details});
	$self->_addSearchDate   (\@where, \@binds, $search, pu => 'created_on');

	$search->{scoring} = $self->_addSearchQuestion(
		\@where, \@binds, $search,
		select_field => 'details.id',
		find_words   => [ $details => $descr_field, @extra_fields ],
		find_words   => [ publication => 'contents' ],
		select_field => 'details.id::varchar',  # tag table id's are strings
		find_tags    => $details,
		find_certids => \@certid_fields,
	);

	my $select = join ', ', @select;
	my $where  = @where ? 'WHERE '.join(' AND ', @where) : '';

	my $publications = $self->{db}->query(<<__SEARCH_PUBL, @binds) or return;
 SELECT $select
   FROM $details AS details
		JOIN publication AS pu  ON details.publication_id = pu.id
  $where
__SEARCH_PUBL

	my @scored;

	while(my $pub = $publications->hash) {
		my $id = $pub->{id} = $pub->{pub_id};
		push @scored, $self->_score($search, 
			type   => $type,
			%$pub,
			tags   => [ $self->_getTags($details, $id) ],
		);
	}

	\@scored;
}

sub _searchAdvisories($%) {
	my ($self, $search, %args) = @_;

	my $type  = $args{type} or confess;
	my $table = $type eq 'advisory' ? 'publication_advisory'
	  : 'publication_advisory_forward';

	my $scored = $self->_searchAnyPublication($type => $search,
		details_table     => $table,
		has_versions      => 1,
		description_field => 'summary',
		extra_fields      => [ qw/govcertid ids/ ],
		certid_fields     => [ qw/govcertid ids/ ],
	);

	$scored;
}

sub _searchEndOfWeeks($%) {
	my ($self, $search, %args) = @_;

	$self->_searchAnyPublication(eow => $search,
		details_table     => 'publication_endofweek',
		description_field => 'introduction',
	);
}

sub _searchEndOfShifts($%) {
	my ($self, $search, %args) = @_;

	$self->_searchAnyPublication(eos => $search,
		details_table     => 'publication_endofshift',
		description_field => 'notes',
	);
}

sub _searchEndOfDays($%) {
	my ($self, $search, %args) = @_;

	$self->_searchAnyPublication(eod => $search,
		details_table     => 'publication_endofday',
		description_field => 'general_info',
	);
}

sub _evaluateQuestion($) {
	my ($self, $search_string) = @_;
	defined $search_string or return;

	# whitespace inside quoted strings also normalized
	s/\s+/ /g,s/^ //,s/ $//
		for $search_string;

	length $search_string
		or return;

	my %question = (
		search_string  => $search_string,
	);

	while($search_string =~ /\S/) {
		$search_string =~ s/^[ ]? ([+-])? (tag\:)? (?:"([^"]+)" | (\S*)) //xi;

		my $sign   = $1 || '';
		my $is_tag = !! $2;
		my $word   = $3 || $4;
		length $word or next;

		my $need
		  = $sign eq '-' ? 'excluded'
		  : $sign eq '+' ? 'required'
		  :                'bonus';
		$question{"has_$need"}++;

		my $group
		  = $is_tag                      ? 'tags'
		   : $self->_isIdentifier($word) ? 'certids'
		   :                               'words';
		$question{"has_$group"}++;

		push @{$question{"$need\_$group"}}, $word;
	}

	$question{has_words} || $question{has_tags} || $question{has_certids}
		or return;

	# Only excluded words/tags/ids is not allowed: too many results.
	if($question{has_excluded} && ! $question{has_required} && ! $question{has_bonus}) {
		$self->{errmsg} = "Cannot perform search with only excluded keywords.";
		return;
	}

	\%question;
}

sub _isIdentifier($) {
	my ($self, $word) = @_;
	$word =~ $self->{is_identifier};
}

sub _addSearchDate($$$$$) {
	my ($self, $where, $binds, $search, $prefix, $field) = @_;
	my $start = $search->{start_time};
	my $end   = $search->{end_time};
	$start || $end or return ();

	push @$where
	  , ! $end   ? "$prefix.$field >= '$start'"
	  : ! $start ? "$prefix.$field <= '$end'"
	  :            "$prefix.$field BETWEEN '$start' AND '$end'";
}

# See %search_groups in mod_search/meta_search.pl for restrictions on names.
#XXX This knowledge should be kept in the classes for each of the searchables:
# too fragile as it is implemented here.
sub _addSearchFilters($$$$) {
	my ($self, $where, $binds, $prefix, $prefs) = @_;
	$prefs or return ();

	foreach my $field (sort keys %$prefs) {
		my $content = $prefs->{$field};
		defined $content && length $content or next;
		next if $field =~ /^search/;  # skip group enabled flag

		if($content =~ /\D/) {
			push @$where, "$prefix.$field ILIKE ?";
			push @$binds, $content;
		} else {
			push @$where, "$prefix.$field = $content";
		}
	}
}

sub _addSearchQuestion($$$%) {
	my ($self, $where, $binds, $search, @rules) = @_;
	my $question = $search->{question};

	# When any of the sets has a required pattern, we only search for
	# those.  In that case, the bonus is just for scoring.  However,
	# when we only have bonus fields, we need to collect all objects
	# which match any of them.
	my $has_required = $question->{has_required};
	my $set = $has_required ? 'required' : 'bonus';

	# We need to split searches which use trigrams per table, otherwise the
	# index is not used.  Limitation at least till Postgresql 9.6.  This
	# implies that there can be more than one word search set.

	my $select_field;

	my @selects;
	my @pos_rules = @rules;
	while(@pos_rules) {
		my ($class, $config) = (shift @pos_rules, shift @pos_rules);

		if($class eq 'select_field') {
			$select_field = $config;
		} elsif($class eq 'find_words') {
			my ($table, @fields) = @$config;
			push @selects, $self->_wordFilterFind($binds,
				$question->{"${set}_words"},
				table    => $table,
				id_field => $select_field,
				columns  => \@fields,
			);
		} elsif($class eq 'find_tags') {
			my $table = $config;
			push @selects, $self->_tagFilterFind($binds,
				$question->{"${set}_tags"},
				table     => $table, id_field => $select_field,
				tag_group => $table,
			);
		} elsif($class eq 'find_certids_table') {
			push @selects, $self->_certidFilterFind($binds,
				$question->{"${set}_certids"},
				table    => $config,
				id_field => $select_field,
			);
		} elsif($class eq 'find_certids') {
			push @selects, $self->_certidFilterFieldsFind($binds,
				$question->{"${set}_certids"},
				fields => $config,
			);
		} else { confess $class }
	}

	if(@selects > 1 && ! $has_required) {
		# Postgresql 9.5 will seq go through all rows with
		#   SELECT * FROM item WHERE it.digest IN (@A) OR it.digest IN (@B)
		# eventhough there is an index on digest.  This also happens with
		#   SELECT * FROM item WHERE it.digest = ANY (@A UNION @B)
		# probably because the optimizer is confused about the index on the selected digest
		# column.  Solution found on internet:
		#   SELECT * FROM item WHERE it.digest = ANY(ARRAY(@A UNION @B))

		if(grep !/^it\.digest IN /, @selects) {
			# There is no such search at the moment, AFAIK.
			push @$where, '(' . join(' OR ', @selects). ')';
		} else {
			my @x = map s/^it\.digest IN //r, @selects;
			push @$where, 'it.digest = ANY(ARRAY(' . join(' UNION ', @x). '))'
		}
	} else {
		push @$where, @selects;
	}

	my @neg_rules = @rules;
	while(@neg_rules) {
		my ($class, $config) = (shift @neg_rules, shift @neg_rules);

		if($class eq 'select_field') {
			$select_field = $config;
		} elsif($class eq 'find_words') {
			my ($table, @fields) = @$config;
			push @$where, $self->_wordFilterBlock($binds,
				$question->{exclude_words},
				table    => $table,
				id_field => $select_field,
				columns  => \@fields,
			);
		} elsif($class eq 'find_tags') {
			my $table = $config;
			push @$where, $self->_tagFilterBlock($binds,
				$question->{exclude_tags},
				table     => $table,
				id_field  => $select_field,
				tag_group => $table,
			);
		} elsif($class eq 'find_certids_table') {
			push @$where, $self->_certidFilterBlock($binds,
				$question->{exclude_certids},
				table    => $config,
				id_field => $select_field,
			);
		} elsif($class eq 'find_certids') {
			push @$where, $self->_certidFilterFieldsBlock($binds,
				$question->{exclude_certids},
				fields => $config,
			);
		}
	}
}

### Word filter

sub _wordFilter($$$) {
	my ($self, $binds, $words, $args) = @_;
	$words && @$words or return undef;

	my $all_columns = $args->{columns} or confess;
	my $nr_columns  = @$all_columns;

	my @where;
	foreach my $word (@$words) {
		push @where, map "$_ ILIKE ?", @$all_columns;
		push @$binds, ("%${word}%") x $nr_columns;
	}
	my $where  = join ' OR ', @where;
	my $id     = $args->{id_field} =~ /\.(.*)/ ? $1 : confess;

	return <<__SELECT;
 SELECT $id
   FROM $args->{table}
  WHERE $where
__SELECT
}

sub _wordFilterFind($$%) {
	my ($self, $binds, $find, %args) = @_;
	my $positive = $self->_wordFilter($binds, $find, \%args);
	$positive ? "$args{id_field} IN (\n$positive)" : ();
}

sub _wordFilterBlock($$%) {
	my ($self, $binds, $block, %args) = @_;
	my $positive = $self->_wordFilter($binds, $block, \%args);
	$positive ? "$args{id_field} NOT IN (\n$positive)" : ();
}

### Tag filter

sub _tagFilter($$) {
	my ($self, $binds, $tags, $args) = @_;
	$tags && @$tags or return undef;

	my $where = join ' OR ', ("tag.name ILIKE ?") x @$tags;
	push @$binds, @$tags;

	my $group = $args->{tag_group} or confess;

	return <<__SELECT;
 SELECT ti.item_id
   FROM tag
        JOIN tag_item AS ti  ON ti.tag_id = tag.id
  WHERE ti.item_table_name = '$group'
    AND $where
__SELECT
}

sub _tagFilterFind($$%) {
	my ($self, $binds, $find, %args) = @_;
	my $positive = $self->_tagFilter($binds, $find, \%args);
	$positive ? "$args{id_field} IN (\n$positive)" : ();
}

sub _tagFilterBlock($$%) {
	my ($self, $binds, $block, %args) = @_;
	my $positive = $self->_tagFilter($binds, $block, \%args);
	$positive ? "$args{id_field} NOT IN (\n$positive)" : ();
}

### Cert-id filter via 'identifier' table (for assess items)

sub _certidFilter($$$) {
	my ($self, $binds, $cert_ids, $args) = @_;
	$cert_ids && @$cert_ids or return ();

	my $table   = $args->{table} or confess;
	my $certids = join "','", map uc, @$cert_ids;

	<<__SEARCH_IDENTIFIER;
 SELECT digest
   FROM $table
  WHERE UPPER(identifier) IN ('$certids')
__SEARCH_IDENTIFIER
}

sub _certidFilterFind($$%) {
	my ($self, $binds, $find, %args) = @_;
	my $positive = $self->_certidFilter($binds, $find, \%args);
	$positive ? "$args{id_field} IN (\n$positive)" : ();
}

sub _certidFilterBlock($$%) {
	my ($self, $binds, $block, %args) = @_;
	my $positive = $self->_certidFilter($binds, $block, \%args);
	$positive ? "$args{id_field} NOT IN (\n$positive)" : ();
}

### Cert-id filter on one or more fields

sub _certidFilterFields($$$) {
	my ($self, $binds, $cert_ids, $args) = @_;
	my $fields = $args->{fields};
	$fields && $cert_ids && @$cert_ids or return ();

	my @where;
	foreach my $field (@$fields) {
		foreach my $certid (@$cert_ids) {
			#XXX escape $certid?
			push @where, "$field ILIKE ?", "$field ILIKE ?";
			push @$binds, "%$certid %", "%$certid";
		}
	}
	'(' . join(' OR ', @where) . ')';
}

sub _certidFilterFieldsFind($$%) {
	my ($self, $binds, $find, %args) = @_;
	$self->_certidFilterFields($binds, $find, \%args);
}

sub _certidFilterFieldsBlock($$%) {
	my ($self, $binds, $block, %args) = @_;
	my $positive = $self->_certidFilterFields($binds, $block, \%args);
	$positive ? "NOT $positive" : ();
}

### Scoring

sub _score($%) {
	my ($self, $search, %scored) = @_;
	my $question = $search->{question};

	my $title  = $scored{title}       || '';
	my $descr  = $scored{description} || '';
	my $extra  = $scored{extra_text}  || '';
	my $dbdate = $scored{date};

	my $log    = "";
	my $score  = 0;

	### each keyword and +keyword in title and/or description

	my ($all_words_in_title, $all_words_in_descr) = (1, 1);
	my $nr_words = 0;

	foreach my $key (qw/required_words bonus_words/) {
		my @words = @{$question->{$key} || []};
		@words or next;

		$nr_words += @words;
		my ($nr_in_title, $nr_in_descr, $nr_in_extra) = (0, 0, 0);

		foreach my $pattern (map qr/(\Q$_\E)/i, @words) {
			$nr_in_title += () = $title =~ /$pattern/g;
			$nr_in_descr += () = $descr =~ /$pattern/g;
			$nr_in_extra += () = $extra =~ /$pattern/g;

			$all_words_in_title = 0 if $title !~ $pattern;
			$all_words_in_descr = 0 if $descr !~ $pattern;
		}

		my $weights = $word_scores_table{$key};
		$score += $nr_in_title * $weights->{in_title};
		$score += $nr_in_descr * $weights->{in_text};
		$score += $nr_in_extra * $weights->{in_extra};

		$log   .= "+ $nr_in_title * $weights->{in_title} --> $key in title\n"
		       .  "+ $nr_in_descr * $weights->{in_text}  --> $key in descr\n"
		       .  "+ $nr_in_extra * $weights->{in_extra} --> $key in extra\n";
	}

	if($nr_words && $all_words_in_title) {
		$score += $score_all_words_in_title;
		$log   .= "+ $score_all_words_in_title all keywords in title\n";
	}

	if($nr_words && $all_words_in_descr) {
		$score += $score_all_words_in_descr;
		$log   .= "+ $score_all_words_in_descr all keywords in description\n";
	}

	# Exact match words

	if(   !$question->{has_tags}      # confusing
	   && !$question->{has_excluded}  # useless
	   && @{$question->{words} || []} + @{$question->{certids} || []} >= 2
	) {

		# To match the exact string, we need the words in their original order.
		my $words = quotemeta $question->{search_string};

		# Blanks are replaced by any sequence of non-word chars
		$words    =~ s/\s+/\\W+/g;

		if($title =~ /\b$words\b/i) {
			$score += $score_title_exact_match;
			$log   .= "+ $score_title_exact_match exact match title\n";
		}

		if($descr =~ /\b$words\b/i) {
			$score += $score_descr_exact_match;
			$log   .= "+ $score_descr_exact_match exact match description\n";
		}
	}

	### score tags

	my @matched_tags;

	my $has_tags = $scored{tags} || [];
	if(@$has_tags) {
		my %has_tag = map +($_ => 1), @$has_tags;

		my $required_tags = $question->{required_tags} || [];
		foreach my $tag (grep $has_tag{$_}, @$required_tags) {
			$score += $score_required_tag;
			$log   .= "+ $score_required_tag required tag '$tag'\n";
			push @matched_tags, $tag;
		}

		my $bonus_tags = $question->{bonus_tags} || [];
		foreach my $tag (grep $has_tag{$_}, @$bonus_tags) {
			$score += $score_bonus_tag;
			$log   .= "+ $score_bonus_tag bonus tag '$tag'\n";
			push @matched_tags, $tag;
		}
	}

	### score certid's

	my $has_certids = $scored{cert_ids} || [];
	if(@$has_certids) {
		my %has_certid = map +($_ => 1), @$has_certids;

		my $required_certids = $question->{required_certids} || [];
		if(my $hits = grep $has_certid{$_}, @$required_certids) {
			$score += $hits * $score_required_certid;
			$log   .= "+ $hits * $score_required_certid required certids\n";
		}

		my $bonus_certids = $question->{bonus_certids} || [];
		if(my $hits = grep $has_certid{$_}, @$bonus_certids) {
			$score += $hits * $score_bonus_certid;
			$log   .= "+ $hits * $score_bonus_certid bonus certids\n";
		}
	}

	# The newest get preference.
	# This is also needed to avoid double scores: the result hash does
	# not like that...

	use bignum;
	$dbdate =~ m/(..).(..).(....).(..).(..).(..).(..)/;
	my $date   = "$3$2$1$4$5$6$7";
	$score    += $date / 10_000_000_000_000_000;
	$log      .= '+ ' . ($date / 10_000_000_000_000_000) . " timestamp\n";
	no bignum;

	$self->{log}->("$scored{type} score: $score - $scored{title} =\n$log");

	# Adding to the output
	$scored{matched_tags} = \@matched_tags;
	$scored{score}        = $score;
	\%scored;
}

sub _sortScores(@) {
	my $self = shift;
	[ sort { $b->{score} <=> $a->{score} } @_ ];
}

sub getDistinctSources() {
	my $self = shift;

	return $self->{db}->query(<<'__SOURCES')->list;
 SELECT DISTINCT(sourcename)
   FROM sources
  ORDER BY sourcename
__SOURCES
}

1;
