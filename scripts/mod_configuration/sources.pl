#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis::Database qw(withTransaction);
use Taranis::Sources;
use Taranis::Parsers;
use Taranis::Template;
use Taranis qw(:all);
use Taranis::Category;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use Taranis::Error;
use Taranis::Collector::Administration;
use Taranis::Collector::HTMLFeed;
use Taranis::Collector::Twitter;
use Taranis::Collector::XMLFeed;
use Taranis::Users qw();
use Taranis::Wordlist;
use Image::Size;
use HTML::Entities qw(decode_entities);
use Encode;
use Encode::IMAPUTF7;
use Mail::IMAPClient;
use Mail::POP3Client;
use JSON;

my @EXPORT_OK = qw(
	displaySources openDialogNewSource openDialogSourceDetails
	saveNewSource saveSourceDetails deleteSource getSourceItemHtml
	testSourceConnection testMailServerConnection
	enableDisableSource searchSources testTwitterConnection
);

sub sources_export {
	return @EXPORT_OK;
}

sub displaySources {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisSources = Taranis::Sources->new( Config );
	my $oTaranisCategory = Taranis::Category->new( Config );

	my ( %uniqueCategory, @categoryIds, @categories );

	if ( right( "particularization" ) ) {
		foreach my $category ( @{ right("particularization") } ) {

			$category = lc( $category );

			if ( !exists( $uniqueCategory{ $category } ) ) {
				$uniqueCategory{ $category} = 1;

				my $categoryId = $oTaranisCategory->getCategoryId( $category );
				push @categories, { id => $categoryId, name => $category };
			}
		}
	} else {
		@categories = $oTaranisCategory->getCategory( is_enabled => 1 );
	}

	$vars->{categories} = \@categories;
	my $oTaranisCollectorAdministration = Taranis::Collector::Administration->new( Config );
	@{ $vars->{collectors} } = $oTaranisCollectorAdministration->getCollectors();

	foreach my $category ( @categories ) {
		push @categoryIds, $category->{id};
	}

	my $resultCount = $oTaranisSources->getSourcesCount( category => \@categoryIds );
	my $sources = $oTaranisSources->getSources( category => \@categoryIds, limit => 100, offset => 0 );

	$vars->{sources} = $sources;
	$vars->{filterButton} = 'btn-sources-search';
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( 1, $resultCount, 100 );

	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $htmlContent = $oTaranisTemplate->processTemplate('sources.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('sources_filters.tt', $vars, 1);

	my @js = ('js/sources.js', 'js/sources_import_export.js');

	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewSource {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");

	if ( $writeRight ) {
		$vars = getSourcesSettings();
		$vars->{custom_collector_modules} = getCustomCollectorModules();
		$tpl = 'sources_details.tt';
	} else {
		$vars->{message} = 'No permission...';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => { writeRight => $writeRight }
	};
}

sub openDialogSourceDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $oTaranisTemplate = Taranis::Template->new;

	my $writeRight = right("write");

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};

		my $oTaranisError = Taranis::Error->new( Config );
		my $oTaranisSources = Taranis::Sources->new( Config );

		$vars = getSourcesSettings();

		my $source = $oTaranisSources->getSource( $id );

		$vars->{custom_collector_modules} = getCustomCollectorModules();
		$vars->{source} = $source;
		$vars->{sourceWordlists} = $oTaranisSources->getSourceWordlist( source_id => $id );
		$vars->{collector_errors} = $oTaranisError->getErrorsById( $source->{digest} );

		$tpl = 'sources_details.tt';

	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {
			writeRight => $writeRight,
			id => $id
		}
	};
}

