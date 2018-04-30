# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Install::Perl;
use base 'Exporter';

use warnings;
use strict;
use version;

use Config            qw(%Config);
use CPAN;
use CPAN::FirstTime;
use File::Copy        qw(move);
use Pod::Man          ();
use Data::Dumper      ();

use Taranis::Install::Bare   qw(has_internet);
use Taranis::Install::Config qw(config_generic config_release taranis_sources);

our @EXPORT = qw(
	perl_install
	perl_install_cleanup
	perl5lib
	perl5man
	cpan_init
	pod2man
);

sub cpan_init($) {
	my $outfile = shift;
	return if -f $outfile;

	my $generic = config_generic;

	print "*    installation of perl modules from CPAN into $outfile\n";

	# It's a pity that CPAN.pm does not have a configuration option for this.
	# The next lines are all to work around trickery of CPAN.pm; the module
	# tries to avoid accidents for "normal" users, for the cost of automatic
	# procedures.
	$CPAN::Config->{urllist} = [ '' ];
	$CPAN::Config->{mbuildpl_arg} = "install_base";

	my $product = "$generic->{home}/.cpan/CPAN/MyConfig.pm";
	unlink $product;

	my $config = CPAN::FirstTime::init('CPAN/Config.pm',
		autoconfig   => 1,
		install_help => 'local::lib',
	);

	move $product, $outfile
		or die "ERROR: could not move $product to $outfile: $!\n";
}

# We create this before each run: composed from the special settings by
# the application maintainers, combined with the defaults of the latest
# CPAN.pm

sub _make_runconfig() {
	my $generic = config_generic;
	my $runconfig_fn = "$generic->{home}/.cpan/CPAN/MyConfig.pm";
	my $myconfig_fn  = $generic->{cpan_myconfig} or die;
	my $config_fn    = $generic->{cpan_config}   or die;

    return 1
		if -f $runconfig_fn
		&& -M $runconfig_fn > -M $myconfig_fn
		&& -M $runconfig_fn > -M $config_fn;

	print "Compose CPAN configuration in $runconfig_fn\n";

	do $config_fn or die;
	my $config   = $CPAN::Config;

	do $myconfig_fn or die;
	my $myconfig = $CPAN::MyConfig;
	@{$config}{keys %$myconfig} = values %$myconfig;

	open my $fh, '>:encoding(utf8)', $runconfig_fn
		or die "ERROR: cannot create $runconfig_fn: $!\n";

	$fh->print(Data::Dumper->new([$config], ['$CPAN::Config'])
		->Indent(1)->Sortkeys(1)->Dump, "\n1;\n");

	$fh->close
		or die "ERROR while writing $runconfig_fn: $!\n";
	1;
}

my $done_init = 0;
sub perl_init() {
	return if $done_init++;

	_make_runconfig;

	my $generic = config_generic;

	my $home          = $generic->{home} or die;

	# Also added to ~/lib/bash_profile to be able to install additional
	# Perl modules by hand.
	$ENV{PERL_MM_OPT} = qq(INSTALL_BASE="$home");
	$ENV{PERL_MB_OPT} = qq(--install_base "$home");

	my $lib           = $generic->{perl_lib} or die;
	$ENV{PERL5LIB}    = "$lib:$lib/$Config{archname}:$ENV{PERL5LIB}";
}

sub perl_install($;$%) {
	my ($module, $min_version, %args) = @_;

	unless(has_internet) {
		print "--> no internet: no install/upgrade for $module $min_version\n";
		return 0;
	}

	my $new_count = 0;

	perl_init;

	# inst_version requires the module to be in the path
	my $generic = config_generic;
	my $lib = $generic->{perl_lib};
	local @INC = ($lib, "$lib/$Config{archname}", @INC);

	my @mods = CPAN::Shell->expand(Module => $module);
	@mods or die "ERROR: perl module $module does not exist.\n";

	foreach my $mod (@mods) {
		my $has_version = $mod->inst_version;
		if(defined $has_version && $has_version ne 'undef'
		&& defined $min_version
		&& version->parse($has_version) >= version->parse($min_version)) {
			print "*   $module is already installed, version $has_version\n";
			next;
		}

		print "*   installing perl module $module\n";
		my $dist = $mod->distribution;
		print "    distribution " . $dist->pretty_id . "\n";

		CPAN::Shell->install($dist);

		CPAN::Shell->reload('cpan')
			if $module eq 'CPAN';

		$new_count++;
	}

	$new_count;
}

sub perl_install_cleanup() {
	my $generic = config_generic;
	my $home    = $generic->{home};
	system "rm -rf $home/.cpan/build/* $home/.cpan/Metadata";
}

sub pod2man($$$) {
	my ($section, $module_fn, $package) = @_;
	(my $sectnum = $section) =~ s/\D//g;

	my $release = config_release;
	my $manpath = "$release->{install}/man/man$sectnum";
	my $outfile = "$manpath/$package.$section";

	return
		if -f $outfile
		&& -M $outfile < -M $module_fn
		&& -M $outfile < -M __FILE__;

	my $parser  = Pod::Man->new(
		center  => 'NCSC-NL Taranis',
		release => "Taranis $release->{version}",
		section => $section,
#	errors  => 'die',
		name    => $package,
	);

	$parser->parse_from_file($module_fn, $outfile);
	if($parser->{CONTENTLESS}) {
		unlink $outfile;
		return;
	}

	# When the manual-page is not modified, it will not get installed.
	# However, in that case -M $outfile will stay < -M __FILE__
	system 'touch', $outfile;
	print "*   created manual in man$sectnum/$package.$section\n";
}

sub perl5lib(;$) {
	my $version  = shift;
	my $generic  = config_generic;
	my $release  = config_release $version;

	my $archname = $Config{archname};

	my @code;
	if($version eq 'git') {
		# own code used uninstalled
		my $sources = taranis_sources $version;
		push @code, "$sources/pm";
	} else {
		# own code used installed
		push @code, 
			"$release->{install}/perl5",
			"$release->{install}/perl5/$archname"; 
	}

	grep -d,
		"$release->{extension}/perl5",           # release specific local extension
		"$release->{extension}/perl5/$archname", #   " XS
		"$generic->{extension}/perl5",           # generic local extensions
		"$generic->{extension}/perl5/$archname", #   " XS
		@code,                                   # my own code
        "$generic->{charts}/lib",                # ChartDirector has a perl interface
        "$generic->{lib}/perl5",                 # CPAN perl
        "$generic->{lib}/perl5/$archname";       #   " XS
}

sub perl5man(;$) {
	my $version  = shift;
	my $generic  = config_generic;
	my $release  = config_release $version;

	grep -d,
		"$release->{extension}/man",
		"$generic->{extension}/man",
		"$release->{install}/man",               # my own modules
		"$generic->{home}/man";                  # CPAN modules
}

1;
