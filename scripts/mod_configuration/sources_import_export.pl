#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Template;
use Taranis::Sources;
use Taranis::Category;
use Taranis::Parsers;
use XML::Simple;
use Archive::Tar;
use HTML::Entities qw(decode_entities);

$Archive::Tar::WARN = 0;

my @EXPORT_OK = qw( openDialogImportExportSources importSources exportSources );

sub sources_import_export_export {
	return @EXPORT_OK;
}

sub openDialogImportExportSources {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");

	if ( $writeRight ) {
		my $ca = Taranis::Category->new( Config );
		my $pa = Taranis::Parsers->new( Config );

		@{ $vars->{categories} } = $ca->getCategory("is_enabled" => 1);

		my $parsers = $pa->getParsers();
		my @parsers_unsorted;
		if ( $parsers ) {
			for (my $i = 0; $i < @$parsers; $i++ ) {
				push @parsers_unsorted, $parsers->[$i]->{parsername};
			}
		}

		my @sorted_parsers = sort {$a cmp $b} @parsers_unsorted;
		$vars->{parsers} = \@sorted_parsers;
		$tpl = "sources_import_export.tt";

	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub importSources {
	my ( %kvArgs) = @_;
	my ( $tpl, $vars, $filename );

	my $tt = Taranis::Template->new;

	if ( right("write") ) {
		my ( $tar, $importSourcesXml, $importParsersXml );
		my $ca = Taranis::Category->new( Config );
		my $pa = Taranis::Parsers->new( Config );
		my $src = Taranis::Sources->new( Config );

		my $default_collector = $src->{dbh}->simple->query(<<'_COL')->list;
SELECT id FROM collector ORDER BY id ASC LIMIT 1
_COL

		$filename = scalarParam("import_file");
		my $fh = CGI->upload($filename);

		eval{
			$tar = Archive::Tar->new( $fh );
		};

		if ( !$tar ) {
			$vars->{error} = "Error: cannot read import file.";
		} else {

			eval{
				$importSourcesXml = $tar->get_content( "taranis.sources.xml" );
			};

			eval{
				$importParsersXml = $tar->get_content( "taranis.parsers.xml" );
			};

			if ( !$importSourcesXml ) {
				$vars->{error} = $tar->error();
			} else {

				if ( !$importParsersXml ) {
					$vars->{error} = "Missing taranis.parsers.xml.";
				} else {
					my $importParsers;

					eval{
						$importParsers = XMLin( $importParsersXml, SuppressEmpty => undef );
					};

					if ( $@ || !exists( $importParsers->{parser} ) ) {
						$vars->{error} = $@ || "Missing parser element in XML.";
					} else {

						my ( @failedParserImports, @successfulParserImports );
						my @parsers = flat $importParsers->{parser};

						PARSER:
						foreach my $parser ( @parsers ) {
							if ( !exists( $parser->{parsername} ) ) {
								$parser->{failReason} = "Missing mandatory field 'parsername' for import.";
								push @failedParserImports, $parser;
							} elsif ( $pa->{dbh}->checkIfExists( { parsername => $parser->{parsername} } , "parsers", "IGNORE_CASE" ) ) {
								$parser->{failReason} = "Parser already exists.";
								push @failedParserImports, $parser;
							} else {
								if ( !$pa->addParser( %$parser ) ) {
									$parser->{failReason} = "Import failed: $pa->{errmsg}.";
									push @failedParserImports, $parser;
								} else {
									push @successfulParserImports, $parser;
								}
							}
						}

						$vars->{successfulParserImports} = \@successfulParserImports;
						$vars->{failedParserImports} = \@failedParserImports;
					}
				}

				my $importSources;
				eval{
					$importSources = XMLin( $importSourcesXml, SuppressEmpty => undef );
				};

				if ( $@ || !exists( $importSources->{source} ) ) {
					$vars->{error} = $@ || "Missing source element in XML.";
				} else {

					my ( @failedSourceImports, @successfulSourceImports, @addedCategories );
					my $iconDir = $ENV{SOURCE_ICONS} or die "ERROR: SOURCE_ICONS?";
					my @sources = flat $importSources->{source};

					SOURCE:
					foreach my $source ( @sources ) {
						if (
							!exists($source->{protocol})   || !$source->{protocol} ||
							!exists($source->{mtbc})       || # 0 is a valid value for mtbc.
							!exists($source->{parser})     || !$source->{parser} ||
							!exists($source->{category})   || !$source->{category} ||
							!exists($source->{sourcename}) || !$source->{sourcename} ||
							!exists($source->{fullurl})    || !$source->{fullurl} ||
							!exists($source->{port})       || !$source->{port} ||
							!exists($source->{host})       || !$source->{host} ||
							!exists($source->{digest})     || !$source->{digest}
						) {
							$source->{failReason} = "Missing one or more mandatory fields for import.";
							push @failedSourceImports, $source;
						} elsif ( $src->{dbh}->checkIfExists( { digest => $source->{digest} } , "sources", "IGNORE_CASE" ) ) {
							$source->{failReason} = "Source already exists.";
							push @failedSourceImports, $source;
						} elsif ( !$src->{dbh}->checkIfExists( { parsername => $source->{parser} } , "parsers", "IGNORE_CASE" ) ) {
							$source->{failReason} = "Missing parser for this source.";
							push @failedSourceImports, $source;
						} else {
							$source->{collector_id} = $default_collector;
							my $category = $ca->getCategory( name => { -ilike => $source->{category} } );

							if ( !$category ) {
								if ( !$ca->addCategory( name => $source->{category} ) ) {
									$source->{failReason} = "Could not add category.";
									push @failedSourceImports, $source;
									next SOURCE;
								} else {
									push @addedCategories, $source->{category};
									$source->{category} = $ca->{dbh}->getLastInsertedId('category');
								}
							} else {
								$source->{category} = $category->{id};
							}

							foreach my $key ( keys %$source ) {
								if (ref $source->{$key} eq 'HASH' ) {
									$source->{$key} = undef;
								}
							}

							# boolean conversions
							for ( 'checkid', 'delete_mail', 'enabled', 'clustering_enabled', 'take_screenshot', 'use_starttls' ) {
								$source->{$_} = 1 if ( $source->{$_} =~ /^true$/ );
								$source->{$_} = 0 if ( $source->{$_} =~ /^false$/ );
							}

							if ( !$src->addSource( %$source ) ) {
								$source->{failReason} = "Import failed: $src->{errmsg}.";
								push @failedSourceImports, $source;
							} else {
								my $iconImage;
								my $sourceName = $source->{sourcename};

								eval{
									$iconImage = $tar->get_content( $sourceName . ".gif" );
								};

								if ( !$iconImage ) {
									$iconImage = $src->createSourceIcon( $sourceName );
								}

								eval{
									my $fh;
									open $fh, ">", "$iconDir/$source->{sourcename}.gif";
									print $fh $iconImage;
									close $fh;
								};

								if ( $@ ) {
									logErrorToSyslog( $@ );
								}

								push @successfulSourceImports, $source;
							}
						}
					}
					$vars->{categories} = \@addedCategories;
					$vars->{successfulSourceImports} = \@successfulSourceImports;
					$vars->{failedSourceImports} = \@failedSourceImports;
				}
			}
		}

		$tpl = 'sources_import.tt';
		setUserAction( action => 'import sources', comment => "Imported sources with file '$filename'");
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );

	return { dialog => $dialogContent };
}

sub exportSources {
	my ( %kvArgs ) = @_;

	my $src = Taranis::Sources->new( Config );
	my $pa = Taranis::Parsers->new( Config );

	my ( %where, $returnToBrowser, %parsersList, @parsersExport );

	if ( @{ $kvArgs{protocols} } > 0 ) {
		$where{protocol} = $kvArgs{protocols};
	}

	if ( @{ $kvArgs{categories} } > 0) {
		$where{category} = $kvArgs{categories};
	}

	if ( @{ $kvArgs{languages} } > 0 ) {
		$where{language} = $kvArgs{languages};
	}

	if ( @{ $kvArgs{parsers} } > 0) {
		$where{parser} = $kvArgs{parsers};
	}

	my $sources = $src->getSources( %where );
	my $tar = Archive::Tar->new;

	for ( my $i = 0; $i < @$sources; $i++ ) {

		# delete fields which can cause conflicts or are not in use
		for ( 'id', 'categoryid', 'collector_id', 'status', 'advisory_handler', 'contains_advisory', 'create_advisory', 'use_keyword_matching' ) {
			delete $sources->[$i]->{$_};
		}

		# boolean conversions
		for ( 'checkid', 'delete_mail', 'enabled', 'clustering_enabled', 'take_screenshot', 'use_starttls' ) {
			$sources->[$i]->{$_} = "true" if ( $sources->[$i]->{$_} =~ /^1$/ );
			$sources->[$i]->{$_} = "false" if ( $sources->[$i]->{$_} =~ /^0$/ );
		}

		$parsersList{ $sources->[$i]->{parser} } = 1;

		# decode all source details
		foreach my $key ( keys %{ $sources->[$i] }) {
			$sources->[$i]->{$key} = decode_entities( $sources->[$i]->{$key} );
		}
		my $sourceName = $sources->[$i]->{sourcename};

		# add icon to archive file
		my $iconName = "$sourceName.gif";
		$tar->add_data($iconName, $src->createSourceIcon($sourceName))
			unless $tar->contains_file($iconName);
	}

	my $xmlSourcesOut = ""  ;
	eval{
		$xmlSourcesOut = XMLout( { 'source' => $sources }, NoAttr => 1, RootName => 'sources', XMLDecl => 1 );
	};

	# add XML file to archive file
	$tar->add_data("taranis.sources.xml", $xmlSourcesOut );

	# collect parsers to export
	foreach my $parser ( keys %parsersList ) {
		my $parserDetails = $pa->getParser( $parser );
		push @parsersExport, $parserDetails if ( $parserDetails );
	}

	my $xmlParsersOut = ""  ;
	eval{
		$xmlParsersOut = XMLout( { 'parser' => \@parsersExport }, NoAttr => 1, RootName => 'parsers', XMLDecl => 1 );
	};

	# add XML file to archive file
	$tar->add_data("taranis.parsers.xml", $xmlParsersOut );

	$returnToBrowser->{content} = $tar->write();

	setUserAction( action => 'export sources', comment => "Exported sources");

	if ( !$@ ) {
		$returnToBrowser->{header} = "Content-Type: application/x-tar \n"
			. "Content-disposition: attachment; filename=taranis.sources.tar;\n\n";
		print $returnToBrowser->{header};
		print $returnToBrowser->{content};
	}

	return {};
}
1;