sub saveNewSource {
	my ( %kvArgs) = @_;
	my ( $message, $id, $sourceName, $digestAlreadyExists );
	my $saveOk = 0;

	if ( right("write") ) {
		my $oTaranisSources = Taranis::Sources->new( Config );
		for ( $kvArgs{protocol} ) {
			if (/(http|https)/) {
				delete $kvArgs{mailbox};
				delete $kvArgs{archive_mailbox};
				delete $kvArgs{delete_mail};
				delete $kvArgs{username};
				delete $kvArgs{password};
				delete $kvArgs{use_starttls};
			} elsif (/(imap|imaps)/) {
				$kvArgs{url} = '';
				$kvArgs{parser} = undef;
				delete $kvArgs{delete_mail};
			} elsif (/(pop3|pop3s)/) {
				$kvArgs{url} = '';
				$kvArgs{parser} = undef;
				delete $kvArgs{mailbox};
				delete $kvArgs{archive_mailbox};
				delete $kvArgs{use_starttls};
			}
		}

		$sourceName = ( $kvArgs{'source-icon'} =~ /^1$/ )
			? sanitizeInput( "filename", $kvArgs{new_sourcename} )
			: sanitizeInput( "filename", $kvArgs{sourcename} );

		# add a leading slash on url part if it's not there
		if ( $kvArgs{url} !~ /^\// ) {
			$kvArgs{url} = '/' . $kvArgs{url};
		}

		# delete protocol,port nr, trailing slash and url from host/domain part
		# http://www.somewhere.com:8080/feed.xml becomes www.somewhere.com
		$kvArgs{host} =~ s/^[a-zA-Z]{3,6}:\/{1,3}//; # http:// etc...
		$kvArgs{host} =~ s/[:\d+]*\/.*$//;           # :80/blah.html
		$kvArgs{host} =~ s/:\d+$//;                  # :80
		$kvArgs{host} =~ s/\/.*$//;                  # / or /blah.xml

		my $addSlashes = ( $kvArgs{protocol} =~ /^(imap|pop3)/i ) ? '://' : '';

		my $full_url = $kvArgs{protocol} . $addSlashes . $kvArgs{host};

		if ($kvArgs{port} && !(($kvArgs{port} == 80 && $kvArgs{protocol} == 'http://') or ($kvArgs{port} == 443 && $kvArgs{protocol} == 'https://'))) {
			$full_url .= ':' . $kvArgs{port};
		}

		$full_url .= $kvArgs{url};

		my $useForDigest = "";
		for ( $kvArgs{protocol} ) {
			if ( /^imap/ ) {
				$useForDigest = $kvArgs{mailbox} . $kvArgs{username};
			} elsif ( /^pop3/ ) {
				$useForDigest = $kvArgs{username};
			} else {
				$useForDigest = $kvArgs{url};
			}
		}

		my $additionalConfigJSON;
		if ( $kvArgs{collector_module} ) {
			my $additionalConfig = {};

			my $collectorModules = getCustomCollectorModules();
			my $configKeys = $collectorModules->{ $kvArgs{collector_module} };

			if (ref $configKeys eq 'ARRAY') {
				$additionalConfig->{collector_module} = $kvArgs{collector_module};

				foreach my $configKey ( @$configKeys ) {
					$additionalConfig->{$configKey} = $kvArgs{$configKey} // '';
				}
			}
			$additionalConfigJSON = to_json( $additionalConfig );
			$useForDigest .= $additionalConfigJSON;
		}

		my $digest = textDigest($kvArgs{host} . $useForDigest);
		my $clusteringEnabled = ( $kvArgs{clustering_enabled} ) ? 1 : 0;
		my $containsAdvisory = ( $kvArgs{contains_advisory} ) ? 1 : 0;
		my $createAdvisory = ( $kvArgs{create_advisory} ) ? 1 : 0;
		my $takeScreenshot = ( $kvArgs{take_screenshot} ) ? 1 : 0;
		my $useStartTLS = ( $kvArgs{use_starttls} ) ? 1 : 0;
		my $useKeywordMatching = ( $kvArgs{use_keyword_matching} ) ? 1 : 0;
		my $rating = ( $kvArgs{rating} >= 0 && $kvArgs{rating} <= 100 ) ? $kvArgs{rating} : 50;

		if ( $kvArgs{'source-icon'} eq 1 ) {
			my $filename = scalarParam("new_icon");
			my $fh   = CGI->upload( $filename );
			my $mime = CGI->upload_info( $filename, 'mime' );
			my $size = CGI->upload_info( $filename, 'size' );

			if($mime eq 'image/gif' && $size < 5120 ) {
				checkIconImageDimensions($fh) && saveIconImage($fh, $sourceName)
					or $message = "Incorrect image selected. The Image icon must be 72 x 30 pixels (wxh), of type 'gif', and should not exceed 5 Kb.";
			}
		}

		# There are three possibilities:
		#  1. the source is totally unused
		#  2. the source has a single use, old style: without cat
		#  3. the source can be found with category extension
		# We have to maintain the existing "old style", because it is
		# used *everywhere*.

		my $category = $kvArgs{category};    # actually its id, not name
		if(!$message) {
			my $extended_digest  = "$digest;$category";

			my $source_old_style = ($oTaranisSources->getSources(
				digest      => $digest,
				deleted     => 'ANY',
			) || [])->[0];

			my $source_new_style = ($oTaranisSources->getSources(
				digest       => $extended_digest,
				's.category' => $category,
				deleted      => 'ANY',
			) || [])->[0];

			if($source_new_style) {
				# if in new style, it's more specific
				if($source_new_style->{deleted}) {
					$digest = $digestAlreadyExists = $extended_digest;
					$id  = $source_new_style->{id};
				} else {
					$message = 'The source in the same category already exists (1)';
				}
			} elsif(!$source_old_style) {
				# new source, not yet in use
				$digest = $extended_digest;
			} elsif($source_old_style->{categoryid} ne $category) {
				# new source, other category
				$digest = $extended_digest;
			} elsif($source_old_style->{deleted}) {
				# revive deleted source/category combination
				$digestAlreadyExists = $digest;
				$id      = $source_old_style->{id};
			} else {
				$message = 'The source in the same category already exists (2)';
			}

			if($digestAlreadyExists) {
				$message = 'The source in this category already exists, but is disabled.  Do you want to reinstate it with the new settings?';
			}
		}

		if(!$message) {
			my $dbh      = $oTaranisSources->{dbh};
			$dbh->startTransaction();

			if (
				$oTaranisSources->addElement(
					sourcename => $sourceName,
					checkid => $kvArgs{checkid},
					digest => $digest,
					host => $kvArgs{host},
					mailbox => $kvArgs{mailbox},
					mtbc => $kvArgs{mtbc},
					mtbc_random_delay_max => $kvArgs{mtbc_random_delay_max} ||0,
					parser => $kvArgs{parser},
					password => $kvArgs{password},
					port => $kvArgs{port},
					protocol => $kvArgs{protocol},
					status => $kvArgs{status},
					url => $kvArgs{url},
					fullurl => $full_url,
					username => $kvArgs{username},
					category => $category,
					enabled => 1,
					archive_mailbox => $kvArgs{archive_mailbox},
					delete_mail => $kvArgs{delete_mail},
					language => $kvArgs{language},
					clustering_enabled => $clusteringEnabled,
					contains_advisory => $containsAdvisory,
					create_advisory => $createAdvisory,
					advisory_handler => $kvArgs{advisory_handler} || undef,
					take_screenshot => $takeScreenshot,
					collector_id => $kvArgs{collector} || undef,
					use_starttls => $useStartTLS,
					use_keyword_matching => $useKeywordMatching,
					additional_config => $additionalConfigJSON,
					rating => $rating
				)
			) {
				$id = $dbh->getLastInsertedId('sources');

				my @wordlist1 = flat $kvArgs{wordlist1};
				my @wordlist2 = flat $kvArgs{wordlist2};

				my %wordlistsCheck;
				if ( !$message && @wordlist1 && @wordlist2 ) {
					ADDWORDLISTS:
					for( my $i = 0; $i < @wordlist1; $i++ ) {

						if (
							$wordlist1[$i]
							&& $wordlist1[$i] ne $wordlist2[$i]
							&& !exists( $wordlistsCheck{ $wordlist1[$i] . $wordlist2[$i] } )
						) {
							$wordlistsCheck{ $wordlist1[$i] . $wordlist2[$i] } = 1;
							my %insert = (
								source_id => $id,
								wordlist_id => $wordlist1[$i]
							);

							$insert{and_wordlist_id} = $wordlist2[$i] if ( $wordlist2[$i] );

							if ( !$oTaranisSources->addSourceWordlist( %insert ) ) {
								$message = $oTaranisSources->{errmsg};
								last ADDWORDLISTS;
							}
						}
					}
				}

				$dbh->commitTransaction();
			} else {
				$message = $oTaranisSources->{errmsg};
				$dbh->rollbackTransaction();
			}
		}
	}

	$saveOk = 1 if !$message;
	if ( $saveOk && !$digestAlreadyExists ) {
		setUserAction( action => 'add source', comment => "Added source '$sourceName'");
	} elsif ( !$digestAlreadyExists ) {
		setUserAction( action => 'add source', comment => "Got error '$message' while trying to add source '$sourceName'");
	}

	return {
		params => {
			saveOk => $saveOk,
			digestAlreadyExists => $digestAlreadyExists,
			message => $message,
			id => $id,
			insertNew => 1
		}
	};
}

