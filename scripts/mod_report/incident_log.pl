#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Report::IncidentLog;
use Taranis::Template;
use Taranis::Users qw();

my @EXPORT_OK = qw( 
	displayIncidentLogs openDialogNewIncidentLog 
	saveNewIncidentLog openDialogIncidentLogDetails 
	saveIncidentLogDetails getIncidentLogItemHtml 
	searchIncidentLog deleteIncidentLog
);

sub incident_log_export {
	return @EXPORT_OK;
}

sub	displayIncidentLogs {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
	
	my $incidentLogList = $oTaranisReportIncidentLog->getIncidentLog();
	$vars->{incidentLogList} = $incidentLogList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_incident_log.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('report_incident_log_filters.tt', $vars, 1);
	
	my @js = ('js/report_incident_log.js', 'js/report.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewIncidentLog {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		my $oTaranisUsers = Taranis::Users->new( Config );

		$oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}
		
		$vars->{users} = \@users;
		$vars->{statuses} = Taranis::Report::IncidentLog->getStatusDictionary();
		
		$tpl = 'report_incident_log_details.tt';
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

sub saveNewIncidentLog {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if (
		right("write") 
		&& $kvArgs{status} =~ /^\d+$/
	) {

		my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );

		if ( $id = $oTaranisReportIncidentLog->addIncidentLog(
				constituent => $kvArgs{constituent},
				description => $kvArgs{description},
				owner => $kvArgs{owner},
				ticket_number => $kvArgs{ticket_number},
				status => $kvArgs{status}
			) 
		) {
			setUserAction( action => 'add incident log', comment => "Added incident log $kvArgs{description}");
		} else {
			$message = $oTaranisReportIncidentLog->{errmsg};
			setUserAction( action => 'add incident log', comment => "Got error '$message' while trying to add incident log $kvArgs{description}");
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
			insertNew => 1
		}
	};
}

sub openDialogIncidentLogDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $incidentLogID );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
		$incidentLogID = $kvArgs{id};

		my $incidentLog = $oTaranisReportIncidentLog->getIncidentLog( 'ril.id' => $incidentLogID );
		$vars->{incidentLog} = ( $incidentLog ) ? $incidentLog->[0] : undef;
		
		my $oTaranisUsers = Taranis::Users->new( Config );

		$oTaranisUsers->getUsersList();
		my @users;
		while ( $oTaranisUsers->nextObject() ) {
			my $user = $oTaranisUsers->getObject();
			push @users, { username => $user->{username}, fullname => $user->{fullname} }
		}
		
		$vars->{users} = \@users;
		$vars->{statuses} = Taranis::Report::IncidentLog->getStatusDictionary();
		
		$tpl = 'report_incident_log_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $incidentLogID
		}  
	};	
}

sub saveIncidentLogDetails {
	my ( %kvArgs) = @_;
	my ( $message, $incidentLogID );
	my $saveOk = 0;
	

	if ( 
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{status} =~ /^\d+$/
	) {

		my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
		$incidentLogID = $kvArgs{id};

		if ( !$oTaranisReportIncidentLog->setIncidentLog(
				id => $incidentLogID,
				constituent => $kvArgs{constituent},
				description => $kvArgs{description},
				owner => $kvArgs{owner},
				ticket_number => $kvArgs{ticket_number},
				status => $kvArgs{status}
			)
		) {
			$message = $oTaranisReportIncidentLog->{errmsg};
			setUserAction( action => 'edit incident log', comment => "Got error '$message' while trying to edit incident log $kvArgs{description}");
		} else {
			my $statuses = Taranis::Report::IncidentLog->getStatusDictionary();
			
			if ( $statuses->{ $kvArgs{status} } !~ /^(new|open)$/i ) {
				
				setUserAction( action => 'edit incident log status', comment => "Changed status to $statuses->{ $kvArgs{status} } of incident $kvArgs{description} ($kvArgs{ticket_number})");
			} else {
				setUserAction( action => 'edit incident log', comment => "Edited incident log $kvArgs{description} ($kvArgs{ticket_number})");
			}
		}

		$saveOk = 1 if ( !$message );
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $incidentLogID,
			insertNew => 0
		}
	};
}

sub getIncidentLogItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
		
	my $incidentLogID = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $incidentLog = $oTaranisReportIncidentLog->getIncidentLog( 'ril.id' => $incidentLogID );
 
	if ( $incidentLog ) {
		$vars->{incidentLog} = $incidentLog->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'report_incident_log_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $incidentLogID
		}
	};
}

sub searchIncidentLog {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
	
	if ( exists( $kvArgs{search} ) && trim( $kvArgs{search} ) ) {
		$search{-or} = {
			description => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			ticket_number => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			owner => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			constituent => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' }
		}
	}
	
	my $incidentLogList = $oTaranisReportIncidentLog->getIncidentLog( %search );
		
	$vars->{incidentLogList} = $incidentLogList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_incident_log.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub deleteIncidentLog {
	my ( %kvArgs) = @_;
	my ( $message, $id, $description );

	my $oTaranisReportIncidentLog = Taranis::Report::IncidentLog->new( Config );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $incidentLog = $oTaranisReportIncidentLog->getIncidentLog( 'ril.id' => $id );
		$description  = ( $incidentLog ) ? $incidentLog->[0]->{description} : undef;
		if ( $oTaranisReportIncidentLog->deleteIncidentLog( id => $id ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete report incident log', comment => "Deleted incident log $description ");
	} else {
		setUserAction( action => 'delete report incident log', comment => "Got error $message while trying to delete incident log $description");
	}

	return {
		params => {
			message => $message,
			deleteOk => $deleteOk,
			id => $id
		}
	};
}

1;
