# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::MetaSearch;

use Taranis qw(:all);
use Taranis::Database;
use Taranis::FunctionalWrapper qw(Database Sql);
use Taranis::Config::XMLGeneric;
use Taranis::Config;
use SQL::Abstract::More;
use strict;
use Tie::IxHash;

sub new {
	my ( $class, $config ) = @_;
	
	my $identifiersConfig = $config ? $config->{identifiersconfig}
		: Taranis::Config->getSetting('identifiersconfig');
	
	my $self = {
		errmsg 	 => undef,
		keywords => undef,
		logScore => 0, # 1 = on, 0 = off (logs the score for each result found, (including results which are not displayed)!)
		dbh => Database,
		sql => Sql,
		identifiersConfig => $identifiersConfig
	};
	
	return( bless( $self, $class ) );
}

sub search {
	my ( $self, $searchSettings, $dbSettings ) = @_;
	undef $self->{errmsg};

	my ( @items, @analysis, @advisories, @eow, @eos, @eod );

	my @negative_ids = @{ $searchSettings->{negative_ids} };
	my @positive_ids = @{ $searchSettings->{positive_ids} };
	my @all_ids = @{ $searchSettings->{all_ids} };
	
	my $not_id = $searchSettings->{not_id};
	my $id_string = $searchSettings->{idstring};
	
	my %search_string_collection = %{ $searchSettings->{search_string_collection} };
	
	my %keywords = %{ $searchSettings->{keywords} };
	my %tags = %{ $searchSettings->{tags} };
	
	my ( $startDate, $endDate );

	if ( exists( $dbSettings->{startDate} )	&& $dbSettings->{startDate} ) {
		$startDate = formatDateTimeString( $dbSettings->{startDate} );
	}
	
	if ( exists( $dbSettings->{endDate} ) && $dbSettings->{endDate} ) {
		$endDate = formatDateTimeString( $dbSettings->{endDate} );
	}
	
#### search Assess ####

# search table item(_archive), identifier(_archive) and email_item(_archive)

	if ( exists( $dbSettings->{item} ) ) {

		my $searchArchive = delete $dbSettings->{item}->{archive};
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{item} } ) {
			if ( $dbSettings->{item}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{item}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{item}->{$setting} );
			}
		}
		
		if ( $startDate && $endDate ) {
			$where{created} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{created} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{created} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $item_where, @bind ) = $self->{sql}->where(\%where);
		
		$item_where =~ s/WHERE(.*)/$1/;
		
		my @item_columns = ( 'title', 'description', 'body' );
	
		my %tables = ( current => { 
			item => 'item',
			email => 'email_item',
			identifier => 'identifier'
		});

		$tables{archive}  = { 
			item => 'item_archive',
			email => 'email_item_archive',
			identifier => 'identifier_archive'
		} if ( $searchArchive );

		foreach my $table ( keys %tables ) {
			my $itemTable = $tables{$table}->{item};
			my $emailTable = $tables{$table}->{email};
			my $identifierTable = $tables{$table}->{identifier};

			my $item_select =  "$itemTable.digest, title, description, to_char(created, 'DD-MM-YYYY HH24:MI:SS:MS') AS item_date, body AS extra_column";
		
			my $item_join = { "LEFT JOIN $emailTable AS ei" => { "ei.digest" => "$itemTable.digest" } };
		
			if ( !@negative_ids && ( @all_ids ) ) {
				$item_join->{ "LEFT JOIN $identifierTable AS i" } = { "i.digest" => "$itemTable.digest" };
				push @item_columns, "identifier";
			}
		
			my ( $item_stmnt, @item_bind ) = $self->_createWhereForSearch(
				"$itemTable", 
				"digest", 
				$item_select, 
				\@item_columns, 
				\%tags, 
				\%keywords,
				$item_join,
				$item_where
			);
			unshift @item_bind, @bind;
			
			my @collection = $self->collect( $item_stmnt, \@item_bind );

			for ( my $i = 0; $i < @collection; $i++ ) {
				if ( $table =~ /^archive$/ ) {
					$collection[$i]->{is_archived} = 1; 
				} else {
					$collection[$i]->{is_archived} = 0;
				}
			}
			
			push @items, @collection if ( scalar @collection ) ;
			
# include this search when there are more than one +identifiers given as keywords	
# --> NOTE this only works correct with a limit on +keywords of three

			if ( scalar( @positive_ids ) > 1 ) {
				my @identifier_bind;
				my $identifier_stmnt;
				my $identifier_select = "$itemTable.digest, title, description, to_char(created, 'DD-MM-YYYY HH24:MI:SS:MS') AS item_date";
				
				for ( my $i = 0; $i < @positive_ids; $i++ ) {
					my ( $stmnt_part, @bind_part ) = $self->{sql}->select( "$identifierTable", "digest", { 'upper(identifier)' => uc( $positive_ids[$i] ) } );						
					my $operator = ( $i != 0 ) ? "AND" : "";
					$identifier_stmnt .= " $operator $itemTable.digest IN ( " . $stmnt_part . " ) ";
					push @identifier_bind, @bind_part;
				}
		
				my $stmnt = "";
				if ( $not_id ) {
		
					push @identifier_bind, $not_id;
					my @temp_bind = @identifier_bind;
		
					my @columns = ( 'title', 'description', 'body' );
					my $operator = "OR";
		
					foreach my $column ( @columns ) {
						if ( $columns[-1] ne $column ) {
							$operator = "OR";
							push @identifier_bind, @temp_bind;
						} else {
							$operator = "";
						}
						
						$stmnt .= " ( " . $identifier_stmnt . " AND $column ilike ? ) $operator ";
					}
				}

				$stmnt = $identifier_stmnt if ( !$stmnt );

				my $identifier_join = { "LEFT JOIN $emailTable AS ei" => { "ei.digest" => "$itemTable.digest" } };
				
				my @identifier_columns = ( 'title', 'description', 'body' );
				
				my %identifier_keywords = ( negative_words => $keywords{negative_words} ) if ( $keywords{negative_words} ) ;
				my $operator = ( $keywords{negative_words} || scalar( %tags ) ) ? "AND" : "WHERE" ;
				
				my ( $identifier_stmnt2, @identifier_bind2 ) = $self->_createWhereForSearch(
					"$itemTable", 
					"digest", 
					$identifier_select, 
					\@identifier_columns, 
					\%tags, 
					\%identifier_keywords,
					$identifier_join
				);
				$stmnt = $identifier_stmnt2 . " $operator ( " . $stmnt . " ) ";
				unshift @identifier_bind, @identifier_bind2;

				my @identifier_collection = $self->collect( $stmnt, \@identifier_bind );
				
				for ( my $i = 0; $i < @identifier_collection; $i++ ) {
					if ( $table =~ /^archive$/ ) {
						$identifier_collection[$i]->{is_archived} = 1; 
					} else {
						$identifier_collection[$i]->{is_archived} = 0;
					}
				}
				
				push @items, @identifier_collection if ( scalar @identifier_collection ) ;		
			}
		}
	}
	