sub saveSourceDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id, $sourceName );
	my $saveOk = 0;


	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {

		$id = $kvArgs{id};
		my $oTaranisSources = Taranis::Sources->new( Config );

		$sourceName = $kvArgs{'source-icon'} eq 1
			? sanitizeInput( "filename", $kvArgs{new_sourcename} )
			: sanitizeInput( "filename", $kvArgs{sourcename} );

		for ( $kvArgs{protocol} ) {
			if (/(http|https)/) {
				delete $kvArgs{mailbox};
				delete $kvArgs{archive_mailbox};
				delete $kvArgs{delete_mail};
				delete $kvArgs{username};
				delete $kvArgs{password};
				delete $kvArgs{use_starttls};
			} elsif (/(imap|imaps)/) {
				$kvArgs{parser} = "xml";
				$kvArgs{url} = '';
				delete $kvArgs{delete_mail};
			} elsif (/(pop3|pop3s)/) {
				$kvArgs{parser} = "xml";
				$kvArgs{url} = '';
				delete $kvArgs{mailbox};
				delete $kvArgs{archive_mailbox};
				delete $kvArgs{use_starttls};
			}
		}

		# add a leading slash on url part if it's not there
		if ($kvArgs{url} !~ /^\// ) {
		   $kvArgs{url} = '/' . $kvArgs{url};
		}

		# delete protocol,port nr, trailing slash and url from host/domain part
		# http://www.somewhere.com:8080/feed.xml becomes www.somewhere.com
		$kvArgs{host} =~ s/^[a-zA-Z]{3,6}:\/{1,3}//; # http:// etc...
		$kvArgs{host} =~ s/[:\d+]*\/.*$//;           # :80/blah.html
		$kvArgs{host} =~ s/:\d+$//;                  # :80
		$kvArgs{host} =~ s/\/.*$//;                  # / or /blah.xml

		my $orig_digest = $kvArgs{digest};

		my $useForDigest = "";
		for ( $kvArgs{protocol} ) {
			if ( /^imap/ ) {
				$useForDigest = $kvArgs{mailbox} . $kvArgs{username};
			} elsif ( /^pop3/ ) {
				$useForDigest = $kvArgs{username};
			} else {
				$useForDigest = $kvArgs{url};
			}
		}

		my $additionalConfigJSON;
		if ( $kvArgs{collector_module} ) {
			my $additionalConfig = {};

			my $collectorModules = getCustomCollectorModules();
			my $configKeys = $collectorModules->{ $kvArgs{collector_module} };

			if ( ref $configKeys eq 'ARRAY') {
				$additionalConfig->{collector_module} = $kvArgs{collector_module};

				foreach my $configKey ( @$configKeys ) {
					$additionalConfig->{ $configKey } = ( exists( $kvArgs{$configKey} ) )
						? $kvArgs{$configKey}
						: '';
				}
			}
			$additionalConfigJSON = to_json( $additionalConfig );
			$useForDigest .= $additionalConfigJSON;
		}

		my $new_digest = textDigest($kvArgs{host} . $useForDigest);

		my $addSlashes = ( $kvArgs{protocol} =~ /^(imap|pop3)/i ) ? '://' : '';

		my $full_url = $kvArgs{protocol} . $addSlashes . $kvArgs{host};

		if ($kvArgs{source} && !(($kvArgs{port} == 80 && $kvArgs{protocol} == 'http://') or ($kvArgs{port} == 443 && $kvArgs{protocol} == 'https://'))) {
			$full_url .= ':' . $kvArgs{port};
		}

		$full_url .= $kvArgs{url};

		my $clusteringEnabled = ( $kvArgs{clustering_enabled} ) ? 1 : 0;
		my $containsAdvisory = ( $kvArgs{contains_advisory} ) ? 1 : 0;
		my $createAdvisory = ( $kvArgs{create_advisory} ) ? 1 : 0;
		my $takeScreenshot = ( $kvArgs{take_screenshot} ) ? 1 : 0;
		my $useStartTLS = ( $kvArgs{use_starttls} ) ? 1 : 0;
		my $useKeywordMatching = ( $kvArgs{use_keyword_matching} ) ? 1 : 0;
		my $rating = ( defined( $kvArgs{rating} ) && $kvArgs{rating} >= 0 && $kvArgs{rating} <= 100 ) ? $kvArgs{rating} : 50;

		my $proceed = 1;
		if ( $kvArgs{'source-icon'} =~ /^1$/ ) {
			my $filename = scalarParam("new_icon");
			my $fh = CGI->upload( $filename );
			my $mime = CGI->upload_info( $filename, 'mime' ); # MIME type of uploaded file
			my $size = CGI->upload_info( $filename, 'size' ); # size of uploaded file

			if ( $mime eq 'image/gif' && $size < 5120 ) {
				$proceed = checkIconImageDimensions($fh) && saveIconImage($fh, $sourceName);
			} else {
				$proceed = 0;
			}
		}

		if ( $proceed ) {
			my %where = ( digest => $new_digest );
			if ( $orig_digest eq $new_digest || !$oTaranisSources->{dbh}->checkIfExists( \%where, 'sources' ) ) {

				my @currentWordlistsID = flat $kvArgs{source_wordlist_id};
				my %currentWordlistsIDHash = map { $_ => 1 } @currentWordlistsID;
				my @deleteSourceWordlists;
				my $linkedWordlists = $oTaranisSources->getSourceWordlist( source_id => $id );
				foreach my $linkedWordlist ( @$linkedWordlists ) {
					if ( !exists( $currentWordlistsIDHash{ $linkedWordlist->{id} } ) ) {
						push @deleteSourceWordlists, $linkedWordlist->{id};
					}
				}

				$oTaranisSources->{dbh}->startTransaction();

				if (
					!$oTaranisSources->setSource(
						id => $id,
						sourcename => $sourceName,
						checkid => $kvArgs{checkid},
						host => $kvArgs{host},
						mailbox => $kvArgs{mailbox},
						mtbc => $kvArgs{mtbc},
						mtbc_random_delay_max => $kvArgs{mtbc_random_delay_max} || 0,
						parser => $kvArgs{parser},
						password => $kvArgs{password},
						port => $kvArgs{port},
						protocol => $kvArgs{protocol},
						status => $kvArgs{status},
						url => $kvArgs{url},
						fullurl => $full_url,
						username => $kvArgs{username},
						category => $kvArgs{category},
						archive_mailbox => $kvArgs{archive_mailbox},
						delete_mail => $kvArgs{delete_mail},
						language => $kvArgs{language},
						clustering_enabled => $clusteringEnabled,
						contains_advisory => $containsAdvisory,
						create_advisory => $createAdvisory,
						advisory_handler => $kvArgs{advisory_handler} || undef,
						take_screenshot => $takeScreenshot,
						collector_id => $kvArgs{collector} || undef,
						use_starttls => $useStartTLS,
						use_keyword_matching => $useKeywordMatching,
						additional_config => $additionalConfigJSON,
						deleted => 0,
						rating => $rating
					)
				) {
					$message = $oTaranisSources->{errmsg};
					$oTaranisSources->{dbh}->rollbackTransaction();
				} else {

					DELETEWORDLISTS:
					foreach my $deleteWordlist ( @deleteSourceWordlists ) {
						if ( !$oTaranisSources->deleteSourceWordlist( id => $deleteWordlist ) ) {
							$message = $oTaranisSources->{errmsg};
							last DELETEWORDLISTS;
						}
					}

					my %wordlistsCheck;
					my @wordlist1 = flat $kvArgs{wordlist1};
					my @wordlist2 = flat $kvArgs{wordlist2};

					if ( !$message && @wordlist1 && @wordlist2 ) {
						ADDWORDLISTS:
						for( my $i = 0; $i < @wordlist1; $i++ ) {

							if (
								$wordlist1[$i]
								&& $wordlist1[$i] ne $wordlist2[$i]
								&& !exists( $wordlistsCheck{ $wordlist1[$i] . $wordlist2[$i] } )
							) {
								$wordlistsCheck{ $wordlist1[$i] . $wordlist2[$i] } = 1;
								my %insert = (
									source_id => $id,
									wordlist_id => $wordlist1[$i]
								);

								my %check = %insert;
								$insert{and_wordlist_id} = $wordlist2[$i] if ( $wordlist2[$i] );
								$check{and_wordlist_id} = ( $wordlist2[$i] ) ? $wordlist2[$i] : undef;

								if ( !$oTaranisSources->{dbh}->checkIfExists( \%check, 'source_wordlist' ) ) {

									if ( !$oTaranisSources->addSourceWordlist( %insert ) ) {
										$message = $oTaranisSources->{errmsg};
										last ADDWORDLISTS;
									}
								}
							}
						}
					}

					$oTaranisSources->{dbh}->commitTransaction();
				}

			} else {
				$message = "A source with the specified host and URL already exists.";
			}
		} else {
			$message = "Incorrect image selected. The Image icon must be 72 x 30 pixels (wxh), of type 'gif' and cannot exceed 5 kb.";
		}

	} else {
		$message = 'No permission';
	}

	$saveOk = 1 if ( !$message );
	if ( $saveOk ) {
		setUserAction( action => 'edit source', comment => "Edited source '$sourceName'");
	} else {
		setUserAction( action => 'edit source', comment => "Got error '$message' while trying to edit source '$sourceName'");
	}

	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			insertNew => 0
		}
	};
}

