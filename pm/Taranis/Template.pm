# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Template;

use Taranis qw(:all);
use Taranis::Assess;
use Taranis::Analysis;
use Taranis::Database;
use Taranis::Dossier;
use Taranis::Dossier::Item;
use Taranis::Config;
use Taranis::Publication;
use Taranis::Report::ContactLog;
use Taranis::Report::IncidentLog;
use Taranis::FunctionalWrapper qw(CGI Config Database Sql);

use 5.010;
use strict;

use Carp;
use Template;
use SQL::Abstract::More;
use Data::Validate qw(is_integer);
use XML::Simple;
use POSIX;
use JSON -support_by_pp; 
use Encode;
use Date::Calc qw(N_Delta_YMDHMS);
use Date::Language;
use Date::Parse;
use HTML::Entities qw(encode_entities decode_entities);
use CGI::Simple;


sub new {
	my ( $class, %arg ) = @_;

	my $cfg = ( exists( $arg{config} ) && $arg{config} )
		? $arg{config}
		: Taranis::Config->new();
 
	my $templates = $ENV{TEMPLATE_PATH}
		or die "no TEMPLATE_PATH";

	my $self = {
		errmsg => undef,
		tpl_error => undef,
		tt => Template->new(
			{
				INCLUDE_PATH => [split /\:/, $templates],
				PRE_CHOMP => 1,
				POST_CHOMP => 1,
			}
		),
		dbh => Database,
		sql => Sql,
		config => $cfg
	};

	# extra template vmethod decodeEntity
	$self->{tt}->context->define_vmethod( 'scalar', 'decodeEntity',
		sub {
			my $encodedText = shift;
			return decode_entities( $encodedText );
		} 
	);  

	# extra template vmethod keysReverseSortByValue
	$self->{tt}->context->define_vmethod( 'hash', 'keysReverseSortByValue',
		sub {
			my $hash = shift;
			my %hashCopy = %$hash;
			return reverse sort( { $hashCopy{$a} cmp $hashCopy{$b} } keys %hashCopy ); 
		} 
	);
	
	# extra template vmethod durationText
	$self->{tt}->context->define_vmethod( 'scalar', 'durationText',
		sub {
			my $startDateTime = shift;
			my $endDateTime = shift;

			my ( $sec1, $min1, $hour1, $day1, $month1, $year1 ) = ( localtime($startDateTime) )[0,1,2,3,4,5]; 
			my ( $sec2, $min2, $hour2, $day2, $month2, $year2 ) = ( localtime($endDateTime) )[0,1,2,3,4,5];

			# correct month and year
			$month1 += 1;
			$month2 += 1;
			$year1 += 1900;
			$year2 += 1900;
			
			my ( $years, $months , $days, $hours, $minutes, $seconds ) = N_Delta_YMDHMS(
					$year1,$month1,$day1, $hour1,$min1,$sec1,
					$year2,$month2,$day2, $hour2,$min2,$sec2
				);
			
			my $durationText = '';
			$durationText .= $days . ' day' if ( $days );
			$durationText =~ s/(.*)/$1s, / if ( $days > 1 );
			
			$durationText .= $hours . ' hour' if ( $hours );
			$durationText =~ s/(.*)/$1s/ if ( $hours > 1 );
			
			$durationText .= ' and ' if ( $hours );
			$durationText .= $minutes . ' minute' if ( $minutes );
			$durationText =~ s/(.*)/$1s/ if ( $minutes > 1 );

			return $durationText;
		}
	);

	# extra template vmethod displayAssessStatus
	$self->{tt}->context->define_vmethod( 'scalar', 'displayAssessStatus',
		sub {
			my $statusNumber = shift;
			return Taranis::Assess::->getStatusDictionary()->{$statusNumber};
		}
	);

	# extra template vmethod displayAnalyzeRating
	$self->{tt}->context->define_vmethod( 'scalar', 'displayAnalyzeRating',
		sub {
			my $rating = shift;
			return Taranis::Analysis::->getRatingDictionary()->{$rating};
		}
	);

	# extra template vmethod displayPublicationStatus
	$self->{tt}->context->define_vmethod( 'scalar', 'displayPublicationStatus',
		sub {
			my $statusNumber = shift;
			return Taranis::Publication::->getStatusDictionary()->{$statusNumber};
		}
	);
	# extra template vmethod displayTLPColor
	$self->{tt}->context->define_vmethod( 'scalar', 'displayTLPColor',
		sub {
			my $tlp = shift;
			return uc( Taranis::Dossier::Item->getTLPMapping()->{$tlp} );
		}
	);
	# extra template vmethod displayDossierStatus
	$self->{tt}->context->define_vmethod( 'scalar', 'displayDossierStatus',
		sub {
			my $statusNumber = shift;
			return Taranis::Dossier::->getDossierStatuses()->{$statusNumber};
		}
	);
	# extra template vmethod displayReportContactLogType
	$self->{tt}->context->define_vmethod( 'scalar', 'displayReportContactLogType',
		sub {
			my $typeNumber = shift;
			return Taranis::Report::ContactLog->getContactTypeDictionary()->{$typeNumber};
		}
	);
	# extra template vmethod displayReportIncidentLogStatus
	$self->{tt}->context->define_vmethod( 'scalar', 'displayReportIncidentLogStatus',
		sub {
			my $statusNumber = shift;
			return Taranis::Report::IncidentLog->getStatusDictionary()->{$statusNumber};
		}
	);
	
	# extra template vmethod stripTags
	$self->{tt}->context->define_vmethod( 'scalar', 'stripTags',
		sub {
			my $html = shift;
			$html =~ s/<.*?>//g;
			return $html;
		}
	);
	# extra template vmethod addThousandsSeparators
	$self->{tt}->context->define_vmethod( 'scalar', 'addThousandsSeparators',
		sub {
			my $intnum = shift;
			return Taranis::addThousandsSeparators($intnum);
		}
	);

	# extra template vmethod stripSeconds
	# Purpose of vmethod is to sanitize a timestamp with seconds and 
	# timezone indication so timestamp can be formatted with Template::Pugin::Date->format().
	# It prevents messages in apache log like:
	# 'Argument "01.032523+02" isn't numeric in subroutine entry at /usr/lib64/perl5/Template/Plugin/Date.pm line 121' 
	$self->{tt}->context->define_vmethod( 'scalar', 'stripSeconds',
		sub {
			my $timestamp = shift;
			
			$timestamp =~ s/(.*?)(\.|\+).*/$1/;
			
			return $timestamp;
		}
	);

	return( bless( $self, $class ) );
}