#### search Analyze ####

# search table analysis

	if ( exists( $dbSettings->{analyze} ) ) {

		delete $dbSettings->{analyze}->{searchAnalyze};
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{analyze} } ) {
			if ( $dbSettings->{analyze}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{analyze}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{analyze}->{$setting} );
			}
		}

		if ( $startDate && $endDate ) {
			$where{orgdatetime} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{orgdatetime} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{orgdatetime} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $analyze_where, @bind ) = $self->{sql}->where(\%where);
		
		$analyze_where =~ s/WHERE(.*)/$1/;

		my @analysis_columns = ( 'title', 'comments', 'idstring' );
		
		my $analysis_select = "analysis.id, to_char( orgdatetime, 'DD-MM-YYYY HH24:MI:SS:MS') AS analysis_date, title, comments, idstring AS extra_column";
		
		my ( $analysis_stmnt, @analysis_bind ) = $self->_createWhereForSearch(
			"analysis", 
			"id", 
			$analysis_select, 
			\@analysis_columns, 
			\%tags, 
			\%keywords,
			{},
			$analyze_where
		);

		unshift @analysis_bind, @bind;
		
		@analysis = $self->collect( $analysis_stmnt, \@analysis_bind );
	}
	
#### search Write ####

	my $searchAllProducts = ( exists( $dbSettings->{publication} ) && $dbSettings->{publication}->{searchAllProducts} ) ? 1 : 0;
	my $searchAdvisory = ( exists( $dbSettings->{publication} ) && $dbSettings->{publication_advisory}->{searchAdvisory} ) ? 1 : 0;
	my $searchEndOfWeek = ( exists( $dbSettings->{publication} ) && $dbSettings->{publication_endofweek}->{searchEndOfWeek} ) ? 1 : 0;
	my $searchEndOfShift = ( exists( $dbSettings->{publication} ) && $dbSettings->{publication_endofshift}->{searchEndOfShift} ) ? 1 : 0;
	my $searchEndOfDay = ( exists( $dbSettings->{publication} ) && $dbSettings->{publication_endofday}->{searchEndOfDay} ) ? 1 : 0;
		
	delete $dbSettings->{publication}->{searchAllProducts} if ( exists( $dbSettings->{publication}->{searchAllProducts} ) );
	delete $dbSettings->{publication_advisory}->{searchAdvisory} if ( exists( $dbSettings->{publication_advisory}->{searchAdvisory} ) );
	delete $dbSettings->{publication_endofweek}->{searchEndOfWeek} if ( exists( $dbSettings->{publication_endofweek}->{searchEndOfWeek} ) );
	delete $dbSettings->{publication_endofshift}->{searchEndOfShift} if ( exists( $dbSettings->{publication_endofshift}->{searchEndOfShift} ) );
	delete $dbSettings->{publication_endofday}->{searchEndOfDay} if ( exists( $dbSettings->{publication_endofday}->{searchEndOfDay} ) );
	
# search publication_advisory && publication_advisory_forward

	if ( $searchAllProducts || $searchAdvisory ) {
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{publication} } ) {
			if ( $dbSettings->{publication}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication}->{$setting} );
			}
		}

		foreach my $setting ( keys %{ $dbSettings->{publication_advisory} } ) {
			if ( $dbSettings->{publication_advisory}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication_advisory}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication_advisory}->{$setting} );
			}
		}

		$where{deleted} = 'f';

		if ( $startDate && $endDate ) {
			$where{created_on} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{created_on} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{created_on} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $advisory_where, @bind ) = $self->{sql}->where(\%where);
		
		$advisory_where =~ s/WHERE(.*)/$1/;

		# do search in publication_advisory
		{
			my $advisory_select = "publication_advisory.id, govcertid, version, publication_advisory.publication_id AS pub_id, publication_advisory.title AS adv_title, summary, to_char( pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS advisory_date, ids || ' ' || govcertid AS extra_column, pu.contents AS contents";
			
			my $advisory_join = { "JOIN publication AS pu" => { "pu.id" => "publication_advisory.publication_id" } };
				
			my @advisory_columns = ( "publication_advisory.title", "publication_advisory.govcertid", "publication_advisory.ids", "pu.contents" );
			my ( $advisory_stmnt, @advisory_bind ) = $self->_createWhereForSearch(
				"publication_advisory", 
				"id::varchar", 
				$advisory_select, 
				\@advisory_columns, 
				\%tags, 
				\%keywords,
				$advisory_join,
				$advisory_where
			);
	
			unshift @advisory_bind, @bind;
				
			@advisories = $self->collect( $advisory_stmnt, \@advisory_bind );
		}
		
		# do search in publication_advisory_forward
		{
			my $advisoryForwardSelect = "publication_advisory_forward.id, govcertid, version, publication_advisory_forward.publication_id AS pub_id, publication_advisory_forward.title AS adv_title, summary, source, to_char( pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS advisory_date, ids || ' ' || govcertid AS extra_column, pu.contents AS contents";
			
			my $advisoryForwardJoin = { "JOIN publication AS pu" => { "pu.id" => "publication_advisory_forward.publication_id" } };
				
			my @advisoryForwardColumns = ( "publication_advisory_forward.title", "publication_advisory_forward.govcertid", "publication_advisory_forward.ids", "pu.contents" );
			my ( $advisoryForwardStmnt, @advisoryForwardBind ) = $self->_createWhereForSearch(
				"publication_advisory_forward",
				"id::varchar",
				$advisoryForwardSelect,
				\@advisoryForwardColumns,
				\%tags, 
				\%keywords,
				$advisoryForwardJoin,
				$advisory_where
			);
	
			unshift @advisoryForwardBind, @bind;
			
			my @advisoriesForward = $self->collect( $advisoryForwardStmnt, \@advisoryForwardBind );
			push @advisories, @advisoriesForward if ( @advisoriesForward );
		}
	}