sub deleteSource {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;

	my $oTaranisSources = Taranis::Sources->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my $source = $oTaranisSources->getSource( $id );

		withTransaction {
			# delete linked wordlists, if there are any
			if (
				$oTaranisSources->{dbh}->checkIfExists( { source_id => $id }, 'source_wordlist')
				&& !$oTaranisSources->deleteSourceWordlist( source_id => $id )
			) {
				$message = $oTaranisSources->{errmsg};
			}

			# delete source
			if ( !$message && !$oTaranisSources->deleteSource( $id ) ) {
				$message = $oTaranisSources->{errmsg};
			}
		};

		if ( $message ) {
			setUserAction( action => 'delete source', comment => "Got error '$message' while trying to delete source '$source->{sourcename}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete source', comment => "Deleted source '$source->{sourcename}'");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $id
		}
	};
}

sub getSourceItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisSources = Taranis::Sources->new( Config );

	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};

	my $source = $oTaranisSources->getSource( $id );

	if ( $source) {
		$vars->{source} = $source;
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;

		$tpl = 'sources_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};
}

sub searchSources {
	my ( %kvArgs) = @_;
	my ( $vars, %search );


	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisSources = Taranis::Sources->new( Config );
	if ( exists( $kvArgs{category} ) && $kvArgs{category} =~ /^\d+$/ ) {
		$search{category} = [ $kvArgs{category} ];
	}

	if ( exists( $kvArgs{collector} ) && $kvArgs{collector} =~ /^\d+$/ ) {
		$search{collector_id} = [ $kvArgs{collector} ];
	}

	if ( exists( $kvArgs{search} ) && $kvArgs{search} ) {
		$search{-or} = {
			fullurl => {'-ilike' => '%' . trim($kvArgs{search}) . '%'},
			sourcename => {'-ilike' => '%' . trim($kvArgs{search}) . '%'}
		}
	}

	my $resultCount = $oTaranisSources->getSourcesCount(	%search );

	my $pageNumber = val_int $kvArgs{'hidden-page-number'} || 1;
	my $hitsperpage = val_int $kvArgs{hitsperpage} || 100;
	my $offset = ( $pageNumber - 1 ) * $hitsperpage;

	$search{limit} = $hitsperpage;
	$search{offset} = $offset;

	my $sources = $oTaranisSources->getSources( %search );

	$vars->{sources} = \@$sources;
	$vars->{page_bar} = $oTaranisTemplate->createPageBar( $pageNumber, $resultCount, $hitsperpage );
	$vars->{filterButton} = 'btn-sources-search';
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;

	my $htmlContent = $oTaranisTemplate->processTemplate('sources.tt', $vars, 1);

	return { content => $htmlContent };
}

