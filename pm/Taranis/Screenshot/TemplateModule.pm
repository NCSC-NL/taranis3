# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Screenshot::TemplateModule;

use strict;

sub new {
	my $class = shift;
	
	my $self = {
		modulSpecificParam => ''
	};
	
	return( bless( $self, $class ) );
}

sub sayCheese {
	my ( $self, %args ) = @_;
	# input args are: siteAddress
	

	# code for taking a screenshot...
	my $return = '';
	


	if ( $return ) { 
		return 1;
	} else {
		$self->{errmsg} = 'some error message';
		return 0;
	}
}

sub getError {
	my ( $self ) = @_;
	return $self->{errmsg};
}

1;
