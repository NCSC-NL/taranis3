#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Template;
use Taranis::Error;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use strict;
use Taranis qw(:util);

use HTML::Entities qw(encode_entities);

my @EXPORT_OK = qw( 
	displayCollectorLogging openDialogCollectorLoggingDetails
	deleteCollectorLogging searchCollectorLogging bulkDeleteCollectorLogging
);

sub module_collect_export {
	return @EXPORT_OK;
}

sub displayCollectorLogging {
	my ( %kvArgs) = @_;
	my ( $vars );
	
	my $tt = Taranis::Template->new;
	my $er = Taranis::Error->new( Config );

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	$er->loadCollection( offset => ( $pageNumber - 1 ) * 100 );
#	tie my %loggingPerSource, "Tie::IxHash";
	my @loggingItems;
	my $loggingCount = 0;
	while ( $er->nextObject() ) {
		my $record = $er->getObject();
		$record->{sourceid} = "STATSIMG" if ( !$record->{sourceid} );
#		if ( exists( $loggingPerSource{ $record->{sourceid} } ) ) {
#			if ( exists( $loggingPerSource{ $record->{sourceid} }->{$record->{error_code} } ) ) {
#				push @{ $loggingPerSource{ $record->{sourceid} }->{$record->{error_code} } }, { error => $record->{error}, datetime => $record->{datetime} };
#			} else {
#				$loggingPerSource{ $record->{sourceid} }->{$record->{error_code} } = [ { error => $record->{error}, datetime => $record->{datetime} }  ];
#			}
#		} else {
#			$loggingPerSource{ $record->{sourceid} } = {  
#				fullurl => $record->{fullurl},
#				sourcename => $record->{sourcename},
#				sourceid => $record->{sourceid},
#				$record->{error_code} => [ { error => $record->{error}, datetime => $record->{datetime} } ]
#			}
#		}
#		$loggingCount++;
		push @loggingItems, $record;
	}

#	foreach my $logging ( keys %loggingPerSource ) {
#		push @loggingItems, $loggingPerSource{ $logging };
#	}

	$vars->{loggingItems} = \@loggingItems;
	$vars->{error_codes} = $er->getDistinctErrorCodes();
	
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $er->{result_count}, 100 );
	$vars->{filterButton} = 'btn-collector-logging-search';
	$vars->{write_right} = right('write');
	$vars->{numberOfResults} = $loggingCount;
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('logging_module_collect.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('logging_module_collect_filters.tt', $vars, 1);
	
	my @js = ('js/logging_module_collect.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };		
}
	
sub openDialogCollectorLoggingDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );
	
	my $tt = Taranis::Template->new;
	my $er = Taranis::Error->new( Config );
	
	if ( $kvArgs{id} =~ /^\d+$/ ) {
		my $error = $er->getError( $kvArgs{id} );
		$vars->{collectorLog} = $error;

		my $log = fileToString( $error->{logfile} );
		$vars->{"log"} = encode_entities( $log ) || "No logfile available.";

		$tpl = 'logging_module_collect_details.tt';
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { dialog => $dialogContent };	
}

sub deleteCollectorLogging {
	my ( %kvArgs) = @_;
	my $message;
	my $deleteOk = 0;
	
	my $er = Taranis::Error->new( Config );
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		my $error = $er->getError( $kvArgs{id} );
		
		if ( !$er->deleteLog( $kvArgs{id} ) ) {
			$message = $er->{errmsg};
			setUserAction( action => 'delete collector logging', comment => "Got error '$message' while trying to delete '$error->{error_code}' for '$error->{sourcename}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete collector logging', comment => "Deleted '$error->{error_code}' for '$error->{sourcename}'");
		}
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			deleteOk => $deleteOk,
			message => $message,
			id => $kvArgs{id}
		}
	};	
}

sub searchCollectorLogging {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	my $tt = Taranis::Template->new;
	my $er = Taranis::Error->new( Config );
	

	my $pageNumber = ( exists( $kvArgs{'hidden-page-number'} ) && $kvArgs{'hidden-page-number'} =~ /^\d+$/ )
		? $kvArgs{'hidden-page-number'}
		: 1;

	$er->loadCollection( 
		offset => ( $pageNumber - 1 ) * 100,
		error_code => $kvArgs{error_code}
	);
									 
	my @loggingItems;
	while ( $er->nextObject() ) {
		my $record = $er->getObject();
		$record->{sourcename} = "STATSIMG" if ( !$record->{sourcename} );
		push @loggingItems, $record;
	}

	$vars->{loggingItems} = \@loggingItems;
	
	$vars->{filterButton} = 'btn-collector-logging-search';
	$vars->{page_bar} = $tt->createPageBar( $pageNumber, $er->{result_count}, 100 );
	$vars->{numberOfResults} = scalar @loggingItems;

	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('logging_module_collect.tt', $vars, 1);
	
	return { content => $htmlContent };	
}

sub bulkDeleteCollectorLogging {
	my ( %kvArgs) = @_;
	my ( $message, $logs );
	
	my $deleteOk = 0;
	my $er = Taranis::Error->new( Config );
	
	my $errorCode = $kvArgs{errorCode};
	my $deleteSub = ( $errorCode ) ? 'deleteLogs' : 'deleteAllLogs';
	
	if ( $errorCode ) {
		
		$er->loadCollection( error_code => $errorCode );		
		
		while ( $er->nextObject() ) {
			my $record = $er->getObject();

			next if ( !$record->{logfile} );
			
			my $filename = $record->{logfile};
			$filename =~ s/.*\/(.*?)$/$1/i;
			
			$logs->{ $filename } = $record;
		}		
	}

	if ( $er->$deleteSub( $logs, $errorCode ) ) {
		$deleteOk = 1;
		$message = "Logs have been deleted.";
		if ( $errorCode ) {
			setUserAction( action => 'delete collector logging', comment => "Deleted all logs with code '$errorCode'");
		} else {
			setUserAction( action => 'delete collector logging', comment => "Deleted all logs");
		}
	} else {
		$message = $er->{errmsg};
		if ( $errorCode ) {
			setUserAction( action => 'delete collector logging', comment => "Got error '$message' while trying to delete all logs with code '$errorCode'");
		} else {
			setUserAction( action => 'delete collector logging', comment => "Got error '$message' while trying to delete all logs");
		}
	}

	return { 
		params => { 
			deleteOk => $deleteOk,
			message => $message
		} 
	};	
}

1;