sub testSourceConnection {
	my ( %kvArgs) = @_;
	my ( $message );
	my $checkOk = 0;

	my $testOnly = $kvArgs{testOnly};

	my %source = (
		host => $kvArgs{host},
		url => $kvArgs{url},
		protocol => $kvArgs{protocol},
		port => $kvArgs{port},
		parser => $kvArgs{parser},
		sourcename => 'checkXmlHtmlSource'
	);

	if ( $kvArgs{collector_module} && $kvArgs{collector_module} =~ /^Taranis::Collector::/ ) {
		my $collectorModules = getCustomCollectorModules();
		if ( exists( $collectorModules->{ $kvArgs{collector_module} } ) ) {

			my $collectorModule = $kvArgs{collector_module};

			my $collector = eval {
				(my $collectorModulePath = "$collectorModule.pm") =~ s{::}{/}g;
				require $collectorModulePath;
				$collectorModule->new( Config );
			};

			if ( $collector->can('testCollector') ) {
				my $configKeys = $collectorModules->{ $collectorModule };
				if (ref $configKeys eq 'ARRAY') {
					foreach my $configKey ( @$configKeys ) {
						$source{$configKey} = decode_entities($kvArgs{$configKey} || '');
					}
				}
				$message = $collector->testCollector( \%source );

			} else {
				$message = "This module is missing test functionality.";
			}
		} else {
			$message = "This module can not be used.";
		}

		$testOnly = 1;

	} else {

		my $httpCollector = ( $source{parser} =~ /^xml/ )
			? Taranis::Collector::XMLFeed->new( Config )
			: Taranis::Collector::HTMLFeed->new( Config );

		$httpCollector->{no_db} = 1;
		$httpCollector->{collector}->{no_db} = 1;

		my $fullurl = $source{protocol} . $source{host};

		if ($source{port} && !(($source{port} == 80 && $source{protocol} == 'http://') or ($source{port} == 443 && $source{protocol} == 'https://'))) {
			$fullurl .= ':' . $source{port};
		}
		$fullurl .= $source{url};

		my $sourceData = $httpCollector->{collector}->getSourceData( $fullurl, \%source );

		my $feed_links;

		$feed_links = $httpCollector->collect( $sourceData, \%source );

		if ( ref $feed_links ne 'ARRAY' ) {
			my $responseCode = $httpCollector->{collector}->{http_status_code};

			if ( $responseCode =~ /^20/ ) {
				$message = "Connection to source: OK. But retrieval of items FAILED.";
			} else {
				$message = "Connection to source: FAILED. Response: " . $httpCollector->{collector}->{http_status_line};
			}

		} else {
			$checkOk = 1;
			$message = "Connection and retrieval of items: OK";
		}
	}

	return {
		params => {
			checkOk => $checkOk,
			message => $message,
			testOnly => $testOnly
		}
	};
}