# search publication_endofweek	

	if ( $searchAllProducts || $searchEndOfWeek ) {
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{publication} } ) {
			if ( $dbSettings->{publication}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication}->{$setting} );
			}
		}

		foreach my $setting ( keys %{ $dbSettings->{publication_endofweek} } ) {
			if ( $dbSettings->{publication_endofweek}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication_endofweek}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication_endofweek}->{$setting} );
			}
		}

		if ( $startDate && $endDate ) {
			$where{created_on} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{created_on} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{created_on} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $eow_where, @bind ) = $self->{sql}->where(\%where);
		
		$eow_where =~ s/WHERE(.*)/$1/;

		my $eow_select = "publication_endofweek.id, publication_endofweek.publication_id AS pub_id, pu.title AS eow_title, introduction, to_char( pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS eow_date, to_char( pu.created_on, 'DD-MM-YYYY') AS eow_created, pu.contents AS contents";
	
		my $eow_join = { "JOIN publication AS pu" => { "pu.id" => "publication_endofweek.publication_id" } };
		
		my @eow_columns = ( 'pu.contents' );
		my ( $eow_stmnt, @eow_bind ) = $self->_createWhereForSearch(
			"publication_endofweek", 
			"id::varchar", 
			$eow_select, 
			\@eow_columns, 
			\%tags, 
			\%keywords,
			$eow_join,
			$eow_where
		 );	
		
		unshift @eow_bind, @bind;

		@eow = $self->collect( $eow_stmnt, \@eow_bind );
	}

# search publication_endofshift

	if ( $searchAllProducts || $searchEndOfShift ) {
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{publication} } ) {
			if ( $dbSettings->{publication}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication}->{$setting} );
			}
		}

		foreach my $setting ( keys %{ $dbSettings->{publication_endofshift} } ) {
			if ( $dbSettings->{publication_endofshift}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication_endofshift}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication_endofshift}->{$setting} );
			}
		}

		if ( $startDate && $endDate ) {
			$where{created_on} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{created_on} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{created_on} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $eos_where, @bind ) = $self->{sql}->where(\%where);
		
		$eos_where =~ s/WHERE(.*)/$1/;

		my $eos_select = "publication_endofshift.id, publication_endofshift.publication_id AS pub_id, pu.title AS eos_title, notes, to_char( pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS eos_date, to_char( pu.created_on, 'DD-MM-YYYY') AS eos_created, pu.contents AS contents";
	
		my $eos_join = { "JOIN publication AS pu" => { "pu.id" => "publication_endofshift.publication_id" } };
		
		my @eos_columns = ( 'pu.contents' );
		my ( $eos_stmnt, @eos_bind ) = $self->_createWhereForSearch(
			"publication_endofshift", 
			"id::varchar", 
			$eos_select, 
			\@eos_columns, 
			\%tags, 
			\%keywords,
			$eos_join,
			$eos_where
		);	
		
		unshift @eos_bind, @bind;

		@eos = $self->collect( $eos_stmnt, \@eos_bind );
	}

	if ( $searchAllProducts || $searchEndOfDay ) {
		
		my %where;
		foreach my $setting ( keys %{ $dbSettings->{publication} } ) {
			if ( $dbSettings->{publication}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication}->{$setting} );
			}
		}

		foreach my $setting ( keys %{ $dbSettings->{publication_endofday} } ) {
			if ( $dbSettings->{publication_endofday}->{$setting} =~ /^\d+$/ ) {
				$where{$setting} = $dbSettings->{publication_endofday}->{$setting};	
			} else {
				$where{"upper($setting)"} = uc( $dbSettings->{publication_endofday}->{$setting} );
			}
		}

		if ( $startDate && $endDate ) {
			$where{created_on} = {-between => [$startDate." 000000", $endDate." 235959"] };
		} elsif ( $startDate ) {
			$where{created_on} = { '>=' => $startDate . ' 000000'};
		} elsif ( $endDate ) {
			$where{created_on} = { '<=' => $endDate . ' 235959'};
		}
		
		my ( $eod_where, @bind ) = $self->{sql}->where(\%where);
		
		$eod_where =~ s/WHERE(.*)/$1/;

		my $eod_select = "publication_endofday.id, publication_endofday.publication_id AS pub_id, pu.title AS eod_title, general_info, to_char( pu.published_on, 'DD-MM-YYYY HH24:MI:SS:MS') AS eod_date, to_char( pu.created_on, 'DD-MM-YYYY') AS eod_created, pu.contents AS contents";
	
		my $eod_join = { "JOIN publication AS pu" => { "pu.id" => "publication_endofday.publication_id" } };
		
		my @eod_columns = ( 'pu.contents' );
		my ( $eod_stmnt, @eod_bind ) = $self->_createWhereForSearch(
			"publication_endofday", 
			"id::varchar", 
			$eod_select, 
			\@eod_columns, 
			\%tags, 
			\%keywords,
			$eod_join,
			$eod_where
		);	
		
		unshift @eod_bind, @bind;

		@eod = $self->collect( $eod_stmnt, \@eod_bind );
	}

	return $self->_formatResults( 
		search_collection => \%search_string_collection,
		ids => $id_string,
		items => \@items,
		analysis => \@analysis, 
		advisories => \@advisories,
		eow => \@eow,
		eos => \@eos,
		eod => \@eod
	);
}

