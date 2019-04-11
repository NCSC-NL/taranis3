# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::FunctionalWrapper::Croaker;

## Taranis::FunctionalWrapper::Croaker: proxy class to turn all an object's methods from errmsg-returning style to
## exception-throwing objects. Used inside Taranis::FunctionalWrapper.
## Many Taranis classes work in errmsg-returning style: when a methods fails, it sets $self->{errmsg} to an error string
## and returns 0. Taranis::FunctionalWrapper::Croaker makes them croak (i.e. die, i.e. throw an exception) instead, with
## the error string as the croak message.
##
## That is to say, instead of:
##
## $user = $taranisUsersObject->getUser('username');
## if ($taranisUsersObject->{errmsg}) {
##   ... # User not found, or something. Handle error.
## } else {
##   print $user->{fullname};
## }
##
## Taranis::FunctionalWrapper::Croaker allows us to do:
##
## eval {
##   print Taranis::FunctionalWrapper::Croaker->new($taranisUsersObject)->getUser('username')->{fullname};
## };
## if ($@) {
##   ... # User not found, or something. Handle error.
## }


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;


sub new {
	my ($class, $targetObject) = @_;
	$targetObject->{__croaker_target_class} = ref $targetObject;
	return bless($targetObject, $class);
}

sub can {
	my ($self, $method) = @_;
	return $self->{__croaker_target_class}->can($method);
}

sub DESTROY {
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	our $AUTOLOAD;

	my $method = $AUTOLOAD;

	$method =~ s/^Taranis::FunctionalWrapper::Croaker::// or die "Mysterious method $method is outside our package";
	if (!$self->can($method)) {
		croak("attempt to call nonexistent method '$method' on '$self->{__croaker_target_class}' proxy object");
	}

	my $fullMethod = $self->{__croaker_target_class} . '::' . $method;
	my ($result, @result);

	{
		# Make Carp ignore us - the proxy - when generating exception messages.
		local $Carp::CarpLevel = $Carp::CarpLevel + 1;

		if (wantarray) {
			eval {
				@result = $self->$fullMethod(@args);
			};
		} else {
			eval {
				$result = $self->$fullMethod(@args);
			};
		}
	}

	if (my $errmsg = $@ || $self->{errmsg} || $self->{db_error_msg}) {
		undef $self->{errmsg};
		undef $self->{db_error_msg};
		confess $errmsg;
	}

	return wantarray ? @result : $result;
}

1;
