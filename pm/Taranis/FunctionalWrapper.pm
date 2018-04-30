# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::FunctionalWrapper;

## Taranis::FunctionalWrapper: alternative, "functional" interface to various modules.
##
## Synopsis:
##
## use Taranis::Users;  # Must import the necessary Taranis modules yourself; FunctionalWrapper won't do it for you.
## use Taranis::Template;
## use Taranis::FunctionalWrapper qw(Users Template);
## print Users->getUser('alice')->{fullname};
## print Users->getUser('bob')->{fullname};  # This reuses the same Taranis::Users object; no resource worries.
## Template->doThing();
##
##
## The above is roughly equivalent to:
##
## use Taranis::Users;
## use Taranis::Template;
## $oTaranisUsers = Taranis::Users->new;
## $oTaranisTemplate = Taranis::Template->new;
##
## $userA = $oTaranisUsers->getUser('alice');
## if ($oTaranisUsers->{errmsg}) {
##   die $oTaranisUsers->{errmsg};
## }
## print $userA->{fullname};
##
## $userB = $oTaranisUsers->getUser('bob');
## if ($oTaranisUsers->{errmsg}) {
##   die $oTaranisUsers->{errmsg};
## }
## print $userB->{fullname};
##
## $oTaranisTemplate->doThing();
## if ($oTaranisTemplate->{errmsg}) {
##   die $oTaranisTemplate->{errmsg};
## }
##
##
## Behind the scenes, 'Users' (and 'Template', and..) is actually a function that returns a singleton Croaker object,
## i.e. on first invocation (per thread or request) it creates a Taranis::Users object, wraps that in
## Taranis::FunctionalWrapper::Croaker (to get exceptions instead of error-returns) and returns the wrapped object; on
## subsequent invocations it returns the same wrapped object.
##
## Beside Taranis modules (Taranis::Users, Taranis::Template, etc), we also wrap external modules. These are not
## wrapped in Croaker, since Croaker is purely for transforming Taranis-style error-returns into exceptions.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use threads;
use Apache2::RequestUtil;
use Apache2::RequestRec;

use Taranis::FunctionalWrapper::Croaker;


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	croaker
	Config Constituent_Group Database Publication PublicationEndOfShift PublicationEndOfDay Publish
	ReportContactLog ReportIncidentLog ReportSpecialInterest ReportToDo
	Role SoftwareHardware Template Users
	CGI Sql
);


our %singletons;


*Config                 = _makeSingleton('Taranis::Config',                  1);
*Constituent_Group      = _makeSingleton('Taranis::Constituent_Group',       1);
*Database               = _makeSingleton('Taranis::Database',                1);
*Publication            = _makeSingleton('Taranis::Publication',             1);
*PublicationEndOfShift  = _makeSingleton('Taranis::Publication::EndOfShift', 1);
*PublicationEndOfDay    = _makeSingleton('Taranis::Publication::EndOfDay',   1);
*Publish                = _makeSingleton('Taranis::Publish',                 1);
*ReportContactLog       = _makeSingleton('Taranis::Report::ContactLog',      1);
*ReportIncidentLog      = _makeSingleton('Taranis::Report::IncidentLog',     1);
*ReportSpecialInterest  = _makeSingleton('Taranis::Report::SpecialInterest', 1);
*ReportToDo             = _makeSingleton('Taranis::Report::ToDo',            1);
*Role                   = _makeSingleton('Taranis::Role',                    1);
*SoftwareHardware       = _makeSingleton('Taranis::SoftwareHardware',        1);
*Template               = _makeSingleton('Taranis::Template',                1);
*Users                  = _makeSingleton('Taranis::Users',                   1);

*CGI                    = _makeSingleton('CGI::Simple',                      0);

# Without the 'array_datatypes' option, SQL::Abstract(::More) interprets [arrayrefs] as literal SQL. We allow users to
# supply JSON - often containing arrayrefs - so we really don't want that.
# Hence, enable 'array_datatypes' option, regardless of whether we use array datatypes.
*Sql                    = _makeSingleton('SQL::Abstract::More',              0, {array_datatypes => 1});


sub croaker {
	return Taranis::FunctionalWrapper::Croaker->new(shift);
}

sub _makeSingleton {
	my ($module, $wrapInCroaker, $constructorArgs) = @_;
	$constructorArgs //= {};

	if ($ENV{MOD_PERL}) {
		# Use mod_perl's Apache2::RequestUtil::pnotes to make sure that our "singleton" objects get destroyed at the
		# end of the request, instead of staying around and being reused for the next mod_perl request. This may not be
		# necessary for some classes - it might even be a good (efficient) thing to keep some singletons around for the
		# next request - but it would certainly be VERY BAD for others.
		#
		# Specifically, if a CGI::Simple object gets reused, that means that one user will get another user's request
		# environment, which will lead to Bad Things. (Incidentally, CGI::Simple::Standard suffers from this problem;
		# apparently it wasn't built for use with mod_perl. This is why we can't just use CGI::Simple::Standard instead
		# of our own CGI::Simple singleton.)
		#
		# For other classes, it's less scary, but may still be undesirable; for example, if we die in the middle of a
		# db transaction, the next request might end up still inside that transaction.
		#
		# Hence, to keep things clean and simple, use pnotes to have all our singletons destroyed/renewed after each
		# request.
		return sub {
			return Apache2::RequestUtil->request->pnotes->{"Taranis::FunctionalWrapper/$module"} ||= (
				$wrapInCroaker
				? croaker($module->new(%$constructorArgs))
				: $module->new(%$constructorArgs)
			);
		};
	} else {
		return sub {
			state $lastThreadId;

			# If we're in a new thread, spawned after our singleton was created, we'll have inherited the singleton
			# object. Ignore the inherited object and make our own, to prevent thread safety issues or resource
			# contention.
			if ($lastThreadId ne threads->tid) {
				undef $singletons{$module};
				$lastThreadId = threads->tid;
			}

			return $singletons{$module} ||= (
				$wrapInCroaker
				? croaker($module->new(%$constructorArgs))
				: $module->new(%$constructorArgs)
			);
		}
	}
}

1;
