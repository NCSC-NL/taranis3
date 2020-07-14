# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Command::Dashboard;

use warnings;
use strict;

use Carp  qw(confess);
use JSON  qw(to_json);

use Taranis qw(logErrorToSyslog find_config);
use Taranis::Config;
use Taranis::Dashboard;
use Taranis::Template;
use Taranis::Install::Config   qw(config_generic config_release
	taranis_sources);

Taranis::Commands->plugin(dashboard => {
	handler       => \&dashboard,
	requires_root => 0,
	sub_commands  => [ qw/make-pages/ ],
	getopt        => [
		'log|l=s',
	],
	help          => <<'__HELP',
SUB-COMMANDS:
  make-pages [-l]        prepare page fragments for dashboard display

OPTIONS:
  -l --log FILE          alternative destination for log (may be '-')
__HELP
} );

my %handlers = (
	'make-pages' => \&dashboard_make_pages,
);

sub dashboard(%) {
	my %args = @_;

    @{$args{files}}==0
        or die "ERROR: no filenames expected.\n";

    my $subcmd = $args{sub_command}
        or confess;

    my $handler = $handlers{$subcmd}
        or confess $subcmd;

	$handler->(\%args);
}

sub dashboard_make_pages($) {
	my $args   = shift;
	my $logger = Taranis::Log->new('dashboard-pages', $args->{log});

	my $screenConfig = Taranis::Config->new(find_config 'var/dashboard/layout.xml');
	my $config = Taranis::Config->new();
	my $dab    = Taranis::Dashboard->new( $config );
	my $tt     = Taranis::Template->new(config => $config);

	my @jsonData;
	my $items = $screenConfig->{item} || [];

	my (@maxi, @mini);

  ITEM:
	foreach my $item (@$items) {
		my $module_name = $item->{module}        or next;
	    my $processor   = $item->{dataProcessor} or next;
		my $generator   = $item->{dataGenerator};

		my $package     = "Taranis::Dashboard::$module_name";
		eval "use $package";
		if($@) {
			$logger->error("failed compiling $module_name: $@");
			next ITEM;
		};

		my $module = eval { $package->new($config, $item->{itemSettings}) }; 
		if($@) {
			$logger->error("cannot instantiate $module_name: $@");
			next ITEM;
		}

		if(! $module->can($processor)) {
			$logger->warning("module $module_name does not implement $processor");
			next ITEM;
		}

		if($generator && !$module->can($generator)) {
			$logger->warning("module $module_name does not provide $generator");
			next ITEM;
		}

		$module->$generator() if $generator;

		my $data = $module->$processor();
		push @jsonData, $data if ref $data eq 'HASH';

		my %vars = (
			template_toolkit_is_admin_begin => '[% IF is_admin %]',
			template_toolkit_is_admin_end   => '[% END %]',
			$processor  => {
				data         => $data,
				showMinified => $item->{showMinified},
			}
		);

		if(my $tpl_maxi = $module->{tpl}) {
			push @maxi, $tt->processTemplate($tpl_maxi, \%vars, 1);
		}

		if(my $tpl_mini = $module->{tpl_minified}) {
			push @mini, $tt->processTemplate($tpl_mini, \%vars, 1);
		}
	}

	# maxi in two columns
	my @maxi_left = splice @maxi, 0, @maxi/2;

	local $" = "\n    ";
	my $dashboardHtml = <<_PAGE_FRAGMENT;
	<div class="dashboard-content center">
	  <div class="block dashboard-column">
	    @maxi_left
	  </div>
	  <div class="block dashboard-column">
	    @maxi
	  </div>
	</div>
_PAGE_FRAGMENT

	# store dashboard
	$dab->setDashboardItems(
		type => $dab->{maximized},
		html => $dashboardHtml,
	    #XXX knowledge about storage form should move into $dab
		json => to_json(\@jsonData),
	);

	# store minified dashboard
	$dab->setDashboardItems(
		type => $dab->{minified},
		html => join('', @mini),
		json => ''
	);
}

1;