sub dissectSearchString {
	my ( $self, $search_string ) = @_;
	undef $self->{keywords};
	
	my $orignal_string = $search_string;

	$search_string =~ s/&quot;/"/gi;
	$search_string =~ s/(\s+)\+(\s+)/$1/gi; # deletes the plus sign when it's not preceded and followed by another character
	$search_string =~ s/(\s+)-(\s+)/$1/gi; # see plus sign deletion above but for minus
			
	my ( @positive_words, @negative_words,	@optional_words,
		@positive_tags, @negative_tags, @optional_tags,
		@quoted_words, @all_ids, @positive_ids, @negative_ids 
	);

	my ( $not_id, $id_string );
	
	my %search_string_collection;

	$search_string_collection{search_string} = $orignal_string;

	# extract tag:keywords
	foreach my $word ( $search_string =~ /([+-]?tag:(")?.*?(?(2)"))(?:\s|\z)/gi ) {
		next if ( !$word || $word eq "\"" ); # ignore capture $2
		
		my $del_word = $word;
		$del_word =~ s/\+/\\+/;
		$search_string =~ s/\Q$del_word\E//gi;
		
		if ( $word =~ s/^\+tag:"?(.*?)"?$/$1/i ) {
#			push @positive_tags, "%" . $word . "%";
			push @positive_tags, $word;
		} elsif ( $word =~ s/^-tag:"?(.*?)"?$/$1/i ) {
#			push @negative_tags, "%" . $word . "%";
			push @negative_tags, $word;
		} else {
			$word =~ s/^tag:"?(.*?)"?$/$1/i;
#			push @optional_tags, "%" . $word . "%";
			push @optional_tags, $word;
		}
	}
	
	# extract "quoted keywords"
	foreach my $word ( $search_string =~ /([+-]?".*?")/gi ) {
		# remove the quoted words from searchstring
		my $del_word = $word;
		$del_word =~ s/\+/\\+/;
		$search_string =~ s/\Q$del_word\E//gi;

		$word =~ s/"//g;
		push @quoted_words, $word;
	}
	
	# create lists of all keywords and add % to every word for SQL search
	foreach my $word ( split( " ", $search_string ), @quoted_words ) {
		if ( $word =~ s/^\+// ) {
			push @{ $self->{keywords} }, $word;
			push @positive_words, "%" . trim($word) . "%";
		} elsif ( $word =~ s/^-//) {
			push @negative_words, "%" . trim($word) . "%";
		} else {
			push @{ $self->{keywords} }, $word;
			push @optional_words, "%" . trim($word) . "%";
		}
	}
	
	# searches with only negative words or tags is not allowed
	if ( ( scalar( @negative_words ) || scalar( @negative_tags ) ) 
		&& !scalar( @positive_words ) 
		&& !scalar( @optional_words )
		&& !scalar( @positive_tags )
		&& !scalar( @optional_tags ) 
	) {
		$self->{errmsg} = "Cannot perform search with only negative keywords.";
		return 0;
	}

	if ( scalar( @positive_words ) > 3 ) {
		$self->{errmsg} = "Cannot perform search with more than three +keywords.";
		return 0;
	}

	@{ $search_string_collection{positive_words} } = @positive_words; 
	@{ $search_string_collection{optional_words} } = @optional_words;
		
	@{ $search_string_collection{positive_tags} } = @positive_tags;
	@{ $search_string_collection{optional_tags} } = @optional_tags;

	if ( @positive_words || @optional_words ) {
		my $ip = Taranis::Config::XMLGeneric->new( $self->{identifiersConfig}, "idname", "ids");
		my $id_patterns = $ip->loadCollection();
		
		if ( @positive_words ) {
			my @words = @positive_words;
			WORD:foreach my $word ( @words ) {
				PATTERN:foreach my $pattern ( @$id_patterns ) {
					$word =~ s/%//g;
		
					if ( $word =~ /$pattern->{pattern}/i ) {
						push @positive_ids, $word;
						next WORD;
					} else {
						$not_id = "%" . trim($word) . "%";
					}
				}
			}
		}
		
		if ( @optional_words ) {
			my @words = @optional_words;
			WORD:foreach my $word ( @words ) {
				PATTERN:foreach my $pattern ( @$id_patterns ) {
					$word =~ s/%//g;
		
					if ( $word =~ /$pattern->{pattern}/i ) {
						push @all_ids, $word;
						next WORD;
					} 
				}
			}
		}

		if ( @negative_words ) {
			my @words = @negative_words;
			WORD:foreach my $word ( @words ) {
				PATTERN:foreach my $pattern ( @$id_patterns ) {
					$word =~ s/%//g;
		
					if ( $word =~ /$pattern->{pattern}/i ) {
						push @negative_ids, $word;
						next WORD;
					} 
				}
			}
		}		

#TODO: idstring ook vullen indien er in archive wordt gezocht 
		push @all_ids, @positive_ids if ( @positive_ids );
		if ( @all_ids ) {
			
			foreach ( @all_ids ) { $_ = uc( $_ ) } 
			
			my ( $ids_stmnt, @ids_bind ) = $self->{sql}->select( "identifier", "digest", { 'upper(identifier)' => \@all_ids } );

			$self->{dbh}->prepare( $ids_stmnt );
			$self->{dbh}->executeWithBinds( @ids_bind );

			while ( $self->nextObject() ) {
				my $digest = $self->getObject()->{digest};
				$id_string .= $digest . " ";
			}
		}
	}
	
	# when there are positive words and optional tags, the search must be done without the optional tags
	# the optional tags will then be used for sorting the results
	if ( scalar( @positive_words ) ) {
		undef @optional_tags if ( scalar( @optional_tags) );
	}

	# when there are positive tags and optional words, the search must be done without the optional words
	# the optional words will then be used for sorting the results
	if ( scalar( @positive_tags ) ) {
		undef @optional_words if ( scalar( @optional_words) );
	}	
	
	my %keywords;
	$keywords{positive_words} = \@positive_words if ( scalar( @positive_words ) );
	$keywords{optional_words} = \@optional_words if ( scalar( @optional_words ) );
	$keywords{negative_words} = \@negative_words if ( scalar( @negative_words ) ); 
	
	my %tags;
	$tags{positive_tags} = \@positive_tags if ( scalar( @positive_tags ) );
	$tags{optional_tags} = \@optional_tags if ( scalar( @optional_tags ) );
	$tags{negative_tags} = \@negative_tags if ( scalar( @negative_tags ) ); 
	
	my $return_collection;
	
	$return_collection->{keywords} = \%keywords;
	$return_collection->{tags} = \%tags;
	$return_collection->{not_id} = $not_id;
	$return_collection->{idstring} = $id_string;
	$return_collection->{negative_ids} = \@negative_ids;
	$return_collection->{positive_ids} = \@positive_ids;
	$return_collection->{all_ids} = \@all_ids;
	$return_collection->{search_string_collection} = \%search_string_collection;
	
	return $return_collection;
}