sub addTemplate {
	my ( $self, %template ) = @_;
	undef $self->{errmsg};
	
	my ( $stmnt, @bind ) = $self->{sql}->insert( "publication_template", \%template );
	$self->{dbh}->prepare($stmnt);
	
	if ( defined( $self->{dbh}->executeWithBinds(@bind) ) > 0 ) {
		return 1;
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub setTemplate {
	my ( $self, %template ) = @_;

	if ( !defined( $template{id} ) || !is_integer( $template{id} ) ) {
		$self->{errmsg} = "Invalid parameter!";
		return 0;
	}

	my %where = ( id => delete $template{id} );
	my ( $stmnt, @bind ) = $self->{sql}->update( "publication_template", \%template, \%where );

	$self->{dbh}->prepare($stmnt);
	my $result = $self->{dbh}->executeWithBinds(@bind);

	if ( defined($result) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return 0;
	}
}

sub deleteTemplate {
	my ( $self, $id ) = @_;

	if ( !defined($id) || !is_integer($id) ) {
		$self->{errmsg} = "Invalid parameter!";
		return 0;
	}

	my ( $stmnt, @bind ) = $self->{sql}->delete( "publication_template", { id => $id } );
	$self->{dbh}->prepare($stmnt);

	my $result = $self->{dbh}->executeWithBinds(@bind);
	if ( defined($result) && ( $result !~ m/(0E0)/i ) ) {
		if ( $result > 0 ) {
			return 1;
		} elsif ( defined( $self->{dbh}->{db_error_msg} ) ) {
			$self->{errmsg} = $self->{dbh}->{db_error_msg};
			return 0;
		}
	} else {
		$self->{errmsg} = "Delete failed, corresponding id not found in database.";
		return 0;
	}
}

sub getTemplate {
	my ( $self, %searchFields ) = @_;
	undef $self->{errmsg};

	my %where = $self->{dbh}->createWhereFromArgs( %searchFields );

	my ( $stmnt, @bind ) =  $self->{sql}->select( "publication_template", "title, id, description, type, template AS tpl",  \%where, "title" );

	$self->{dbh}->prepare($stmnt);
	my $result = $self->{dbh}->executeWithBinds(@bind);

	$self->{errmsg} = $self->{dbh}->{db_error_msg};
 	return $result;
}

sub getTypeIds {
	my ( $self, @type_names ) = @_;
	undef $self->{errmsg};
	my @ids;
	
	my ( $stmnt, @bind ) = $self->{sql}->select( "publication_type", "id", { title => { ilike => \@type_names} } );

	$self->{dbh}->prepare( $stmnt );
	$self->{dbh}->executeWithBinds( @bind );
	
	if ( defined( $self->{dbh}->{db_error_msg} )) {
		$self->{errmsg} = $self->{dbh}->{db_error_msg};
		return;
	} else {	
		while ( $self->nextObject() ) {
			push @ids, $self->getObject()->{id};
		}
		return \@ids;
	}	
}

sub nextObject {
	my ($self) = @_;
	return $self->{dbh}->nextRecord;
}

sub getObject {
	my ($self) = @_;
	return $self->{dbh}->getRecord;
}

sub processTemplateWithHeaders {
	my ( $self, $template, $vars ) = @_;

	print CGI->header(
		-cache_control => 'no-cache, no-store, max-age=0, must-revalidate',
		-type => 'text/html',
		-charset => 'utf-8',
	);

	print $self->processTemplate( $template, $vars, 1 );
}

sub processTemplate {
	my ( $self, $template, $vars, $noprint ) = @_;
	$vars //= {};

	# Add some standard template variables.
	$vars = {
		unixtime => time,
		webroot => Config->{webroot},
		scriptroot => Config->{scriptroot},
		banner_html => Config->{banner_html},
		taranis_version => $Taranis::VERSION,
		%$vars,
	};

	if ($noprint) {
		my $output = '';
		$self->{tt}->process( $template, $vars, \$output ) || croak $self->{tt}->error;
		return $output;
	} else {
		$self->{tt}->process( $template, $vars ) || croak $self->{tt}->error;
	}
}

sub processPublicationTemplate {
	my ( $self, $template, $tab ) = @_;
	undef $self->{tpl_error};

	$template =~ s/&lt;/</g;
	$template =~ s/&gt;/>/g;
	$template =~ s/&quot;/"/g;
	$template =~ s/&#39;/'/g;  

	$template =~ /<template>(.*?)<\/template>/s;

	my $tpl_content = $1;
	
	if ( $template !~ /<template><!\[CDATA\[.*?\]\]><\/template>/is ) {
		$template =~ s/<template>.*?<\/template>/<template><!\[CDATA\[$tpl_content]]><\/template>/s;
	}
	
	my $ref = eval { XMLin $template };
	if ($@) {
		$self->{tpl_error} = "XML parse error. Please check the publication template syntax.(1)<br />" . $@;
		return;
	}

	my $fields = $ref->{fields};
	my (@errors, @html);

  FIELD:
	foreach my $fieldname (sort keys %$fields) {
		my $layout = $fields->{$fieldname};
		if(ref $layout ne 'HASH') {
			push @errors, "Field $fieldname description has no attributes.";
			next FIELD;
		}

		my $desc = $layout->{desc};
		unless($desc) {
			push @errors, "Field $fieldname has no 'desc' attribute.";
			next FIELD;
		}

		my ($type, @params) = split /\:/, trim $layout->{content};
		my $html;

		if($type eq 'textarea') {
			my $width  = val_int $params[0];
			my $height = val_int $params[1];
			unless($width && $height && @params==2) {
				push @errors, "Field $fieldname textarea requires a width and height.";
				next FIELD;
			}


			$html = qq{<textarea name="$fieldname" id="$fieldname" class="input-default" style="width: ${width}px; height: ${height}px"></textarea>};

		} elsif($type eq 'text') {
			my $width = val_int $params[0];
			unless($width && @params==1) {
				push @errors, "Field $fieldname text format requires a width.";
				next FIELD;
			}

			$html = qq{<input name="$fieldname" id="$fieldname" type="text" class="input-default" style="width: ${width}px">};

		} elsif($type eq 'dropdown') {
			unless(@params) {
				push @errors, "Field $fieldname dropdown requires entries";
				next FIELD;
			}

			$html = join "\n",
				qq{<select name="$fieldname" id="$fieldname" class="input-default">},
				(map "<option>$_</option>", @params),
				qq{</select>};

		} elsif($type eq 'radio') {
			unless(@params) {
				push @errors, "Field $fieldname radio requires items.";
				next FIELD;
			}

			$html = join "\n", '<div>', map(<<__RADIO, @params), '</div>';
<input type="radio" name="$fieldname" id="$_" value="$_"><label for="$_">$_</label><br>
__RADIO

		} elsif($type eq 'multiple') {
			unless(@params) {
				push @errors, "Field $fieldname multiple requires items.";
				next FIELD;
			}

			$html = join "\n", '<div>', map(<<__CHECKBOX, @params), '</div>';
<input type="checkbox" name="$fieldname" id="$_" value="$_"><label for="$_">$_</label><br>
__CHECKBOX

		} elsif($type eq 'select') {
			my $size = val_int(shift @params);
			unless($size) {
				push @errors, "Field $fieldname select requires size.";
				next FIELD;
			}

			unless(@params) {
				push @errors, "Field $fieldname select requires entries.";
				next FIELD;
			}

			$html = join "\n",
				qq{<select name="$fieldname" id="$fieldname" size="$size" multiple class="input-default">},
				(map "<option>$_</option>", @params),
				qq{</select>};

		} else {
			push @errors, "Unknown field type '$type'";
		}

		push @html, qq{<div class="tpl-heading">$desc:</div>}, $html
			if defined $html;
	}

	push @html, <<__WARNING unless @html;
<div class="tpl-heading">This template contains no input fields.
Press '< Apply template' to add template text.</div>
__WARNING

	$self->{tpl_error} .= join "\n", 'Template errors:', @errors
		if @errors;

	join "\n", @html;
}

sub formatItemList {
	my $glue = pop(@_);
	return "" if !@_;
	my $last = pop(@_);
	return $last if !@_;
	return join(', ', @_) . " $glue $last";
}

sub processPublicationTemplateText {
	my ( $self, $json_str, $tab ) = @_;
	undef $self->{tpl_error};

	my $tpl_data = decode_json($json_str);

	$self->getTemplate( id => $tpl_data->{template_id} );

	my $template = $self->{dbh}->fetchRow()->{tpl};

	$template =~ s/&lt;/</g;
	$template =~ s/&gt;/>/g;
	$template =~ s/&quot;/"/g;
	$template =~ s/&#39;/'/g;
	
	$template =~ /<template>(.*?)<\/template>/s;

	my $tpl_content = $1;

	if ( $template !~ /<template><!\[CDATA\[.*?\]\]><\/template>/is ) {
		$template =~ s/<template>.*?<\/template>/<template><!\[CDATA\[$tpl_content]]><\/template>/s;
	}

	my $ref = eval { XMLin( $template ) };
	if ($@) {
		$self->{tpl_error} = "XML parse error. Please check the publication template syntax.(2)";
		return;
	}

	my $tpl_txt = ref $ref->{template} eq 'HASH' ? '' : $ref->{template};
	
	foreach my $key ( keys %$tpl_data ) {
		my $tpl_fieldname = $key;
		$key =~ s/$tab//i;
		if (ref $tpl_data->{$tpl_fieldname} eq 'ARRAY') {

			my @lst = @{$tpl_data->{$tpl_fieldname}};
			push @lst, Config->{glue_word} // 'and';
			my $tmp = formatItemList(@lst);

			$tpl_txt =~ s/_($key)_/$tmp/ig;
		} else {
			$tpl_txt =~ s/_($key)_/$tpl_data->{$tpl_fieldname}/ig;
		}
	}

	foreach my $field ( keys %{ $ref->{fields} } ) {
		$tpl_txt =~ s/_$field\_//gi;
	}

	# do sorting of headers 
	if ( $tpl_data->{original_txt} && $tpl_data->{original_txt} =~ /-=.*?=-/ ) {
		$tpl_txt = $tpl_data->{original_txt} . "\n" . $tpl_txt;

		my @lines = split( /(\s*-=.*?=-)/ , $tpl_txt );
		
		my $text;
		my %text_per_heading;
		
		for ( my $i = 0; $i < @lines; $i++ ) {
			if ( $lines[$i] =~ /-=.*?=-/ ) {
				$text_per_heading{ trim( $lines[$i] ) } .= trim( $lines[$i] ) . ( delete $lines[$i+1] );
				$i++;
			} else {
				$text = $lines[$i];
			} 
		}
		
		@lines = sort sortAnyCase( keys %text_per_heading );
		
		foreach ( @lines ) {
			$text .= "\n\n".$text_per_heading{$_};
		}

		$tpl_txt = $text;
	} else {
		$tpl_txt = $tpl_data->{original_txt} . $tpl_txt; 
	}

	$tpl_txt =~ s/^\n*//;
	$tpl_txt =~ s/\n*\z/\n/;

	return $tpl_txt;
}

sub processPreviewTemplate {
	my ( $self, $publication, $publication_type, $pub_details_id, $publication_id, $line_width ) = @_;

	my $xml_str;
	my $tpl_name = Config->publicationTemplateName($publication => $publication_type);

	$self->getTemplate( title => $tpl_name );
	while ( $self->nextObject() ) {
		$xml_str = decode_entities( $self->getObject()->{tpl} );
	}

	my %id = (
		publication_id 	=> $publication_id,
		"publication.id" => $publication_id
	);

	if ( $publication eq "advisory" &&  $publication_type =~ /^forward/ ) {
		$id{"advisory_forward_id"} = $pub_details_id;
		$id{"publication_advisory_forward.id"} = $pub_details_id;
	} elsif ( $publication eq "advisory" ) {
		$id{"advisory_id"} = $pub_details_id;
		$id{"publication_advisory.id"} = $pub_details_id;
	} elsif ( $publication eq "eow" ) {
		$id{"eow_id"} = $pub_details_id;
		$id{"publication_endofweek.id"} = $pub_details_id;
	} elsif ( $publication eq "eos" ) {
		$id{"eos_id"} = $pub_details_id;
		$id{"publication_endofshift.id"} = $pub_details_id;
	} elsif ( $publication eq "eod" ) {
		$id{"eod_id"} = $pub_details_id;
		$id{"publication_endofday.id"} = $pub_details_id;
	} else {
		$self->{errmsg} = "Unknown publication: $publication";
		return;
	}

	my $ref = eval { XMLin($xml_str ) };
	if ($@) {
		$self->{errmsg} = "XML parse error:" . $@;
		return;
	}

	my ( %statements, %replacements, %settings );

	my $fields = $ref->{fields};
	my $template_txt = $ref->{template};

	#################### CONVERT XML INTO SQL STATEMENTS (<fields></fields>) ####################
	foreach my $key ( keys %$fields ) {

		if (ref $fields->{$key} ne 'ARRAY' ) {
			$fields->{$key}[0] = delete $fields->{$key};
		}

		for ( my $j = 0 ; $j < @{ $fields->{$key} } ; $j++ ) {
			my $field_type = $fields->{$key}->[$j]->{type};

			for ($field_type) {
				if (/database/) {
					my ( %join, %where );
					my ( $tbl1, $tbl1_column, $tbl2, $tbl2_column, $select, $from );

					for ( my $i = 0 ; $i < @{ $fields->{$key}->[$j]->{tbl} } ; $i++ ) {
						if ( 
							( exists $fields->{$key}->[$j]->{tbl}->[$i]->{content} )
							&& ( exists $fields->{$key}->[$j]->{tbl}->[$i]->{type} )
							&& ( exists $fields->{$key}->[$j]->{tbl}->[$i]->{column} ) 
						) {
							my $type = $fields->{$key}->[$j]->{tbl}->[$i]->{type};
							my $column = $fields->{$key}->[$j]->{tbl}->[$i]->{column};
							my $table  = $fields->{$key}->[$j]->{tbl}->[$i]->{content};

							for ($type) {
								if (/^key$/) {
									my $where_column = ( $column eq "id" ) ? $table . "." . $column : $column;
									%where = ( $table . "." . $column => $id{$where_column} );
								}
								if (/^select$/) {
									$select = "DISTINCT(" . $table . "." . $column . ")";
									$from = $table;
								}
								if (/^select_date$/) {
									$select = "to_char(" . $table . "." . $column . ", 'YYYYMMDD')";
									$from   = $table;
								}
								if (/^(select_date_.+)$/) {
									$select = "DISTINCT(" . $table . "." . $column . ")";
									$from = $table;
									$settings{$key}->{$1} = undef;
								}
								if (/^join1$/) {
									$tbl1 = $table;
									$tbl1_column = $column;
								}
								if (/^join2$/) {
									$tbl2 = $table;
									$tbl2_column = $column;
								}
							}
						} else {
							$self->{errmsg} = "Template error: syntax for type 'database' incorrect. Please correct template $tpl_name\n";
						}
					}
					my ( $stmnt, @bind ) = $self->{sql}->select( $from, $select, \%where );
					if ( $tbl1 && $tbl2 ) {
						%join =	( "JOIN " . $tbl1 => { $tbl1 . "." . $tbl1_column => $tbl2 . "." . $tbl2_column } );
						$stmnt = $self->{dbh}->sqlJoin( \%join, $stmnt ) if keys %join;
					}
					$statements{$key} = [ $stmnt => @bind ];
				} elsif (/replace/) {

					if ( exists( $fields->{$key}->[$j]->{rp} ) ) {

						#If there is only one element in 'replace', must be placed in an array for walking through 'replace'
						if ( ref( $fields->{$key}->[$j]->{rp} ) ne 'ARRAY' ) { 
							$fields->{$key}->[$j]->{rp}->[0] = delete $fields->{$key}->[$j]->{rp};
						}

						for ( my $k = 0 ; $k < @{ $fields->{$key}->[$j]->{rp} }; $k++ ) {
							$replacements{$key}->{ $fields->{$key}->[$j]->{rp}->[$k]->{original_value} } = $fields->{$key}->[$j]->{rp}->[$k]->{content};
						}
					} else {
						$self->{errmsg} = "Template error: child element(s) 'rp' missing for type 'replace'. Please correct template $tpl_name\n";
					}
				} elsif (/settings/) {
					if ( exists( $fields->{$key}->[$j]->{setting} ) ) {

						#If there is only one element in 'settings', must be placed in an array for walking through 'settings'
						if ( ref( $fields->{$key}->[$j]->{setting} ) ne 'ARRAY' ) { 
							$fields->{$key}->[$j]->{setting}->[0] = delete $fields->{$key}->[$j]->{setting};
						}

						for ( my $l = 0; $l < @{ $fields->{$key}->[$j]->{setting} }; $l++ ) {
							$settings{$key}->{$fields->{$key}->[$j]->{setting}->[$l]->{type} } = $fields->{$key}->[$j]->{setting}->[$l]->{content};
						}

					} else {
						$self->{errmsg} = "Template error: child element(s) 'setting' missing for type 'settings'. Please correct template $tpl_name\n";
					}
				}
			}
		}
	}

	#################### QUERY THE STATEMENTS ####################
	my %results;
	foreach my $field ( keys %statements ) {
		my ($stmnt, @binds) = @{$statements{$field}};
		$self->{dbh}->prepare($stmnt);
		$self->{dbh}->executeWithBinds(@binds);

		while ( $self->{dbh}->nextRecord() ) {
			push @{ $results{$field} }, $self->{dbh}->getRecord();
		}
	}

	#################### PROCESS THE TEMPLATE TEXT WITH THE RESULTS FROM THE DATABASE ####################
	foreach my $field_name ( keys %statements ) {
		my $result_txt = "";
		if ( exists( $replacements{$field_name} ) ) {
			for ( my $k = 0; $k < @{ $results{$field_name} }; $k++ ) {
				foreach my $result_key ( keys %{ $results{$field_name}->[$k] } ) {
					my $result_value = [ values %{ $results{$field_name}->[$k] } ]->[0];
					$results{$field_name}->[$k]->{$result_key} = $replacements{$field_name}->{ $result_value };
				}
			}
		}

		if ( exists( $results{$field_name} ) ) {
			#If the result for a field is more than one record
			if ( scalar @{ $results{$field_name} } > 1 ) {
					
				for ( my $j = 0; $j < @{ $results{$field_name} }; $j++ ) {
					$result_txt .= [ values %{ $results{$field_name}->[$j] } ]->[0] . "\n"
						if ( [ values %{ $results{$field_name}->[$j] } ]->[0] );
				}
			} else {
				$result_txt = [ values %{ $results{$field_name}->[0] } ]->[0];
				$result_txt = ( $result_txt ) ? $result_txt : "";
			}
		
			my $field_name_idx = index( $template_txt, "_$field_name" );

			my $margin;
			$template_txt =~ /\n( *_$field_name\_\b)/;
			if ( $1 ) {
				$margin = $field_name_idx - ( index( $template_txt, $1 ) );
			} else {
				$template_txt =~ /\n(.*\s*_$field_name)/;
				$margin = $field_name_idx - ( index( $template_txt, $1 ) );
			}

			my $alignment_space;
			for ( my $i = 0; $i < $margin; $i++ ) {
				$alignment_space .= " ";
			} 
			
			if ( $line_width != 0 ) {
				$result_txt = $self->setNewlines( $result_txt, $margin, $line_width );
			}

			my $new_txt;
			foreach ( split("\n", $result_txt) ) {
				$new_txt .= $_."\n".$alignment_space; 
			}
			$new_txt =~ s/\n$alignment_space$//;
			$result_txt = $new_txt;

			if ( exists( $settings{$field_name} ) && $result_txt ) {
				for ( keys %{ $settings{$field_name} } ) {
					if (/heading/) {
						$result_txt =~ s/(\s*)(.*)/\n$settings{$field_name}->{heading}\n$alignment_space$2/;
						$template_txt =~s/\n\s*_($field_name)_/\n_$field_name\_/i;
					}
					if (/^footer$/) {
						$result_txt =~ s/(.*?)[\s\n\r]*$/$1\n$settings{$field_name}->{footer}/s;
					}
					if (/^select_date_(.+)$/ ) {
						eval{
							my $lang = Date::Language->new( $1 );
							$result_txt = $lang->time2str("%A %d-%m-%Y %H:%M", str2time($result_txt) );
						};

						if ( $@ ) {
							$result_txt .= " DATE LANGUAGE NOT SUPPORTED OR INVALID DATE FORMAT SUPPLIED";
						}
					}
				}
			}
			
			if ( $result_txt ) {
				$template_txt =~s/_($field_name)_/$result_txt/i;	
			} else {
				$template_txt =~s/\n\s*_($field_name)_|_($field_name)_//i;
			}
		} else {
			$template_txt =~s/_($field_name)_//;
		}
	}
	return trim_text $template_txt;
}

sub processPreviewTemplateRT {
	my ( $self, %publicationSettings ) = @_;

	my $publication = $publicationSettings{publication};
	my $publication_type = $publicationSettings{publication_type};

	my $line_width = delete( $publicationSettings{line_width} );

	my $formData = $publicationSettings{formData};

	my $xml_str;
	my $tpl_name = Taranis::Config->new( Config->{publication_templates} )->{$publication}->{$publication_type};

	$self->getTemplate( title => $tpl_name );
	while ( $self->nextObject() ) {
		$xml_str = decode_entities( $self->getObject()->{tpl} );
	}

	my $ref = eval { XMLin($xml_str ) };
	if ($@) {
		$self->{errmsg} = "XML parse error! Please check your publication template for invalid XML.";
		return;
	}

	my ( %replacements, %settings );

	my %results;
	my $fields = $ref->{fields};
	my $template_txt = $ref->{template};

	#################### CREATE DATASTRUCTURE FROM FROMDATA ####################
	foreach my $field ( keys %$fields ) {
		if(ref $fields->{$field} ne 'ARRAY') {
			$fields->{$field}[0] = delete $fields->{$field};
		}

		foreach my $fieldItem ( @{ $fields->{$field} } ) {

			for ( $fieldItem->{type} ) {
				if (/^database$/i) {
					
					if ( exists( $fieldItem->{tbl} ) ) {
					
						TBLITEM:
						foreach my $tblItem ( @{ $fieldItem->{tbl} } ) {
							next TBLITEM if ( $tblItem->{type} !~ /^(select|select_date|select_date_.+)$/i );

							my ( $fieldValue, $keyName );

							if ( exists( $formData->{ $tblItem->{alias} } ) ) {
								$fieldValue = $formData->{ $tblItem->{alias} };
								$keyName = 'alias';
							} elsif ( exists( $formData->{ $tblItem->{column} } ) ) {
								$fieldValue = $formData->{ $tblItem->{column} };
								$keyName = 'column';
							} elsif ( exists( $formData->{ $tblItem->{content} . '.' . $tblItem->{column} } ) ) {
								$fieldValue = $formData->{ $tblItem->{content} . '.' . $tblItem->{column} };
								$keyName = 'column';
							}
							
							if ( $tblItem->{type} =~ /^select_date_(.+)$/ ) {
								# when using a date format like xx-xx-yyyy str2time will use the first xx as month
								eval{
								  my $lang = Date::Language->new( $1 );
								  $fieldValue = $lang->time2str("%A %d-%m-%Y %H:%M", str2time( $fieldValue ) );
								};

								if ( $@ ) {
									$fieldValue .= " DATE LANGUAGE NOT SUPPORTED OR INVALID DATE FORMAT SUPPLIED";
								}
							}
							
							if (ref $fieldValue eq 'ARRAY') {
								$results{$field} = $fieldValue;
							} else {
								$results{$field} = [ { $tblItem->{$keyName} => $fieldValue } ]; 
							}

						}
					} else {
						$self->{errmsg} = "Template error: child element(s) tbl missing for type database. Please correct template $tpl_name\n";
						return 0;						
					}
				} elsif (/^replace$/i) {
					
					if ( exists( $fieldItem->{rp} ) ) {
						if(ref $fieldItem->{rp} ne 'ARRAY') {
							$fieldItem->{rp}->[0] = delete $fieldItem->{rp};
						}						
						
						foreach my $replace ( @{ $fieldItem->{rp} } ) {
							$replacements{$field}->{ $replace->{original_value} } = $replace->{content};
						}
					} else {
						$self->{errmsg} = "Template error: child element(s) rp missing for type replace. Please correct template $tpl_name\n";
						return 0;
					}
				} elsif (/^settings$/i) {
					
					if ( exists( $fieldItem->{setting} ) ) {
						if(ref $fieldItem->{setting} ne 'ARRAY') {
							$fieldItem->{setting}->[0] = delete $fieldItem->{setting};
						}

						foreach my $setting ( @{ $fieldItem->{setting} } ) {
							$settings{$field}->{ $setting->{type} } = $setting->{content};
						}
					} else {
						$self->{errmsg} = "Template error: child element(s) setting missing for type settings. Please correct template $tpl_name\n";
						return 0;
					}
				}
			}
		}
	}

	#################### PROCESS THE TEMPLATE TEXT WITH THE FORM DATA ####################
	foreach my $field_name ( keys %results ) {
		my $result_txt = "";
		if ( exists( $replacements{$field_name} ) ) {
			for ( my $k = 0; $k < @{ $results{$field_name} }; $k++ ) {
				foreach my $result_key ( keys %{ $results{$field_name}->[$k] } ) {
					my $result_value = [ values %{ $results{$field_name}->[$k] } ]->[0];
					$results{$field_name}->[$k]->{$result_key} = $replacements{$field_name}->{ $result_value };
				}
			}
		}

		if ( exists( $results{$field_name} ) ) {
			#If the result for a field is more than one record
			if ( scalar @{ $results{$field_name} } > 1 ) {
					
				for ( my $j = 0; $j < @{ $results{$field_name} }; $j++ ) {
					$result_txt .= [ values %{ $results{$field_name}->[$j] } ]->[0] . "\n"
						if ( [ values %{ $results{$field_name}->[$j] } ]->[0] );
				}
			} else {
				$result_txt = [ values %{ $results{$field_name}->[0] } ]->[0];
				$result_txt = ( $result_txt ) ? $result_txt : "";
			}
		
			my $field_name_idx = index( $template_txt, "_$field_name" );

			my $margin;
			$template_txt =~ /\n( *_$field_name\_\b)/;
			if ( $1 ) {
				$margin = $field_name_idx - ( index( $template_txt, $1 ) );
			} else {
				$template_txt =~ /\n(.*\s*_$field_name)/;
				$margin = $field_name_idx - ( index( $template_txt, $1 ) );
			}

			my $alignment_space;
			for ( my $i = 0; $i < $margin; $i++ ) {
				$alignment_space .= " ";
			} 

			$result_txt =~ s/\n/\r\n/g;

			if ( $line_width != 0 ) {
				$result_txt = $self->setNewlines( $result_txt, $margin, $line_width );
			}

			my $new_txt;
			foreach ( split("\n", $result_txt) ) {
				$new_txt .= $_."\n".$alignment_space; 
			}
			$new_txt =~ s/\n$alignment_space$//;
			$result_txt = $new_txt;

			if ( exists( $settings{$field_name} ) && $result_txt ) {
				for ( keys %{ $settings{$field_name} } ) {
					if (/^heading$/) {
						$result_txt =~ s/(\s*)(.*)/\n$settings{$field_name}->{heading}\n$alignment_space$2/;
						$template_txt =~s/\n\s*_($field_name)_/\n_$field_name\_/i;
					}
					if (/^footer$/) {
						$result_txt =~ s/(.*?)[\s\n\r]*$/$1\n$settings{$field_name}->{footer}/s;
					}
				}
			}

			if ( $result_txt ) {
				$template_txt =~s/_($field_name)_/$result_txt/i;	
			} else {
				$template_txt =~s/\n\s*_($field_name)_|_($field_name)_//i;
			}
		} else {
			$template_txt =~s/_($field_name)_//;
		}	
	}

	return trim_text $template_txt;
}

sub setNewlines {
	my ($self, $text, $margin, $width) = @_;
	my $maxlen = $width - $margin or croak "invalid maxlen 0";
	return "TEMPLATE ERROR: Do not inline block fields:\n$text" if $maxlen < 10;

	if ($text =~ /\r\n/) {
		# Text has DOS line endings. Replace them...
		$text =~ s{\r\n}{\n}g;
		# ... run our magic ...
		$text = $self->setNewlines($text, $margin, $width);
		# ... and replace them back.
		$text =~ s{\n}{\r\n}g;
		return $text;
	}

	$text = decode_entities($text);

	# An old bug removed leading newlines. People may have gotten used to that.
	$text =~ s/^\n*//g;

	my @lines = split /\n/, $text, -1;

	@lines = map {
		my @sub_lines;
		while (length > $maxlen) {
			# Break on the last whitespace (excluding our self-inserted indentation) before $maxlen, or...
			s{^(.{1,$maxlen})\s}{} or

			# If we couldn't break on whitespace (i.e. there was none), assume we're dealing with a hyperlink that's
			# too long for one line. Try to break on the last slash before $maxlen, add indentation for the next line
			# (to indicate this is a url spanning multiple lines). Use null byte as placeholder for space, so we don't
			# trip over it on the next iteration.
			# Don't break in the first 4 characters because they might be our own indentation (\0\0\0).
			s{^(.{4,$maxlen})/}{\0\0\0/} or

			# If all else failed, just break at $maxlen, again adding indentation to indicate continuation of a long
			# word / hyperlink.
			s{^(.{$maxlen})}{\0\0\0};

			push @sub_lines, $1;
		}
		(@sub_lines, $_);
	} @lines;

	$text = join "\n", @lines;
	$text =~ s/\0/ /g;  # Convert the null bytes we inserted above to plain spaces.
	return encode_entities($text);
}

sub createPageBar {
	my ( $self, $my_page, $number_results, $max_results ) = @_;

	my $this_page  = ( $my_page ne '' ) ? $my_page : 1;
	my $start_page = 1;
	my $max_row    = 9;
	my $next_page  = $this_page + 1;
	my $last_page  = ceil( $number_results / $max_results );

	my @row = "$start_page" .. "$last_page";
	my $row_size = scalar(@row);
	my @button_row;

	if ( ( $row_size >= $max_row ) && ( ( $last_page - $this_page ) >= $max_row ) ) {
		my $new_lastpage = $this_page + $max_row;
		@button_row = "$this_page" .. "$new_lastpage";
	} elsif ( $row_size > $max_row ) {
		my $remainder = $row_size - $max_row;
		@button_row = "$remainder" .. "$row_size";
	} else {
		@button_row = @row;
	}

	my $nr_results_text
	  = $number_results==0 ? 'no results'
	  : $number_results==1 ? '1 result'
	  :                       $number_results.' results';

	return {
		next_page => $next_page,
		last_page => $last_page,
		button_row => \@button_row,
		number_results => $number_results,
		number_results_text => $nr_results_text,
		my_page => $my_page
	};
}

sub sortAnyCase {
	return lc($a) cmp lc($b);
}

1;

=head1 NAME 

Taranis::Template

=head1 SYNOPSIS

  use Taranis::Template;

  my $obj = Taranis::Template->new( config => $oTaranisConfig );

  $obj->addTemplate( %template );

  $obj->createPageBar( $page_number, $number_of_results, $maximum_results );

  $obj->deleteTemplate( $template_id );

  $obj->getTemplate( %where );

  $obj->getTypeIds( @publication_type_names );

  $obj->processPreviewTemplate( $publication, $publication_type, $publication_details_id, $publication_id, $line_width );

  $obj->processPreviewTemplateRT( publication => $publication, publication_type => $publication_type, form_data => \%form_data, line_width => $line_width );

  $obj->processPublicationTemplate( $publication_template_string, $tab_name );

  $obj->processPublicationTemplateText( $json_str, $tab_name );

  $obj->processTemplateWithHeaders( $template_filename, \%template_variables );

  $obj->processTemplate( $template, \%template_variables, $noprint );

  $obj->setNewlines( $text, $margin, $width );

  $obj->setTemplate( id => $template_id, %template );

  $obj->sortAnyCase( @list );

=head1 DESCRIPTION

Add, edit remove and process templates. Uses Template Toolkit.

=head1 METHODS

=head2 new( config => $oTaranisConfig )

Constructor for the Taranis::Template module.

    my $obj = Taranis::Template->new( config => $oTaranisConfig ):

Creates a new database handler which can accessed by:

    $obj->{dbh};

Creates a new SQL::Abstract::More object which can be accessed by:

    $obj->{sql};
	
Clears error message for the new object. Can be accessed by:

    $obj->{errmsg};

Adds the configuration object << $objTaranisConfig >>:

    $obj->{config}

Also creates new V-Methods to be used in templates:

=over

=item *

decodeEntity: SCALAR context, runs &decode_entities

=item *

keysReverseSortByValue: HASH context

=item *

durationText: SCALAR context, calculates the duration of two timestamps

=item *

displayAssessStatus: SCALAR context, converts status number to status text

=item *

displayAnalyzeRating: SCALAR context, converts rating number to rating text

=item *

displayPublicationStatus: SCALAR context, converts status number to status text

=item *

displayTLPColor: SCALAR context, converts TLP color code to color name

=item *

displayDossierStatus: SCALAR context, converts status number to status text

=item *

displayReportContactLogType: SCALAR context, converts log type number to log type text

=item *

displayReportIncidentLogStatus: SCALAR context converts log status number to log status text

=item *

stripTags: SCALAR context, strips HTML tags

=item *

stripSeconds: SCALAR context, strips seconds and everything that follows from timesstamp

=back 

Returns the blessed object.

=head2 addTemplate( %template )

Adds publication templates.

    $obj->addTemplate( title => "template title", type => 3, template => "<publication><template>my publication template text</template></publication>" );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 createPageBar( $page_number, $number_of_results, $maximum_results )

Generates all data to generate a page bar with template 'page_bar.tt'.

Parameters are:

=over

=item *

$page_number = the page number of the current page.

=item *

$number_of_results = the total number of results.

=item *

$maximum_results = the maximum number of results per page.

=back

    $obj->createPageBar( 1, 1000, 100 );

The calling for processing of the page_bar.tt should be done within a template:

    [% PROCESS page_bar.tt %] 

Returns a collection of values which should be passed along via C<< $vars->{page_bar} >>. Where C<$vars> is the second argument of method processTemplateWithHeaders():
  
    $vars->{page_bar} = $obj->createPageBar( 1, 1000, 100 );

=head2 deleteTemplate( $template_id )

Deletes a publication template. Parameter C<$template_id> is mandatory.

    $obj->deleteTemplate( 3 );

If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getTemplate( %where )

Executes a SELECT statement on table C<publication_template>.

For retrieving one specific template:

    $obj->getTemplate( id => 3 );

For retrieving all templates:

    $obj->getTemplate();
	
The result of the SELECT statement can be retrieved by using getObject() and nextObject().
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.

=head2 getTypeIds( @publication_type_names )

Retrieves the ID's of publication types.

    $obj->getTypeIds( [ 'Advisory (email)', 'End-of-Week (email)' ] );

Returns an ARRAY reference. Sets $errmsg of this object to Taranis::Database->{db_error_msg} if database execution fails. Returns a list of ID's.

=head2 processPreviewTemplate( $publication, $publication_type, $publication_details_id, $publication_id, $line_width )

Creates the publication text from publication template. 
  
Parameters are:

=over

=item *

$publication = publication type, for instance 'advisory' or 'eow'

=item *

$publication_type = publication subtype, for instance 'email' or 'update'

=item *

$publication_details_id = publication details id

=item *

$publication_id = publication id

=item *

$line_width = the character width of the resulting text

=back

    $obj->processPreviewTemplate( "advisory", "email", 34, 76 );

The preview template deviates from the publication template on the contents of the <fields> tags.

Within the <fields> tag the content of the placeholders, set in the <template> tag as '_placeholder_', is specified. 
The tag name for the placeholder is the same as the placeholder but without the surrounding _ (underscore).
The type attribute is mandatory and can be set to 'database', 'settings' or 'replace' (see below).
  
B<type="database">

For replacing the placeholder with the data from one column from a specific table. The child element is <tbl/>. With I<type="database"> at least two <tbl/> children are needed. One with I<type="key"> and one with I<type="select"> or I<type="select_date">. 

=item I<type="key"> is for specifying the column and table to use in th WHERE clause of the SQL statement. The column is specified with an attribute of the <tbl> element: I<column="my_column_name">. The table is specified as the content of the <tbl> element. Note: So far only the values of the publication id, advisory id and end-of-week id are available in this routine. 

=item I<type="select"> is for specifying the column and table you want to use as data to replace the placeholder with. Column and table specification are the same as I<type="key">.

=back

Other options 

=item I<type="select_date"> is the same as I<type="select">, only in this case a date is being retrieved from the database and is formatted as 'YYYYMMDD' (eg. 20090615).

=item I<type="join1"> & I<type="join2"> is for spcifying the tables to 'join'. Startingpoint is always the table publication, from there on every join is possible if there are matching columns. The column on which to join tables is specified by I<column="my_column_name">. The table is specified as the content of the <tbl> element.

=back

Example:

  <fld_author type="database">
    <tbl type="select" column="fullname">users </tbl>
    <tbl type="key" column="id">publication </tbl>
    <tbl type="join1" column="created_by">publication </tbl>
    <tbl type="join2" column="username">users </tbl>
  </fld_author> 

B<type="settings">

Can be used for specifying certain settings. At this moment only one setting is implemented, I<type="heading">. The child element is <setting/> 

=item I<type="heading"> is for specifying a heading title that will be placed above the placeholder. The actual title is specified as the content of the <setting> element. 

=item I<type="footer"> is for specifying a footer that will be place under the placeholder.

=back

Example:

  <fld_update type="database">
    <tbl type="key" column="id">publication_advisory </tbl>
    <tbl type="select" column="update">publication_advisory </tbl>
  </fld_update>
  
  <fld_update type="settings">
    <setting type="heading">Update </setting>
  </fld_update>

B<type="replace">

For specifying replacement values for the data that is retrieved from the database. The child element is <rp/>. The original value is set using the attribute I<original_value>. The replacement value is specified as the content of the <rp> element.

=item I<original_value="my_value"> 

Example:

  <fld_damage type="replace">
    <rp original_value="1">high </rp>
    <rp original_value="2">medium </rp>
    <rp original_value="3">low </rp>
  </fld_damage>  

Note: all placeholders with no values to replace will be removed from the template.

Returns the complete template text.

=head2 processPreviewTemplateRT( publication => $publication, publication_type => $publication_type, form_data => \%form_data, line_width => $line_width )

Does the same as processPreviewTemplate() except it processes the data set by parameter C<form_data> instead of data from database.

    $obj->processPreviewTemplateRT( publication => 'advisory', publication_type => 'advisory (email)', form_data => { ... }, line_width => 70 );

Returns the complete template text.

=head2 processPublicationTemplate( $publication_template_string, $tab_name )

Processes the publication template before it is processed by processTemplateWithHeaders. Parameter C<$tab_name> can be used to specify the destination.

    $obj->processPublicationTemplate( "<publication><template>my publication template text</template></publication>",  );

Note: the template text should always start and close with the publication tag.

When processing the publication template all errors are concatenated into C<< $obj->{errmsg} >> of this object.

Returns an string containing HTML.

=head2 processPublicationTemplateText( $json_str, $tab_name )

Processes the template result.
 
Where sub processPublicationTemplate() creates the HTML which is declared within the C<< <fields> >> tags, processPublicationTemplateText() creates the resulting text (declared within the C<< <template> >> tags) with the input from the HTML input fields.
  
Parameters are:

=over

=item *

$json_str = JSON string which holds at least the following data:

=item I<template_id, to select a template from the database>

=item I<result_location, the destination of the resulting text>

=item I<original_txt, the text already present in the destination field (result_location)>

=item *

$tab_name = name of the tab where the template is used on
 
=back

    $obj->processPublicationTemplateText( {"tab_summaryfld_title":"test","template_id":"24","result_location":"tab_summary_txt","original_txt":"original text from textfield"}, "tab_summary" );

Note: does sorting of headings that begin with '-=' and end with '=-'. 

Returns the complete text for the result location and also the name of the result location.

=head2 processTemplateWithHeaders( $template_filename, \%template_variables )

Processes the template files with Template Toolkit.
  
Parameters are:

=over

=item *

$template_filename = filename of the template

=item *

%template_variables = the variables that are used in the template file

=back

    $obj->processTemplateWithHeaders( "my_template_file.tt", { my_var_name => "my value", etc... } );

Note: this method also turns off browser caching by adjusting the header and sets the webroot and scriptroot into $var if it is not present. 
  
Returns the template in HTML format. If Template Toolkit produces an error message the error is put in C<< $obj->{errmsg} >>.

=head2 processTemplate( $template, \%template_variables, $noprint )

Processes a template without adding content headers.
  
Parameters are:

=over

=item *

$template = the template file name

=item *

%template_variables = the variables used in the template

=item *

$noprint = when set to FALSE will return Template::process(), if set to TRUE will return HTML

=back

    $obj->processTemplate( "template.tt", \%vars, 'noprint');

=head2 setNewlines( $text, $margin, $width )

Formats a text with newline characters.
  
Parameters are:

=over

=item *

$text = plain text

=item *

$margin = the margin on the left side of the text. This will only shorten the width of the text. 

=item *

$width = the width of the text (or line length).

=back

  $obj->setNewlines( '...', 3, 71 );

Returns HTML encoded text.

=head2 setTemplate( id => $template_id, %template )

Updates publication templates. Parameter C<id> is mandatory.

    $obj->setTemplate( id => 4, title => "my new title" );
	
If successful returns TRUE. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< Taranis::Database->{db_error_msg} >>.	

=head2 sortAnyCase( @list )

For case insensitive sorting.

    $obj->sortAnyCase( ['banana', 'peach', 'Apple'] ); 

Returns an sorted ARRAY.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<Invalid parameter!>

Caused by setTemplate() and deleteTemplate() given parameter is invalid.
You should check input parameters.

=item *

I<Delete failed, corresponding id not found in database.>

Caused by deleteTemplate() when there is no template that has the specified template ID. 
You should check the given template ID parameter. 

=item *

I<XML parse error. Please check the publication template syntax.>

Caused by processPublicationTemplate(), processPublicationTemplateText(), processPreviewTemplate() and processPreviewTemplateRT() when given template cannot be parsed by Perl module XML::Simple.
You should check the XML syntax of the given content.

=back

=cut