sub testMailServerConnection {
	my ( %kvArgs) = @_;
	my ( $message );
	my $checkOk = 0;

	my $server = $kvArgs{host};
	my $port = $kvArgs{port};
	my $protocol = $kvArgs{protocol};
	my $username = $kvArgs{username};
	my $password = $kvArgs{password};
	my $mailbox = encode 'IMAP-UTF-7', decode_entities $kvArgs{mailbox};
	my $archive_mailbox = encode 'IMAP-UTF-7', decode_entities $kvArgs{archive_mailbox};
	my $useStartTLS = ( $kvArgs{use_starttls} ) ? 1 : 0;

	my $id = $kvArgs{id};
	my $testOnly = $kvArgs{testOnly};

	if ( $protocol =~ /(imap|imaps)/i ) {
		my $imap = Mail::IMAPClient->new();

		$imap->Server( $server );
		$imap->User( $username ) if ( $username );
		$imap->Password( $password ) if ( $password );
		$imap->Port( $port ) if ( $port );
		$imap->Ssl( 1 ) if ( $protocol =~ /^imaps$/i );
		$imap->Starttls( 1 ) if ( $useStartTLS );
		$imap->Ignoresizeerrors( 1 );

		if ( $imap->connect() ) {

			if ( $imap->exists( $mailbox ) ) {
				$message = "Connection to mailbox: OK. ";
				$checkOk = 1;
			} else {
				$message = "Connection to mailbox: FAILED. ";
			}

			if ( $imap->exists( $archive_mailbox ) ) {
				$message .= "Connection to archive mailbox: OK. ";
			} else {
				$message .= "Connection to archive mailbox: FAILED. ";
				$checkOk = 0;
			}
			$imap->close();

		} else {
			$message = "Unable to connect to server. " . $imap->LastError();
		}
	} else {

		my $ssl = ( $protocol =~ /pop3s/i ) ? 1 : 0;

		$port = ( !$port && $protocol =~ /pop3s/i ) ? 995 : 110;

		my $pop3 = Mail::POP3Client->new(
			HOST => $server,
			USESSL => $ssl,
			USER => $username,
			PASSWORD => $password,
			PORT => $port
		);

		if ( $pop3->Connect() ) {
			$message = "Connection to server: OK.";
			$checkOk = 1;
		} else {
			$message = "Connection to server: FAILED. " . $pop3->Message();
		}

		$pop3->Close();
	}

	return {
		params => {
			checkOk => $checkOk,
			message => $message,
			id => $id,
			testOnly => $testOnly
		}
	};
}