sub _createWhereForSearch {
	my ( $self, $table, $selection_id, $select, $columns, $tags, $keywords, $join, $extra_where ) = @_;

	my $where;
	my @where_part_negative;
	
	if ( exists $keywords->{negative_words} ) {
			push @where_part_negative, -and => { -not_ilike => $keywords->{negative_words}->[0] };

		if ( scalar( @{ $keywords->{negative_words} } ) > 1 ) {
			for ( my $i = 1; $i < @{ $keywords->{negative_words} }; $i++ ) {
					push @where_part_negative, { -not_ilike => $keywords->{negative_words}->[$i] };
			}
		}
		
		foreach my $column ( @$columns ) {
			if ( $column =~ /^body$/i ) { 	# exception for column body of table email_item
				my @body_where = @where_part_negative;
				my $is_null = "IS NULL";
				
				for ( my $i = 1; $i < @body_where; $i++ ) {
					$body_where[$i] = [ $body_where[$i], \$is_null ];
				}
				$where->{$column} = \@body_where;

			} else {
				$where->{$column} = \@where_part_negative;	
			}
		}
	}

	if ( exists $keywords->{positive_words} ) {
		my @positive_words = @{ $keywords->{positive_words} };

		my $prev_keyword = "";
		my $str = "";
		
		my ( $i, $j, $k );
		my ( @combination, @all_occurences, @all_combinations );
		
		COMBINATION:for ( $i = 0  ; $i < ( @$columns ** @positive_words ) ; $i++ ) {
		
			KEYWORD:for ( $k = 0 ; $k < @positive_words; $k++ ) {
		
				COLUMN:for ( $j = 0 ; $j < @$columns; $j++ ) {		
					
					if ( $positive_words[$k] eq $prev_keyword ) {
						next KEYWORD;
					}
		
					my $new_combination = $str . $columns->[$j] . $positive_words[$k] . " ";
					if ( scalar( grep( /^$new_combination$/, @all_occurences ) ) ) {
						next COLUMN;
					}
		
					$str .= $columns->[$j] . $positive_words[$k] . " ";
					
					push @combination, {  $columns->[$j] => { -ilike => $positive_words[$k] } };
					$prev_keyword = $positive_words[$k];
				}
			}
		
		
			if ( scalar( @combination ) != scalar( @positive_words ) ) {
				push @all_occurences, $str;
		
				undef @combination;
				$prev_keyword = "";
				$str = "";
				goto KEYWORD;
			}
			
			push @all_occurences, $str;
			push @all_combinations, -and => [ @combination ];
			undef @combination;	
			$prev_keyword = "";
			$str = "";
		}
	
		$where->{-nest} = \@all_combinations;	

	} elsif ( exists $keywords->{optional_words} ) {
		foreach my $column ( @$columns ) {
			push @{ $where->{-or} },  $column => { -ilike => \@{ $keywords->{optional_words } } };
		}
	}

	my %where_tags;

	my ( $tags_stmnt, $stmnt );
	my ( @tags_bind, @bind );		

	tie my %tags_join, "Tie::IxHash";
	%tags_join = (
		"JOIN tag_item ti" => { "ti.item_id" => "$table.$selection_id" },
		"JOIN tag t" => { "t.id" => "ti.tag_id"}
	);

	if ( exists $tags->{positive_tags} ) {
		
		my @where_tags_positive;

		my %tags_where = ( name => { -ilike => $tags->{positive_tags}->[0] } );	
		( $tags_stmnt, @tags_bind ) = $self->{sql}->select( $table, "$table.$selection_id", \%tags_where );
		
		my $operator = ( $where || $extra_where ) ? "AND" : "";

		$tags_stmnt = " $operator $table.$selection_id IN ( " . $self->{dbh}->sqlJoin( \%tags_join, $tags_stmnt ) . " ) ";
		
		if ( scalar( @{ $tags->{positive_tags} } ) > 1 ) {
			
			for ( my $i = 1; $i < @{ $tags->{positive_tags} }; $i++ ) {
				
				my @positive_tags_bind;
				my $positive_tags_stmnt;
				
				%tags_where = ( name => { -ilike => $tags->{positive_tags}->[$i] } );	
				( $positive_tags_stmnt, @positive_tags_bind ) = $self->{sql}->select( $table, "$table.$selection_id", \%tags_where );
		
				$tags_stmnt .= " AND $table.$selection_id IN ( " . $self->{dbh}->sqlJoin( \%tags_join, $positive_tags_stmnt ) . " ) ";
				push @tags_bind, @positive_tags_bind;
			}
		}
		
		$tags_stmnt = $tags_stmnt . " ) " if ( exists( $tags->{negative_tags} ) ) ;
		
	} elsif ( exists $tags->{optional_tags} ) {
		my @where_tags_optional;
		push @where_tags_optional, name => { -ilike => \@{  $tags->{optional_tags} } };

		( $tags_stmnt, @tags_bind ) = $self->{sql}->select( $table, "$table.$selection_id", \@where_tags_optional );
		my $operator = ( exists( $keywords->{negative_words} ) ) ? "AND" : "OR";

		$tags_stmnt = " $operator $table.$selection_id IN ( " . $self->{dbh}->sqlJoin( \%tags_join, $tags_stmnt ) . " ) ";
		$tags_stmnt .=  " ) " if ( exists( $tags->{negative_tags} ) ) ;
	}
	
	if ( exists $tags->{negative_tags} ) {
		my @temp_binds;	
		my $temp_save = $tags_stmnt if ( $tags_stmnt );
		
		my @tags_where = ( name => { -ilike => \@{ $tags->{negative_tags} } } );
		( $tags_stmnt, @temp_binds ) = $self->{sql}->select( $table, "$table.$selection_id", \@tags_where );
		
		$tags_stmnt = " AND $table.$selection_id NOT IN ( " . $self->{dbh}->sqlJoin( \%tags_join, $tags_stmnt ) . " ) ";
		$tags_stmnt =  $temp_save . $tags_stmnt if ( $temp_save );
 
 		push @tags_bind, @temp_binds;
	}	

	if ( $where ) {
		( $stmnt, @bind ) = $self->{sql}->select( $table, $select, $where );
		$stmnt =~ s/^(.*?)WHERE(.*)/$1 WHERE \( $2/ 
			if ( exists( $tags->{negative_tags} ) &&  ( exists( $tags->{optional_tags} ) || exists( $tags->{positive_tags} ) ) );
	} else {
		( $stmnt, @bind ) = $self->{sql}->select( $table, $select );
		$tags_stmnt =~ s/^.*?($table\.$selection_id.*)/ WHERE $1/;
	}	

	if ( $join ) {
		$stmnt = $self->{dbh}->sqlJoin( $join, $stmnt );
	}

	$stmnt = $stmnt . $tags_stmnt if ( $tags_stmnt );

	$stmnt =~ s/^(.*?)WHERE(.*)/$1 WHERE \( $2/ 
		if ( exists( $tags->{negative_tags} ) &&  ( exists( $tags->{optional_tags} ) || exists( $tags->{positive_tags} ) ) && !$where );

	if ( $extra_where && $stmnt =~ /WHERE/ ) {
		$stmnt =~ s/^(.*?)WHERE(.*)/$1 WHERE $extra_where AND \( $2 \)/i;
	} elsif ( $extra_where ) {
		$stmnt .= ' WHERE ' . $extra_where; 
	}
	
	push @bind, @tags_bind if ( scalar @tags_bind );

	return $stmnt, @bind;
}

sub _formatResults {
	my ( $self, %results ) = @_;
	
	my %end_results;

	foreach my $item ( @{ $results{items} } ) {
		my $idstring = $results{ids};
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$item->{title}, 
			$item->{description}, 
			$results{search_collection},
			"item",
			$item->{digest},
			$item->{item_date},
			$item->{extra_column},
			$idstring
		);

		logDebug "ITEM score: $score - $item->{title}" if ( $self->{logScore} );

		$end_results{ $score }{id} = $item->{digest};
		$end_results{ $score }{title} = $item->{title};
		$end_results{ $score }{description} = $item->{description};
		$end_results{ $score }{type} = 'assess';
		$end_results{ $score }{date} = $item->{item_date};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
		$end_results{ $score }{is_archived} = $item->{is_archived};
	}
	
	foreach my $analysis ( @{ $results{analysis} } ) {
		
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$analysis->{title}, 
			$analysis->{comments}, 
			$results{search_collection},
			"analysis",
			$analysis->{id},
			$analysis->{analysis_date},
			$analysis->{extra_column}
		);
		logDebug "ANALYSIS score: $score - $analysis->{title}" if ( $self->{logScore} );
				
		$end_results{ $score }{id} = $analysis->{id};
		$end_results{ $score }{title} = $analysis->{title};
		$end_results{ $score }{description} = $analysis->{comments};
		$end_results{ $score }{type} = 'analysis';
		$end_results{ $score }{date} = $analysis->{analysis_date};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
	}

	foreach my $advisory ( @{ $results{advisories} } ) {
		
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$advisory->{adv_title}, 
			$advisory->{contents}, 
			$results{search_collection},
			"publication_advisory",
			$advisory->{id},
			$advisory->{advisory_date},
			$advisory->{extra_column}
		);
		
		logDebug "ADVISORY score: $score - $advisory->{adv_title}" if ( $self->{logScore} );
		
		my $advisoryType = ( exists( $advisory->{source} ) ) ? 'forward' : 'advisory';
		$end_results{ $score }{id} = $advisory->{pub_id};
		$end_results{ $score }{title} = $advisory->{adv_title};
		$end_results{ $score }{description} = $advisory->{summary};
		$end_results{ $score }{type} = $advisoryType;
		$end_results{ $score }{date} = $advisory->{advisory_date};
		$end_results{ $score }{govcertid} = $advisory->{govcertid};
		$end_results{ $score }{version} = $advisory->{version};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
	}
	
	foreach my $eow ( @{ $results{eow} } ) {
		
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$eow->{eow_title}, 
			$eow->{contents}, 
			$results{search_collection},
			"publication_endofweek",
			$eow->{id},
			$eow->{eow_date}
		);

		logDebug "EOW score: $score - $eow->{eow_date}" if ( $self->{logScore} );
				
		$end_results{ $score }{id} = $eow->{pub_id};
		$end_results{ $score }{title} = $eow->{eow_title};
		$end_results{ $score }{description} = $eow->{introduction};
		$end_results{ $score }{type} = 'eow';
		$end_results{ $score }{date} = $eow->{eow_date};
		$end_results{ $score }{created} = $eow->{eow_created};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
	}

	foreach my $eos ( @{ $results{eos} } ) {
		
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$eos->{eos_title}, 
			$eos->{contents}, 
			$results{search_collection},
			"publication_endofshift",
			$eos->{id},
			$eos->{eos_date}
		);

		logDebug "EOS score: $score - $eos->{eos_date}" if ( $self->{logScore} );
				
		$end_results{ $score }{id} = $eos->{pub_id};
		$end_results{ $score }{title} = $eos->{eos_title};
		$end_results{ $score }{description} = $eos->{general_info};
		$end_results{ $score }{type} = 'eos';
		$end_results{ $score }{date} = $eos->{eos_date};
		$end_results{ $score }{created} = $eos->{eos_created};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
	}

	foreach my $eod ( @{ $results{eod} } ) {
		
		my ( $score, @matched_tags ) = $self->_getResultScore( 
			$eod->{eod_title}, 
			$eod->{contents}, 
			$results{search_collection},
			"publication_endofday",
			$eod->{id},
			$eod->{eod_date}
		);

		logDebug "EOD score: $score - $eod->{eod_date}" if ( $self->{logScore} );
				
		$end_results{ $score }{id} = $eod->{pub_id};
		$end_results{ $score }{title} = $eod->{eod_title};
		$end_results{ $score }{description} = $eod->{general_info};
		$end_results{ $score }{type} = 'eod';
		$end_results{ $score }{date} = $eod->{eod_date};
		$end_results{ $score }{created} = $eod->{eod_created};
		$end_results{ $score }{tags} = "@matched_tags";
		$end_results{ $score }{score} = $score;
	}

	my @sorted_return;

	foreach my $key ( reverse sort { $a <=> $b } keys %end_results ) {
		push @sorted_return, $end_results{ $key };
	}
	
	return \@sorted_return;
}

