#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Assess;
use Taranis::Config;
use Taranis::Database qw(withTransaction);
use Taranis::SessionUtil qw(right);
use Taranis::FunctionalWrapper qw(Config);
use URI::Escape;
use strict;

my @EXPORT_OK = qw(setStatus);

sub assess_status_export {
	return @EXPORT_OK; 
}

sub setStatus {
	my ( %kvArgs ) = @_;

	my ( $message, @ids, $status );
	my $statusIsSet = 0;
	my $as = Taranis::Assess->new( Config );

	my $statusDictionary = { 'read' => 1, 'important' => 2 }; 

	if ( right("write") ) {

		if ( exists( $kvArgs{status} ) && $kvArgs{status} =~ /^(read|important)$/i ) {
			$status = lc( $kvArgs{status} );
			if ( ref( $kvArgs{id} ) =~ /^ARRAY$/ ) {
				@ids = @{ $kvArgs{id} };
			} else {
				push @ids, $kvArgs{id};
			}
	
			withTransaction {
				foreach my $id ( @ids ) {
					$id = uri_unescape( $id );
					if ( $as->setItemStatus( digest => $id, status => $statusDictionary->{ $status } ) ) {
					  $statusIsSet = 1;
					} else {
					  $message = $as->{errmsg};
					}
				}
			};
			
		} else {
			$message = "Illegal action!! (assess_status)";
		}	

	} else {
		$message = "Sorry, you do not have enough privileges to to change item status...";
	}
	
	return { 
		params => { 
			message => $message,
			status => $status,
			status_is_set => $statusIsSet,
			ids => \@ids
		}
	};
}

1;
