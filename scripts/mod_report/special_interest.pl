#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Report::SpecialInterest;
use Taranis::Template;

my @EXPORT_OK = qw( 
	displaySpecialInterests openDialogNewSpecialInterest 
	saveNewSpecialInterest openDialogSpecialInterestDetails 
	saveSpecialInterestDetails getSpecialInterestItemHtml
	searchSpecialInterest deleteSpecialInterest
);

sub special_interest_export {
	return @EXPORT_OK;
}

sub	displaySpecialInterests {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
	
	my $specialInterestList = $oTaranisReportSpecialInterest->getSpecialInterest();
	$vars->{specialInterestList} = $specialInterestList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_special_interest.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('report_special_interest_filters.tt', $vars, 1);
	
	my @js = ('js/report_special_interest.js', 'js/report.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewSpecialInterest {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'report_special_interest_details.tt';
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

sub saveNewSpecialInterest {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;
	
	my $date_start = formatDateTimeString $kvArgs{date_start};
	my $date_end   = formatDateTimeString $kvArgs{date_end};
	if (
		right("write")
		&& $date_start
		&& $date_end
		&& $kvArgs{requestor} =~ /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
	) {

		my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );

		if ( $id = $oTaranisReportSpecialInterest->addSpecialInterest(
				requestor => $kvArgs{requestor},
				topic => $kvArgs{topic},
				action => $kvArgs{action},
				date_start => $date_start,
				date_end => "$date_end 23:59:59",
			) 
		) {
			setUserAction( action => 'add special interest', comment => "Added special interest $kvArgs{topic}");
		} else {
			$message = $oTaranisReportSpecialInterest->{errmsg};
			setUserAction( action => 'add special interest', comment => "Got error '$message' while trying to add special interest $kvArgs{topic}");
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

sub openDialogSpecialInterestDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $specialInterestID );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
		$specialInterestID = $kvArgs{id};

		my $specialInterest = $oTaranisReportSpecialInterest->getSpecialInterest( id => $specialInterestID );
		$vars->{specialInterest} = ( $specialInterest ) ? $specialInterest->[0] : undef;

		$tpl = 'report_special_interest_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => {
			writeRight => $writeRight,
			id => $specialInterestID
		}  
	};	
}

sub saveSpecialInterestDetails {
	my ( %kvArgs) = @_;
	my ( $message, $specialInterestID );
	my $saveOk = 0;

	my $date_start = formatDateTimeString $kvArgs{date_start};
	my $date_end   = formatDateTimeString $kvArgs{date_end};

	if ( 
		right("write") 
		&& $kvArgs{id} =~ /^\d+$/ 
		&& $date_start
		&& $date_end
		&& $kvArgs{requestor} =~ /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
	) {

		my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
		$specialInterestID = $kvArgs{id};

		my %update = (
			id => $specialInterestID,
			requestor => $kvArgs{requestor},
			topic => $kvArgs{topic},
			action => $kvArgs{action},
			date_start => $date_start,
			date_end => "$date_end 23:59:59",
		);
		
		$update{timestamp_reminder_sent} = undef
			if $kvArgs{reminder_reset} && $kvArgs{reminder_reset} eq '1';

		if ( !$oTaranisReportSpecialInterest->setSpecialInterest( %update ) ) {
			$message = $oTaranisReportSpecialInterest->{errmsg};
			setUserAction( action => 'edit special interest', comment => "Got error '$message' while trying to edit special interest $kvArgs{topic}");
		} else {
			setUserAction( action => 'edit special interest', comment => "Edited special interest $kvArgs{topic}");
		}

		$saveOk = 1 if ( !$message );
	} else {
		$message = 'No permission';
	}
	
	return {
		params => {
			saveOk => $saveOk,
			message => $message,
			id => $specialInterestID,
			insertNew => 0
		}
	};
}

sub getSpecialInterestItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
		
	my $specialInterestID = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $specialInterest = $oTaranisReportSpecialInterest->getSpecialInterest( id => $specialInterestID );
 
	if ( $specialInterest ) {
		$vars->{specialInterest} = $specialInterest->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'report_special_interest_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $specialInterestID
		}
	};
}

sub searchSpecialInterest {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
	
	if ( exists( $kvArgs{search} ) && trim( $kvArgs{search} ) ) {
		$search{-or} = {
			requestor => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			topic => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			action => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
		}
	}
	
	my $specialInterestList = $oTaranisReportSpecialInterest->getSpecialInterest( %search );
		
	$vars->{specialInterestList} = $specialInterestList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_special_interest.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub deleteSpecialInterest {
	my ( %kvArgs) = @_;
	my ( $message, $id, $topic );

	my $oTaranisReportSpecialInterest = Taranis::Report::SpecialInterest->new( Config );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $specialInterest = $oTaranisReportSpecialInterest->getSpecialInterest( id => $id );
		$topic = ( $specialInterest ) ? $specialInterest->[0]->{topic} : undef;
		if ( $oTaranisReportSpecialInterest->deleteSpecialInterest( id => $id ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete report special interest', comment => "Deleted special interest $topic");
	} else {
		setUserAction( action => 'delete report special interest', comment => "Got error $message while trying to delete special interest $topic");
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
