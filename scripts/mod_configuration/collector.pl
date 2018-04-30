#!/usr/bin/perl 
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Collector::Administration;
use Taranis::Template;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config);
use strict;

my @EXPORT_OK = qw( 
	displayCollectors openDialogNewCollector openDialogCollectorDetails 
	saveNewCollector saveCollectorDetails deleteCollector getCollectorItemHtml
	resetCollectorSecret
);

sub collector_export {
	return @EXPORT_OK;
}

sub	displayCollectors {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $tt = Taranis::Template->new;
	my $col = Taranis::Collector::Administration->new( Config );

	my @collectors = $col->getCollectors();
	if ( @collectors && $collectors[0] ) {
		for ( my $i = 0; $i < @collectors; $i++ ) {
			if ( !$col->{dbh}->checkIfExists( { collector_id => $collectors[$i]->{id} }, "sources") ) {
				$collectors[$i]->{status} = 1;
			} else {
				$collectors[$i]->{status} = 0;
			}
		}
	} else {
		undef @collectors;
	}
	
	$vars->{collectors} = \@collectors;
	$vars->{numberOfResults} = scalar @collectors;
	$vars->{write_right} = right("write");	
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $tt->processTemplate('collector.tt', $vars, 1);
	my $htmlFilters = $tt->processTemplate('collector_filters.tt', $vars, 1);
	
	my @js = ('js/collector.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };	
}

sub openDialogNewCollector {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'collector_details.tt';
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

sub openDialogCollectorDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $id );

	my $tt = Taranis::Template->new;
	
	my $writeRight = right("write");

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $col = Taranis::Collector::Administration->new( Config);
		$id = $kvArgs{id};

		my @collectors = $col->getCollectors( id => $id );
		if ( scalar( @collectors ) == 1 ) {
			$vars->{collector} = $collectors[0]; 
		}

		$tpl = 'collector_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $tt->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $id
		}  
	};	
}
 
sub saveNewCollector {
	my ( %kvArgs) = @_;
	my ( $message, $id, $secret );
	my $saveOk = 0;
	

	if ( right("write") ) {
		my $col = Taranis::Collector::Administration->new( Config );
		
		if ( !$col->{dbh}->checkIfExists( { description => $kvArgs{description} }, "collector", "IGNORE_CASE" ) ) {
			if ( $secret = $col->addCollector( description => $kvArgs{description}) ) {
				$id = $col->{dbh}->getLastInsertedId('collector');
				setUserAction( action => 'add collector', comment => "Added collector '$kvArgs{description}'");
			} else {
				$message = $col->{errmsg};
				setUserAction( action => 'add collector', comment => "Got error '$message' while trying to add collector '$kvArgs{description}'");
			}
		} else {
			$message = "A collector with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $id,
			secret => $secret,
			insertNew => 1
		}
	};	
}

sub saveCollectorDetails {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {

		my $col = Taranis::Collector::Administration->new( Config );
		$id = $kvArgs{id};
		
		my $collectorDescription;
		
		my @collectors = $col->getCollectors( id => $id );
		if ( scalar( @collectors ) == 1 ) {
			$collectorDescription = $collectors[0]->{description}; 
		}

		if (
			lc( $kvArgs{description} ) eq lc( $collectorDescription ) 
			|| !$col->{dbh}->checkIfExists( {description => $kvArgs{description} } , "collector", "IGNORE_CASE" ) 
		) {
			if ( 
				!$col->setCollector( 
					id => $id, 
					description => $kvArgs{description},
				) 
			) {
				$message = $col->{errmsg};
				setUserAction( action => 'edit collector', comment => "Got error '$message' while trying to edit collector '$collectorDescription'");
			} else {
				setUserAction( action => 'edit collector', comment => "Edited collector '$collectorDescription'");
			}
		} else {
			$message = "A collector with the same description already exists.";
		}

		$saveOk = 1 if ( !$message );
		
	} else {
		$message = 'No permission';
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

sub deleteCollector {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $deleteOk = 0;
	
	my $col = Taranis::Collector::Administration->new( Config );

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		my @collectors = $col->getCollectors( id => $id );
		my $collector = $collectors[0]; 

		if ( !$col->deleteCollector( $kvArgs{id} ) ) {
			$message = $col->{errmsg};
			setUserAction( action => 'delete collector', comment => "Got error '$message' while deleting collector '$collector->{description}'");
		} else {
			$deleteOk = 1;
			setUserAction( action => 'delete collector', comment => "Deleted collector '$collector->{description}'");
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

sub getCollectorItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $tt = Taranis::Template->new;
	my $col = Taranis::Collector::Administration->new( Config );
		
	my $id = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $collector;
	my @collectors = $col->getCollectors( id => $id );
	if ( scalar( @collectors ) == 1 ) {
		$collector = $collectors[0]; 
	}
 
	if ( $collector ) {

		if ( !$col->{dbh}->checkIfExists( { collector_id => $id }, "sources") ) {
			$collector->{status} = 1;
		} else {
			$collector->{status} = 0;
		}

		$vars->{collector} = $collector;
		$vars->{write_right} = right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'collector_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $tt->processTemplate($tpl, $vars, 1);

	return {
		params => { 
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $id
		}
	};	
}
sub resetCollectorSecret {
	my ( %kvArgs) = @_;
	my ( $id, $message, $secret );
		

	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {

		my $col = Taranis::Collector::Administration->new( Config );
		$id = $kvArgs{id};

		my @collectors = $col->getCollectors( id => $id );
		my $collector = $collectors[0]; 

		$secret = $col->createSecret();
		if ( !$col->setCollector( id => $id, secret => $secret ) ) {
			$message = $col->{errmsg};
			setUserAction( action => 'edit collector', comment => "Got error '$message' while trying to reset secret for collector '$collector->{description}'");
		} else {
			setUserAction( action => 'edit collector', comment => "Reset secret for collector '$collector->{description}'");
		}
	}
		
	return {
		params => {
			secret => $secret
		}
	};
}
1;