sub enableDisableSource {
	my ( %kvArgs) = @_;
	my ( $message, $id, $enable );
	my $enableOk = 0;

	my $oTaranisSources = Taranis::Sources->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ && $kvArgs{enable} =~ /^(0|1)$/ ) {
		$id = $kvArgs{id};
		$enable = $kvArgs{enable};

		my $source = $oTaranisSources->getSource( $id );
		my $enableText = ( $enable ) ? 'enable' : 'disable';

		if ( !$oTaranisSources->setSource( id => $id, enabled => $enable ) ) {
			$message = $oTaranisSources->{errmsg};
			setUserAction( action => "$enableText source", comment => "Got error '$message' while trying to $enableText source '$source->{sourcename}'");
		} else {
			$enableOk = 1;
			setUserAction( action => "$enableText source", comment => ucfirst( $enableText ) . "d source '$source->{sourcename}'");
		}
	} else {
		$message = 'No permission';
	}

	return {
		params => {
			enableOk => $enableOk,
			message => $message,
			id => $id,
			enable => $enable
		}
	};
}

## HELPERS
sub getSourcesSettings {
	my $settings = {};

	my $oTaranisCategory = Taranis::Category->new( Config );
	my ( %uniqueCategory, @categories, @parsers );

	if ( right( "particularization" ) ) {
		foreach my $category ( @{ right("particularization") } ) {

			$category = lc( $category );

			if ( !exists( $uniqueCategory{ $category } ) ) {
				$uniqueCategory{ $category } = 1;
				my $categoryId = $oTaranisCategory->getCategoryId( $category );
				push @categories, { id => $categoryId, name => $category };
			}
		}
	} else {
		@categories = $oTaranisCategory->getCategory( is_enabled => 1 );
	}

	$settings->{categories} = \@categories;

	# get all sources from icon dir
	my $iconDirAbsolutePath = $ENV{SOURCE_ICONS} or die "ERROR: SOURCE_ICONS?";
	my @files;
	eval{
		my $dh;
		opendir $dh, $iconDirAbsolutePath;
		@files= sort (readdir $dh);
		closedir $dh;
	};

	if ( $@ ) {
		$settings->{sources} = [];
	} else {

		my @sources;
		foreach my $file (@files) {
			if ( $file !~ /^\./ && $file =~ /\.gif$/ ) {
				$file =~ s/\.gif$//i;
				push @sources, $file;
			}
		}
		$settings->{sources} = \@sources;
	}

	my $oTaranisParsers = Taranis::Parsers->new( Config );
	$settings->{parsers} = $oTaranisParsers->getParsers();

	my $oTaranisUsers = Taranis::Users->new( Config );
	my $users = $oTaranisUsers->getUsersList();
	my @users;
	while ( $oTaranisUsers->nextObject() ) {
		my $user = $oTaranisUsers->getObject();
		push @users, { username => $user->{username}, fullname => $user->{fullname} }
	}

	$settings->{users} = \@users;

	my $oTaranisCollectorAdministration = Taranis::Collector::Administration->new( Config );
	@{ $settings->{collectors} } = $oTaranisCollectorAdministration->getCollectors();

	my $oTaranisWordlist = Taranis::Wordlist->new( Config );
	$settings->{wordlists} = $oTaranisWordlist->getWordlist();

	return $settings;
}

