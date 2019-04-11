#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Report::ContactLog;
use Taranis::Template;

my @EXPORT_OK = qw( 
	displayContactLogs openDialogNewContactLog 
	saveNewContactLog openDialogContactLogDetails 
	saveContactLogDetails getContactLogItemHtml 
	searchContactLog deleteContactLog 
);

sub contact_log_export {
	return @EXPORT_OK;
}

sub	displayContactLogs {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
	
	my $contactLogList = $oTaranisReportContactLog->getContactLog();
	$vars->{contactLogList} = $contactLogList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_contact_log.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('report_contact_log_filters.tt', $vars, 1);
	
	my @js = ('js/report_contact_log.js', 'js/report.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewContactLog {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'report_contact_log_details.tt';
		$vars->{contactTypes} = Taranis::Report::ContactLog->getContactTypeDictionary();
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

sub saveNewContactLog {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	
	if ( right("write") && $kvArgs{type} =~ /^[1-4]$/ ) {

		my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );

		if ( $id = $oTaranisReportContactLog->addContactLog(
				type => $kvArgs{type},
				contact_details => $kvArgs{contact_details},
				notes => $kvArgs{notes}
			) 
		) {
			setUserAction( action => 'add contact log', comment => "Added contact log");
		} else {
			$message = $oTaranisReportContactLog->{errmsg};
			setUserAction( action => 'add contact log', comment => "Got error '$message' while trying to add contact log");
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

sub openDialogContactLogDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $contactLogID );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
		$contactLogID = $kvArgs{id};

		my $contactLog = $oTaranisReportContactLog->getContactLog( id => $contactLogID );
		$vars->{contactLog} = ( $contactLog ) ? $contactLog->[0] : undef;
		$vars->{contactTypes} = Taranis::Report::ContactLog->getContactTypeDictionary();
		$tpl = 'report_contact_log_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $contactLogID
		}  
	};	
}

sub saveContactLogDetails {
	my ( %kvArgs) = @_;
	my ( $message, $contactLogID );
	my $saveOk = 0;
	

	if ( 
		right("write")
		&& $kvArgs{id} =~ /^\d+$/
		&& $kvArgs{type} =~ /^[1-4]$/
	) {

		my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
		$contactLogID = $kvArgs{id};

		if ( !$oTaranisReportContactLog->setContactLog(	
				id => $contactLogID,
				type => $kvArgs{type},
				contact_details => $kvArgs{contact_details},
				notes => $kvArgs{notes}
			)
		) {
			$message = $oTaranisReportContactLog->{errmsg};
			setUserAction( action => 'edit contact log', comment => "Got error '$message' while trying to edit contact log");
		} else {
			setUserAction( action => 'edit contact log', comment => "Edited contact log");
		}

		$saveOk = 1 if ( !$message );
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $contactLogID,
			insertNew => 0
		}
	};
}

sub getContactLogItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
		
	my $contactLogID = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $contactLog = $oTaranisReportContactLog->getContactLog( id => $contactLogID );
 
	if ( $contactLog ) {
		$vars->{contactLog} = $contactLog->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'report_contact_log_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $contactLogID
		}
	};
}

sub searchContactLog {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
	
	if ( exists( $kvArgs{search} ) && trim( $kvArgs{search} ) ) {
		$search{-or} = {
			contact_details => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			notes => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
		}
	}
	
	my $contactLogList = $oTaranisReportContactLog->getContactLog( %search );
		
	$vars->{contactLogList} = $contactLogList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_contact_log.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub deleteContactLog {
	my ( %kvArgs) = @_;
	my ( $message, $id, $description );

	my $oTaranisReportContactLog = Taranis::Report::ContactLog->new( Config );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $contactLog = $oTaranisReportContactLog->getContactLog( id => $id );
		
		my $log = ( $contactLog ) ? $contactLog->[0] : undef;
		my $typeMapping = $oTaranisReportContactLog->getContactTypeDictionary();
		
		my $timestamp = $log->{created};
		$timestamp =~ s/(.*?)(\.|\+).*/$1/;
		$description = 'type ' . $typeMapping->{ $log->{type} } . ' of ' . $timestamp;
		
		if ( $oTaranisReportContactLog->deleteContactLog( id => $id ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete report contact log', comment => "Deleted contact log entry $description ");
	} else {
		setUserAction( action => 'delete report contact log', comment => "Got error $message while trying to delete contact log $description");
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