#		exact match in title:	100
#		exact match in text: 90
#		all keywords in title: 50
#		all keywords in text: 25
#
#		per +keyword in title: 20
#		per optional keyword in title: 15
#		per +keyword in text:	10
#		per optional keyword in text: 5
#			
#		all tags: 100
#		per +tag:	25
#		per optional tag: 10
#
#		kolom specifiek: 50

sub _getResultScore {
	my ( $self, $title_txt, $description_txt, $search_collection, $table_name, $item_id, $item_date, $extra_column_data, $idstring ) = @_;

	my $log = "";
	my $search_string = $search_collection->{search_string};

	$search_string =~ s/tag:(")?.*?(?(2)")(?:\s|\z)//gi;
	$search_string =~ s/("|\+|-)//gi;

	my @positive_words = @{ $search_collection->{positive_words} };
	my @optional_words = @{ $search_collection->{optional_words} };	
	my @positive_tags = @{ $search_collection->{positive_tags} };
	my @optional_tags = @{ $search_collection->{optional_tags} };


	my %scores_table = (
		 positive_words => { 
			in_title => 20,
			in_text => 10 
		},
		 optional_words => { 
			in_title => 15,
			in_text => 5 
		}
	 );

#	foreach my $item ( @{ $results{items} } ) {
	my $date = substr( $item_date, 6, 4 ) 
		.substr( $item_date, 3, 2 )
		.substr( $item_date, 0, 2 )
		.substr( $item_date, 11, 2 )
		.substr( $item_date, 14, 2 )
		.substr( $item_date, 17, 2 )
		.substr( $item_date, 20, 2 );

	my $score = 0;
	my $count = 0;
	my $count_in_title = 0;
	my $count_words_in_extra_column = 0;
			
# each keyword and +keyword in title and/or description
	foreach my $key ( keys %{ $search_collection } ) {
		next if ( $key eq 'positive_tags' || $key eq 'optional_tags' || $key eq 'search_string' );

		$count = 0;
		$count_in_title = 0;
		$count_words_in_extra_column = 0;
		
		foreach my $word ( @{ $search_collection->{$key} } ) {
			$word =~ s/%//g;
			$count += () = $description_txt =~ /(\Q$word\E)/ig;
			$count_in_title += () = $title_txt =~ /(\Q$word\E)/ig;
			if ( $extra_column_data ) {
				$count_words_in_extra_column += () = $extra_column_data =~ /(\Q$word\E)/ig;
			}
		} 
		
		$log .= "\n+ $count * $scores_table{ $key }->{in_text} -->in text $key";
		$log .= "\n+ $count_in_title * $scores_table{ $key }->{in_title} -->in title $key";
		$score += ( $count * $scores_table{ $key }->{in_text} );
		$score += ( $count_in_title * $scores_table{ $key }->{in_title} );
		
		$log .= "\n+ $count_words_in_extra_column * 50 -->in extra column";
		$score += ( $count_words_in_extra_column * 50 ) if ( $extra_column_data );
	}
		
# exact match
	if ( $title_txt =~ /\Q$search_string\E/i ) {
		$score += 100;
		$log .= "\n+ 100 exact match title ('$search_string')";	
	}
	
	if ( $description_txt =~ /\Q$search_string\E/i ) {
		$score += 90;
		$log .= "\n+ 90 exact match description ('$search_string')";
	}
		
# all keywords in title and/or text
	my $all_words_in_title = 1;
	my $all_words_in_text = 1;
	foreach my $word ( @positive_words, @optional_words ) {
		$word =~ s/%//g;
		if ( $title_txt !~ /\Q$word\E/i ) {
			$all_words_in_title = 0;
		}
		if ( $description_txt !~ /\Q$word\E/i ) {
			$all_words_in_text = 0;
		}
		last if ( !$all_words_in_title && !$all_words_in_text );
	}
	$log .= "\n+ 50 all keywords in title" if ( $all_words_in_title && ( @positive_words || @optional_words ) );
	$log .= "\n+ 25 all keywords in text" if ( $all_words_in_text && ( @positive_words || @optional_words ) );
	$score += 50 if ( $all_words_in_title && ( @positive_words || @optional_words ) );
	$score += 25 if ( $all_words_in_text && ( @positive_words || @optional_words ) );
		
# per positive and optional tag
	my @matched_tags;
	my $count_linked_tags = 0;
	foreach my $tag ( @positive_tags, @optional_tags ) {
		my $tag_score = 0;
		
		$tag =~ s/%//g;
		if ( $self->_checkItemTag( $tag, $item_id, $table_name ) ) {
			if ( "@positive_tags" =~ /\Q$tag\E/i ) {
				$tag_score = 25;
				$log .= "\n+ 25 positive tag";
			} elsif ( "@optional_tags" =~ /\Q$tag\E/i ) {
				$tag_score = 10;
				$log .= "\n+ 10 optional tag";
			}
			
			push @matched_tags, $tag;
			$score += $tag_score;
			$count_linked_tags++;
		}
	}

# all tags
	$score += 100 if ( $count_linked_tags && $count_linked_tags == ( scalar( @positive_tags ) + scalar( @optional_tags ) ) );
	$log .= "\n+ 100 all tags" if ( $count_linked_tags && $count_linked_tags == ( scalar( @positive_tags ) + scalar( @optional_tags ) ) );
	
	$item_id =~ s/\+/\\\+/g;
	$item_id =~ s/\//\\\//g;
	if ( $idstring ) {
		my $count += () = $idstring =~ /(\Q$item_id\E)/ig;
		$score += ( $count * 50 );
		$log .= "\n+ 50 id in extra column";
	}
	
	use bignum;
	$score += $date / 10000000000000000;
	$log .= "\n+ " . $date / 10000000000000000;
	no bignum;
	
	logDebug $log . "\n" if ( $self->{logScore} );
	return $score, @matched_tags;	
}

sub collect {
	my ( $self, $stmnt, $binds ) = @_;
	undef $self->{errmsg};
	my @collection;
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @$binds );
	
	while ( $self->nextObject() ) {
		push @collection, $self->getObject();
	}		
	
	$self->{errmsg} = $self->{dbh}->{db_error_msg} if ( $self->{dbh}->{db_error_msg} );
	
	return @collection;
}