sub checkIconImageDimensions {
	my $fh = $_[0];

	my ( $img_x , $img_y ) = Image::Size::imgsize($fh);

	return $img_x == 72 && $img_y == 30;
}

sub saveIconImage {
	my $fh = $_[0];
	my $source_name = $_[1];

	die "Attempt to save invalid icon" unless checkIconImageDimensions($fh);

	my $iconDir   = $ENV{SOURCE_ICONS} or die "ERROR: SOURCE_ICONS?";
	my $filename  = $source_name.".gif";
	my $save_file = "$iconDir/$filename";
	my $newFh;
	open($newFh, ">", $save_file) or die "Can't open icon file for writing in $save_file";
	binmode $newFh;
	while(<$fh>) {
		print $newFh $_ or die "Write to icon file failed";
	}
	close $newFh;
}

sub getCustomCollectorModules {
	my %core_modules = map +($_ => 1), qw(
		Taranis::Collector::Administration Taranis::Collector::HTMLFeed
		Taranis::Collector::IMAPMail Taranis::Collector::POP3Mail
		Taranis::Collector::Statistics Taranis::Collector::TemplateModule
		Taranis::Collector::XMLFeed Taranis::Collector::GridDisplay
	);

	my %custom_modules;

	my $modules = scan_for_plugins 'Taranis::Collector';
	foreach my $module (keys %$modules) {
		next if $core_modules{$module};

		(my $path = "$module.pm" ) =~ s{::}{/}g;

		$custom_modules{$module} = eval {
			require $path;
			$module->getAdditionalConfigKeys
				if $module->can('getAdditionalConfigKeys');
		};
	}

	return \%custom_modules;
}

1;
