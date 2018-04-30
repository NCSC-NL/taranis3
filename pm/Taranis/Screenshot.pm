# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Screenshot;

use strict;
use Module::Load;

sub new {
	my ($class, %args) = @_;

	my $self = {
		screenshotModule => $args{screenshot_module},
		connectionSettings => {}
	};

	$self->{connectionSettings}->{proxy_host} = $args{proxy_host} if ( exists( $args{proxy_host} ) );
	$self->{connectionSettings}->{useragent} = $args{user_agent} if ( exists( $args{user_agent} ) );

	return( bless( $self, $class ) );
}

# should always return the 1 or 0
# in case of returning 0 $self->{errmsg} should be set
sub takeScreenshot {
	my ( $self, %args ) = @_;
	undef $self->{errmsg};
	
	if ( !exists( $args{siteAddress} ) || !$args{siteAddress} ) {
		$self->{errgmsg} = 'One or more mandatory arguments missing.';
		return 0;
	}

	load $self->{screenshotModule};
	my $screenshotModuleObj = $self->{screenshotModule}->new();
	
	if ( my $screenshot = $screenshotModuleObj->sayCheese( siteAddress => $args{siteAddress}, connectionSettings => $self->{connectionSettings} ) ) {
		return $screenshot;
	} else {
		$self->{errmsg} = $screenshotModuleObj->getError();
		return 0;
	}
}

1;

=head1 NAME

Taranis::Screenshot

=head1 SYNOPSIS

  use Taranis::Screenshot;

  my $obj = Taranis::Screenshot->new( screenshot_module => $moduleName, proxy_host => $proxy, user_agent => $userAgentString );

  $obj->takeScreenshot( siteAddress => $siteAddress );

=head1 DESCRIPTION

Main module for taking screenshots.

=head1 METHODS

=head2 new( screenshot_module => $moduleName, proxy_host => $proxy, user_agent => $userAgentString )

Constructor of the C<Taranis::Screenshot> module. Parameter screenshot_module is mandatory.

    my $obj = Taranis::Screenshot->new( screenshot_module => 'Taranis::Screenshot::Phantomjs', proxy_host => 'http://my.proxy.host', user_agent => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:22.0) Gecko/20130328 Firefox/22.0' );

Sets which screenshot module will be used:

    $obj->{screenshotModule}

Sets the connection settings like C<proxy_host> and C<useragent>:

    $obj->{connectionSettings}

Returns the blessed object.

=head2 takescreenshot( siteAddress => $siteAddress )

Will create a screenshot of given C<$siteAddress>. Parameter C<siteAddress> is mandatory.

    $obj->takeScreenshot( siteAddress => 'http://www.ncsc.nl' );

If successfule returns the screenshot as binary. If unsuccessful returns FALSE and sets C<< $obj->{errmsg} >> to C<< $obj->{screenshotModule}->getError() >>.

=head1 DIAGNOSTICS

The following messages can be expected from this module:

=over

=item *

I<One or more mandatory arguments missing.>

Caused by takeScreenshot() when parameter C<siteAddress> is undefined.
You should check parameter C<id> setting.

=back

=cut