sub nextObject {
	my ( $self ) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ( $self ) = @_;
	return $self->{dbh}->getRecord;		
}

sub _checkItemTag {
	my ( $self, $tag, $item_id, $table ) = @_;

	tie my %join, "Tie::IxHash";
	my $table_id;

	for ( $table ) {
		if (/item/) {
			$table_id = "digest";
		} elsif (/analysis/) {
			$table_id = "id";
		} elsif (
			/^publication_advisory$/ 
			|| /^publication_advisory_forward$/ 
			|| /^publication_endofweek$/ 
			|| /^publication_endofshift$/ 
			|| /^publication_endofday$/
		) {
			$table_id = "id::varchar";
		}
	}	
		
	my %where = ( "t.name" => { -ilike => $tag }, $table.".".$table_id => $item_id );
		
	my ( $stmnt, @bind ) = $self->{sql}->select( $table, "COUNT(*) AS cnt", \%where );
	%join = (
		"JOIN tag_item ti" => { "ti.item_id" => $table.".".$table_id },
		"JOIN tag t" => { "t.id" => "ti.tag_id"}
	);
		
	$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt );
	
	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
		
	my $cnt = eval {$self->{dbh}->fetchRow(); };
	
	if ( $cnt->{cnt} > 0 ) {
		return 1;
	} else {
		return 0;
	}
}

