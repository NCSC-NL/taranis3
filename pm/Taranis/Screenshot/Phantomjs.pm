# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Screenshot::Phantomjs;

use strict;
use warnings;

use JSON           qw(to_json);
use IPC::Run       qw(run timeout);
use POSIX          qw(WEXITSTATUS WIFEXITED WIFSIGNALED WTERMSIG);
use Carp           qw(confess);

my $default_user_agent = 'Mozilla/5.0 (Windows NT 6.1; rv:52.0) Gecko/20100101 Firefox/52.0'; # Firefox 52.0;

sub new {
	my $class = shift;
	my $bin   = $ENV{PHANTOMJS}     or confess;
	my $lib   = $ENV{PHANTOMJS_LIB} or confess;
	my $self  = { 
		phantomjs  => $bin,
		screenshot => "$lib/screenshot.js",
		htmltopdf  => "$lib/htmltopdf.js",
	};

	bless $self, $class;
}

sub sayCheese {
	my ($self, %args) = @_;
	my $settings = $args{connectionSettings} || {};
	my $webpage  = $args{siteAddress} or confess;
	
    # Please go to http://phantomjs.org/api/ for phantomjs options.
    my $page_settings = +{
		loadImages         => 1,
		userAgent          => $settings->{user_agent} || $default_user_agent,
		webSecurityEnabled => 0,
		XSSAuditingEnabled => 0,

		# PhantomJS itself will not be able to product correct images without
		# javascript enabled.  This certainly is more dangerous than we would
		# like it to be.
		javascriptEnabled  => 'true',
	};

	my $proxy = $settings->{proxy_host};
    my @cmd   = (
        $self->{phantomjs},
        '--ignore-ssl-errors=true',
        ($proxy ? "--proxy=$proxy" : ()),
        $self->{screenshot},
        $webpage,
        to_json($page_settings),
    );

    my ($out, $err);
    eval { run \@cmd, '</dev/null', '>', \$out, '2>', \$err, timeout(30) };
	if($@) {
		$self->{errmsg} = "110\nphantomjs screenshot timeout: $@";
		return undef;
	}

	my ($rc, $rctxt)
		= WIFEXITED($?)   ? (WEXITSTATUS($?), "done, rc=".WEXITSTATUS($?))
		: WIFSIGNALED($?) ? (1, "failed, sig=".WTERMSIG($?))
		:                   (1, "failed, wait=$?");

    $self->{errmsg} = "$err\n$rctxt";
    $rc==0 ? $out : undef;
}

sub createPDF(%) {
    my ($self, %args) = @_;
    my $refhtml  = $args{refhtml} or confess;
	my $pdfname  = $args{pdfname} or confess;
    
    my $page_settings = +{
        loadImages         => 1,
        webSecurityEnabled => 0,
        XSSAuditingEnabled => 0,
    };

    my @cmd   = (
        $self->{phantomjs},
        '--ignore-ssl-errors=true',
        $self->{htmltopdf},
        $$refhtml,
        to_json($page_settings),
		$pdfname,
    );

    my ($out, $err);
    run \@cmd, '</dev/null', '>', \$out, '2>', \$err, timeout(30);

    my ($rc, $rctxt)
        = WIFEXITED($?)   ? (WEXITSTATUS($?), "done, rc=".WEXITSTATUS($?))
        : WIFSIGNALED($?) ? (1, "failed, sig=".WTERMSIG($?))
        :                   (1, "failed, wait=$?");

    $self->{errmsg} = "$err\n$rctxt";
    $rc==0 ? $out : undef;
}

sub getError {
	my ( $self ) = @_;
	return $self->{errmsg};
}

1;

=head1 NAME

Taranis::Screenshot::Phantomjs

=head1 SYNOPSIS

  use Taranis::Screenshot::Phantomjs;

  my $obj = Taranis::Screenshot::Phantomjs->new();

  $obj->sayCheese( connectionSettings => {}, siteAddress => 'http://...');

  $obj->getError();

=head1 DESCRIPTION

Module to create a screenshots using PhantomJS.

=head1 METHODS

=head2 new()

Constructor of the C<Taranis::Screenshot::Phantomjs> module.

    my $obj = Taranis::Screenshot::Phantomjs->new();

Sets the absolute path of the phantomjs executable:

    $obj->{phantomjs};

Sets the absolute path of the javascript file which is used to create a screenshot with PhantomJS:

    $obj->{screenshotjs};

Returns the blessed object.

=head2 sayCheese( connectionSettings => {}, siteAddress => 'http://...')

Will create a screenshot of the site which is specified by siteAddress parameter.
The connectionSettings parameter can be used to sepcify a C<proxy_host> and a C<user_agent>.

    $obj->sayCheese( siteAddress => 'http://www.ncsc.nl', connectionSettings => {} );

If successful returns the screenshot. If unsuccessful returns FALSE and sets C<< $self->{errmsg} >>.

=head2 getError()

Retrieves the error set in C<< $self->{errmsg} >>.

=cut
