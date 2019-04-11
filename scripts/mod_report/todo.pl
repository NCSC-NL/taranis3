#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis qw(:all);
use Taranis::Config;
use Taranis::Database;
use Taranis::SessionUtil qw(setUserAction right);
use Taranis::FunctionalWrapper qw(Config Database);
use Taranis::Report::ToDo;
use Taranis::Template;

my @EXPORT_OK = qw(
	displayToDos openDialogNewToDo
	saveNewToDo openDialogToDoDetails
	saveToDoDetails getToDoItemHtml
	searchToDo deleteToDo
);

sub todo_export {
	return @EXPORT_OK;
}

sub	displayToDos {
	my ( %kvArgs) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
	
	my $todoList = $oTaranisReportToDo->getToDo();
	$vars->{todoList} = $todoList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_todo.tt', $vars, 1);
	my $htmlFilters = $oTaranisTemplate->processTemplate('report_todo_filters.tt', $vars, 1);
	
	my @js = ('js/report_todo.js', 'js/report.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub openDialogNewToDo {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $writeRight = right("write");
	
	if ( $writeRight ) {
		$tpl = 'report_todo_details.tt';
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

sub saveNewToDo {
	my ( %kvArgs) = @_;
	my ( $message, $id );
	my $saveOk = 0;

	my $due_date = formatDateTimeString $kvArgs{due_date};
	
	if ( 
		right("write") 
		&& $kvArgs{done_status} =~ /^(0|25|50|75|100)$/
		&& $due_date
		&& $kvArgs{description}
	) {

		my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );

		if ( $id = $oTaranisReportToDo->addToDo(
				description => $kvArgs{description},
				notes => $kvArgs{notes},
				done_status => $kvArgs{done_status},
				due_date => $due_date,
			) 
		) {
			setUserAction( action => 'add to-do', comment => "Added to-do $kvArgs{description}");
		} else {
			$message = $oTaranisReportToDo->{errmsg};
			setUserAction( action => 'add to-do', comment => "Got error '$message' while trying to add to-do $kvArgs{description}");
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

sub openDialogToDoDetails {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl, $todoID );

	my $oTaranisTemplate = Taranis::Template->new;
	
	my $writeRight = right("write");	

	if ( $kvArgs{id} =~ /^\d+$/ ) {
		
		my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
		$todoID = $kvArgs{id};

		my $todo = $oTaranisReportToDo->getToDo( id => $todoID );
		$vars->{todo} = ( $todo ) ? $todo->[0] : undef;

		$tpl = 'report_todo_details.tt';
		
	} else {
		$vars->{message} = 'Invalid input supplied';
		$tpl = 'dialog_no_right.tt';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );
	
	return { 
		dialog => $dialogContent,
		params => { 
			writeRight => $writeRight,
			id => $todoID
		}  
	};	
}

sub saveToDoDetails {
	my ( %kvArgs) = @_;
	my ( $message, $todoID );
	my $saveOk = 0;
	my $due_date = formatDateTimeString $kvArgs{due_date};

	if ( 
		right("write") 
		&& $kvArgs{id} =~ /^\d+$/ 
		&& $kvArgs{done_status} =~ /^(0|25|50|75|100)$/
		&& $due_date
		&& $kvArgs{description}
	) {

		my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
		$todoID = $kvArgs{id};

		if ( !$oTaranisReportToDo->setToDo(	
				id => $todoID,
				description => $kvArgs{description},
				notes => $kvArgs{notes},
				done_status => $kvArgs{done_status},
				due_date => $due_date,
			)
		) {
			$message = $oTaranisReportToDo->{errmsg};
			setUserAction( action => 'edit to-do', comment => "Got error '$message' while trying to edit to-do $kvArgs{description}");
		} else {
			if ( $kvArgs{done_status} eq '100' ) {
				setUserAction( action => 'edit to-do done', comment => "Completed to-do $kvArgs{description}");
			} else {
				setUserAction( action => 'edit to-do', comment => "Edited to-do $kvArgs{description}");
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
			id => $todoID,
			insertNew => 0
		}
	};
}

sub getToDoItemHtml {
	my ( %kvArgs) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
		
	my $todoID = $kvArgs{id};
	my $insertNew = $kvArgs{insertNew};
 
 	my $todo = $oTaranisReportToDo->getToDo( id => $todoID );
 
	if ( $todo ) {
		$vars->{todo} = $todo->[0];
		$vars->{write_right} =  right("write");
		$vars->{renderItemContainer} = $insertNew;
		
		$tpl = 'report_todo_item.tt';
	} else {
		$tpl = 'empty_row.tt';
		$vars->{message} = 'Could not find the item...';
	}

	my $itemHtml = $oTaranisTemplate->processTemplate($tpl, $vars, 1);

	return {
		params => {
			itemHtml => $itemHtml,
			insertNew => $insertNew,
			id => $todoID
		}
	};
}

sub searchToDo {
	my ( %kvArgs) = @_;
	my ( $vars, %search );

	
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
	
	if ( exists( $kvArgs{search} ) && trim( $kvArgs{search} ) ) {
		$search{-or} = {
			description => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
			notes => { '-ilike' => '%' . trim( $kvArgs{search} ) . '%' },
		}
	}
	
	my $todoList = $oTaranisReportToDo->getToDo( %search );
		
	$vars->{todoList} = $todoList;
	$vars->{write_right} = right("write");
	$vars->{renderItemContainer} = 1;
	
	my $htmlContent = $oTaranisTemplate->processTemplate('report_todo.tt', $vars, 1);
	
	return { content => $htmlContent };
}

sub deleteToDo {
	my ( %kvArgs) = @_;
	my ( $message, $id, $todoDescription );

	my $oTaranisReportToDo = Taranis::Report::ToDo->new( Config );
	
	my $deleteOk = 0;
	
	if ( right("write") && $kvArgs{id} =~ /^\d+$/ ) {
		$id = $kvArgs{id};
		
		my $todo = $oTaranisReportToDo->getToDo( id => $id );
		$todoDescription = ( $todo ) ? $todo->[0]->{description} : undef;
		if ( $oTaranisReportToDo->deleteToDo( id => $id ) ) {
			$deleteOk = 1;
		} else {
			$message = Database->{db_error_msg};
		}
		
	} else {
		$message = "No permission.";
	}

	if ( $deleteOk ) {
		setUserAction( action => 'delete report to-do', comment => "Deleted to-do $todoDescription");
	} else {
		setUserAction( action => 'delete report to-do', comment => "Got error $message while trying to delete to-do $todoDescription");
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