sub getDistinctSources {
	my $self = $_[0];
	
	my @sources;
	my $sql = "SELECT DISTINCT(sourcename) FROM sources ORDER BY sourcename";
	
	$self->{dbh}->prepare( $sql );
	$self->{dbh}->executeWithBinds();
	
	while ( $self->nextObject() ) {
		push @sources, $self->getObject()->{sourcename};
	}
	
	return @sources;
}
1;

=head1 NAME

Taranis::MetaSearch

=head1 SYNOPSIS

  use Taranis::MetaSearch;

  my $obj = Taranis::MetaSearch->new( $oTaranisConfig );

  $obj->collect( $sql_query, \@binds );

  $obj->dissectSearchString( $search_string );

  $obj->getDistinctSources();

  $obj->search( \%searchSettings, \%dbSettings );

  $obj->_checkItemTag( $tag, $item_id, $table );

  $obj->_createWhereFromSearch( $table, $selection_id, $select, \@columns, \%tags, \%keywords, \%join, $extra_where );

  $obj->_formatResults( %results );

  $obj->_getResultScore( $title_txt, $description_txt, \%search_collection, $table_name, $item_id, $item_date, $extra_column_data, $idstring );

=head1 DESCRIPTION

Module for handling search requests originating from main search in GUI.

Searchresult order depends on a score:

=over

=item *

exact match in title: 100

=item *

exact match in text: 90

=item *

all keywords in title: 50

=item *

all keywords in text: 25

=item *

per +keyword in title: 20

=item *

per optional keyword in title: 15

=item *

per +keyword in text: 10

=item *

per optional keyword in text: 5

=item *

all tags: 100

=item *

per +tag: 25

=item *

per optional tag: 10

=item *

column specific: 50

=back

=head1 METHODS

=head2 new( $objTaranisConfig )

Constructor of the C<Taranis::MetaSearch> module. An object instance of Taranis::Config, which is optional, will be used for creating a database handler.

    my $obj = Taranis::MetaSearch->new( $objTaranisConfig );

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new C<SQL::Abstract::More> object which can be accessed by:

    $obj->{sql};

Set debug logging of score. Set 1 for debug logging on and 0 for off:

    $obj->{logScore}

Sets the path of the identifiers configuration:

    $obj->{identifiersConfig}

Returns the blessed object.

=head2 collect( $sql_query, \@binds )

Generic method for retrieving a collection of items.

    $obj->collect( 'SELECT * FROM item WHERE status = ? ', [2,3] ); 

Returns an ARRAY.

=head2 dissectSearchString( $search_string )

Will split up the searchstring into lists and settings. It will

=over

=item *

check if there are keywords surrounded by quotes, which means the surrounded keywords must used as exact match

=item *

check if keywords are preceded by + (plus) or - (minus), which means the keyword is must be present in search text or should not be present in search text

=item *

check if keywords are preceded by tag:, which means the keyword must be included in the tagslist search

=item *

test if searchstring does not only contain negative (=preceded by minus) keywords and tags

=back

    $obj->dissectSearchString( '+tag:taranis +taranis "me like taranis" -taaaaranis' );

Returns an HASH reference with the following keys:

=over

=item *

keywords = { positive_words => ['%list%', '%of%', '%words%'], optional_words => ['%list%', '%of%', '%words%'], negative_words => ['%list%', '%of%', '%words%'] }

=item *

tags = { positive_tags => ['list', 'of', 'tags'], optional_tags => ['list', 'of', 'tags'], negative_tags => ['list', 'of', 'tags'] }

=item *

idstring = 'digest_of_identifier1 digest_of_identifier2 digest_of_identifier2'

=item *

negative_ids = ['list', 'of', 'identifiers']

=item *

positive_ids = ['list', 'of', 'identifiers']

=item *

all_ids = ['list', 'of', 'identifiers']

=item *

search_string_collection = { search_string => '+all -keywords and tag:tags', positive_words => [], optional_words => [], positive_tags => [], optional_tags => [] }

=back

=head2 getDistinctSources()

Retrieves a list of sourcenames.

    $obj->getDistinctSources();

Returns an ARRAY with sourcenames.

=head2 search( \%searchSettings, \%dbSettings )

Performs search using C<%searchSettings> and C<%dbSettings>. Parameter C<%searchSettings> can be created by dissectSearchString().
Runs the results through _formarResults() before returning them.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Missing mandatory parameter!>

Caused by setDossier() when C<id> is not set.
You should check C<id> setting.

=item *

I<Invalid parameter!>

Caused by getDateLatestActivity() when parameter C<$dossierID> is not a number.
You should check parameter C<$dossierID>.

=back

=cut
