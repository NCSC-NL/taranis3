# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis;

## Taranis.pm: various utility functions.

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use POSIX;
use HTML::Entities;    # qw(:DEFAULT encode_entities_numeric);
use Encode;
use Exporter;
use MIME::QuotedPrint;
use MIME::Base64;
use Data::Dumper;
use CGI::Simple;
use File::Basename;
use Cwd qw(realpath);
use Digest::MD5 qw(md5_base64);
use File::Spec  ();
use List::Util  qw(first);
use File::Glob  qw(bsd_glob);
use File::Path  qw(make_path);

use Taranis::FunctionalWrapper qw(CGI);

our @ISA = qw(Exporter);
our $VERSION = '3.5.1';

our %EXPORT_TAGS = ();
$EXPORT_TAGS{util} = [
	qw(
		nowstring trim logDebug formatDateTimeString teePrint say teeSay logErrorToSyslog generateToken
		scalarParam addThousandsSeparators round roundToSignificantDigits logN str2seconds fileToString
		encode_entities_deep decode_entities_deep textDigest normalizePath
		itemtype2text find_config tmp_path simplified_cpe scan_for_plugins
		shorten_html val_int val_date flat analysis_name trim_text
	)
];
$EXPORT_TAGS{all} = [
	@{$EXPORT_TAGS{util}},
	qw(
		keyword_ok decodeMimeEntity sanitizeInput sanatizeLink
	)
];
our @EXPORT_OK = @{$EXPORT_TAGS{'all'}};

sub tmp_path($);

# formatDateTimeString( '10-04-2014' ):
# Format a date like 'dd-mm-yyyy' to 'yyyymmdd'.
sub formatDateTimeString {
	defined $_[0] && $_[0] =~ /^\s*(\d\d?)\-(\d\d?)\-(\d\d\d\d)/
		or return undef;

	sprintf "%d%02d%02d", $3, $2, $1;
}

# nowstring($formatType, $numberOfDaysAgo): return a formatted time string.
# Usage:
#
#         command                 result (POSIX strftime)
#   --------------------------------------------------------
#   nowstring(0)  :             20090610 (%Y%m%d)
#   nowstring(1)  :             12:20:53 (%T)
#   nowstring(2)  :       20090610122053 (%Y%m%d%H%M%S)
#   nowstring(3)  :             20090609 (%Y%m%d) = yesterday
#   nowstring(4)  :           1244629253 (%s)
#   nowstring(5)  :           10-06-2009 (%d-%m-%Y)
#   nowstring(6)  :                 2009 (%Y)
#   nowstring(7)  :  10-06-2009 12:20:53 (%d-%m-%Y %T)
#   nowstring(8)  :               122053 (%H%M%S)
#   nowstring(9)  :             20090610 (%Y%m%d)
#   nowstring(10) :      20090610 122053 (%Y%m%d %H%M%S)
#   nowstring(11) :           2009-06-10 (%Y-%m-%d)
#   nowstring(12) :                   12 (%H)
#   nowstring(13) :            9-04-2014 (%d-%m-%Y) = yesterday
#
# Using parameter $numberOfDaysAgo will subtract days from now before formatting.
sub nowstring {
	my $type = $_[0];
	my $daysAgo = ( $_[1] ) ? $_[1] : 0;
	my $time = time();

	# type 3 en 13 is yesterday!
	if ( $type == 3  || $type == 13 ) {
		$time -= 86400
	} else {
		$time -= ( 86400 * $daysAgo );
	}

	my $timeformat = {
		0  => '%Y%m%d',
		1  => '%T',
		2  => '%Y%m%d%H%M%S',
		3  => '%Y%m%d', # yesterday
		4  => '%s',
		5  => '%d-%m-%Y',
		6  => '%Y',
		7  => '%d-%m-%Y %T',
		8  => '%H%M%S',
		9  => '%Y%m%d',
		10 => '%Y%m%d %H%M%S',
		11 => '%Y-%m-%d',
		12 => '%H',
		13 => '%d-%m-%Y' # yesterday
	};

	return strftime( "$timeformat->{$type}", localtime($time) );
}

# str2seconds: convert duration string, e.g. '2m', '3y' or '10s', to number of seconds.
sub str2seconds {
	my ($str) = @_;

	my %units = (
		s => 1,
		m => 60,
		h => 60 * 60,
		d => 60 * 60 * 24,
		w => 60 * 60 * 24 * 7,
		M => 60 * 60 * 24 * 30,
		y => 60 * 60 * 24 * 365
	);

	my ($number, $unit) = ($str =~ /^(\d+)([smhdwMy])$/) or die "invalid duration string '$str'";
	return $number * $units{$unit};
}


# trim($line): chop off all whitespace from beginning and end of a string.
sub trim {
	my $string = $_[0];
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# trim_text($text)
# Remove trailing blanks per line, and empty leading and trailing lines.
#XXX Would be nice to remove double blank lines as well, but that will
#XXX probably break some existing procedures.
sub trim_text($) {
	my $text = shift // '';
	for($text) {
		s/[\r\t ]+$//gm;
		s/\A\n+//;
		s/\n*\z/\n/;
	}
	$text;
}

# sanitizeInput: DO NOT USE.
sub sanitizeInput {
	my ( $type, @input ) = @_;

	for ( my $i = 0 ; $i < @input ; $i++ ) {
		next if ( !$input[$i] );
		for ($type) {
			if (/xml_primary_key/) {
				$input[$i] =~ s/[^\.\s\w\-:]//gi;
				$input[$i] =~ s/(\s)\s+/$1/gi;
			} elsif (/filename/) {
				$input[$i] =~ s/[^\.\w-]//g;
			} elsif (/only_numbers/) {
				$input[$i] =~ s/[^\d]//g;
			} elsif (/newline_to_br/) {
				$input[$i] =~ s/\n/\<br\/\>/gi;
			} elsif (/db_naming/) {
				$input[$i] =~ s/[^\w\d]//gi;
			} else {
				$input[$i] =~ s/[^\w]//gi;
			}
		}
	}
	return wantarray ? @input : "@input";
}

# Recursively walk through @_ and HTML-encode all scalars (including hash keys).
sub encode_entities_deep {
	return if not @_;

	if (wantarray) {
		return map {
			# Force scalar context so we don't endlessly recurse.
			scalar encode_entities_deep($_)
		} @_;
	} else {
		my $thing = shift;
		return [ encode_entities_deep(@$thing) ] if ref $thing eq 'ARRAY';
		return { encode_entities_deep(%$thing) } if ref $thing eq 'HASH';
		return encode_entities($thing);
	}
}

# Recursively walk through @_ and HTML-decode all scalars (including hash keys).
sub decode_entities_deep {
	return if not @_;

	if (wantarray) {
		return map {
			# Force scalar context so we don't endlessly recurse.
			scalar decode_entities_deep($_)
		} @_;
	} else {
		my $thing = shift;
		return [ decode_entities_deep(@$thing) ] if ref $thing eq 'ARRAY';
		return { decode_entities_deep(%$thing) } if ref $thing eq 'HASH';
		return decode_entities($thing);
	}
}

# decodeMimeEntity: try to decode MIME parts encoded in quoted-printable, base64 and utf8.
# Parameter $entity can be obtained by using Perl module MIME::Parser.
# $noHtmlPart and $noAttachment will exclude decoding MIME parts of type HTML and attachment, respectively.
sub decodeMimeEntity($$$);
sub decodeMimeEntity($$$) {
	my ($entity, $noHtmlPart, $noAttachment) = @_;

	if (my @parts = $entity->parts) {
		my @content;
		foreach my $part (@parts) {
			push @content, decodeMimeEntity $part, $noHtmlPart, $noAttachment;
		}
		return join '', @content;
	}

	my $head        = $entity->head();
	my $contentType = lc($head->mime_type() || 'text/plain');
	my $charset     = $head->mime_attr("content-type.charset")  || 'us-ascii';
	my $contentTransferEncoding = lc($head->mime_encoding() || '');

	return " " if $noHtmlPart   && $contentType eq 'text/html';
	return " " if $noAttachment && $contentType !~ m!^text/!;    #XXX wrong

	my $bodyContent = $entity->stringify_body();

	# remove transfer encodings
	if ( $contentTransferEncoding eq 'base64') {
		$bodyContent = decode_base64( $bodyContent );
	} elsif ($contentTransferEncoding eq 'quoted-printable') {
		$bodyContent = decode_qp( $bodyContent );
	}

	# Convert to Perl string, can die on unsupported charset
	my $string = eval { decode($charset, $bodyContent, Encode::FB_WARN) };
	if($@) {
		print "decodeMimeEntity error: $@\n";
		return $bodyContent;   # work with bytes
	}

	return $string;            # clean Perl string
}

# Add thousands separators to an integer: 12345678 => 12,345,678
sub addThousandsSeparators {
	my ($number) = @_;
	return
		# "876,543,21" => "12,345,678"
		scalar reverse(
				# ("876", "543", "21") => "876,543,21"
				join(
					",",
					# 12345678 => ("876", "543", "21")
					(reverse($number) =~ /(\d{1,3})/g
	) ) );
}

# Round $number to the nearest multiple of $increment (default 1).
# E.g. round(470, 50) => 450, round(1.234, .2) => 1.2, round(1.9) => 2.
sub round {
	my $number = shift;
	my $increment = shift || 1;
	return sprintf("%.0f", $number / $increment) * $increment;
}

# Round $number to $digits significant digits.
# E.g. roundToSignificantDigits(12345, 2) => 12000, roundToSignificantDigits(3.456, 3) => 3.46.
sub roundToSignificantDigits {
	my ( $number, $digits ) = @_;

	$number == 0 and return 0;
	$number < 0 and return -roundToSignificantDigits(-$number, $digits);

	return round(
		$number,
		10 ** (
			int(
				logN( $number, 10 )
			) + 1 - $digits
		)
	);
}

# Calculate base $base logarithm of $number: logN(1000, 10) => 3
sub logN {
	my ( $number, $base ) = @_;
	return log($number) / log($base);
}

# fileToString( '/path/to/some/file.txt' );
# Convert the contents of a file to string.
sub fileToString {
	my $filename = $_[0];
	my $output   = "";

	my $fh;
	open($fh, "<", $filename) or croak "fileToString: $!";
	while ( my $line = <$fh> ) {
		$output .= $line;
	}

	return $output;
}

# keyword_ok($keyword): check $keyword against a blacklist.
# If word is in blacklist, returns an empty string, otherwise will return the keyword.
sub keyword_ok {
	my $keyword = $_[0];
	my $blacklist;

	if ( index( $keyword, ")" ) > -1 )  { $keyword =~ s/\)/ /gi; }
	if ( index( $keyword, "(" ) > -1 )  { $keyword =~ s/\(/ /gi; }
	if ( index( $keyword, ":" ) > -1 )  { $keyword =~ s/\:/ /gi; }
	if ( index( $keyword, "\"" ) > -1 ) { $keyword =~ s/\"/ /gi; }
	if ( index( $keyword, "'" ) > -1 )  { $keyword =~ s/\'/ /gi; }
	if ( index( $keyword, "/" ) > -1 )  { $keyword =~ s/\// /gi; }

	$keyword = trim( uc($keyword) );

	$blacklist = "
    *THE**A**AND**DENIAL**SERVICE**OF**CORRUPTION**MEMORY**LEADS**TO*
    *CODE**EXECUTION**ANTIVIRUS**MULTIPLE**REMOTE**PRIVILEGE**ESCALATION*
    *VULNERABILITY**VULNERABILITIES**INFORMATION**DISCLOSURE**XSS*
    *CROSS**SITE**SCRIPTING**PRINT**SERVER**BUFFER**OVERFLOW**HEAP*
    *STACK**BASED**PARSE**EXCEPTION**HTML**XML**COMMAND**EXECUTION*
    *CORRUPTION**ACTIVEX**CREDENTIAL**DISCLOSURE**UNAUTHORIZED**ACCESS*
    *MALFORMED**ANTI-VIRUS**FORMAT**STRING**LINUX**ELEVATED**SQL**CLIENT*
    *RELEASED**ON**WITH**MICROSOFT**WINDOWS**FEDORA**REDHAT**RED**HAT*
    *UBUNTU**FREEBSD**OPENBSD**NETBSD**1**2**3**4**5**6**7**8**9**0*
    *SECURITY**FOR**INFORMATION**EXPLOIT**OPEN**HOLE**IN**-**INTEGER*
    *CROSS-SITE**ISSUE**BACKUP**LETS**FILE**FILES**:**,**;**.**/**DOS*
    *MAC**HANDLING**ENGINE**ANTI**ANTIVIRUS**VIRUS**SUN**CISCO**UBUNTU*
    *DEBIAN**UPDATE**EXPLORER**INTERNET**CORRUPT**CORRUPTION**MAY**LET*
    *USER**USERS**LOG**PROCESSING**APPLE**REQUEST**REQUESTS**SYSTEM*
    *LOCAL**TWO**ONE**THREE**FOUR**FIVE**SIX**SEVEN**EIGHT**NINE**TEN*
    *WEB**VULN**NEW**FROM**SUPPORT**PASSWORD**ORACLE**NOW**AVAILABLE*
    *COMMON**SERVICE**SERVICES**PAGE**PAGES**DIGITAL**PUT**OFF**WIRE*
    *ISSUES**IN**LIGHT**LIGHTS**WIRE**HOME**ADD**ADDS**MUSIC**DOWNLOAD*
    *REVERSE**BYPASS**SOCIAL**NETWORKING**PHYSICAL**NOTICE**RECEIVE*
    *RECEIVES**READIES**CRITICAL**PLAYER**MORE**MEDIA**MODULE*
    *BUFFER-OVERFLOW**EXTENDED**PICTURE**YEAR**GOOD**EVIL**BOTH**VS*
    *VS.**PACK**SHIP**SHIPPING**XP**2000**VISTA**HAND**HANDS**US*
    *U.S.**CONDEMN*CONDEMNS**CELEBRITY**CULTURE**FIRM**BUY**BUYS*
    *DOC**MGT**ALL-IN-ONE**PLAN**REPORT**REPORTS**MOVIE**ONLINE*
    *FREE**UNSPECIFIED**INJECTION**BLIND**PACKAGE**PACKAGES**NEW*
    *FIX**TOP**CYBER**CRIME**CYBERCRIME**UPDATED**CVE**UPLOAD**EXEC*
    *BACKUP**EXECUTE**ARBITRARY**BUG**FRSIRT**IDEFENSE**ADVISORY**NOTE*
    *CERT-IN*
    *ZIJN**IS**DE**EEN**HET**VIRUSSCANNER**GEBRUIKERS**UIT**BREKEN*
    *AAN**RODE**ROOD**KAART**VAN**DEEL**KLAAR**EERSTE**RUSSISCH*
    *NEDERLANDS**BIJ**WELKOM**KEER**GROEIEN**GROEIT**STELLEN**DIVISIE*
    *KNAAGT**BEWONERS**ONRUST**MINISTER**VRAGEN**VRAAGT**OPLOSSING*
    *VERKOOP**VERWACHT**NEMEN**STERKER**KRIJGT**KRIJGEN**GESTOLEN*
    *NAAR**ACHTER**DODE**DODEN**DOOR**BOVEN**BUITEN**CIRCA**CONFORM*
    *DANKZIJ**DOOR**MET**MIDDEN**NABIJ**NAMENS**ONDANKS**OVER**ONDER*
    *PER**PLUS**ROND**SINDS**TEGEN**TEGENOVER**TIJDENS**TOT**TUSSEN*
    *UIT**VAN**VANAF**VANUIT**VANWEGE**VIA**VOOR**VOORBIJ**WEGENS*
    *ZONDER**WORDEN**WORDT**KUNNEN**DICHTERBIJ**HUN**NIET**MEER*";

	if (
		( index( $blacklist, "*" . $keyword . "*" ) > -1 )
		|| ( length($keyword) < 3 )
	) {
		return '';
	} else {
		return $keyword;
	}
}

# say($text): just like print() but with a newline.
sub say {
	return print("@_\n");
}

# teeSay($text): just like teePrint() but with a newline.
sub teeSay {
	say $_[0];
	return $_[0];
}

# teePrint: a "chainable' version of &print. Handy for "inline printing", e.g.
# $x = foo() + teePrint bar();  # Same as {my $bar = bar(); print $bar; $x = foo() + $bar;}, but shorter.
sub teePrint {
	print $_[0]
		or croak "print() failed: $!\n";
	return $_[0];
}

# logDebug($text): only used for debugging/developing.
# Warning: with apache under systemd maybe in /tmp/systemd-private-*/tmp/...
sub logDebug {
	my ($thing) = @_;

	my $path = tmp_path('debug.log');
	open(my $fh, '>>:encoding(utf8)', $path)
		or croak "logDebug: failed to open $path for writing: $!";

	print $fh "[" . nowstring(7) . "]: \n";
	print $fh ref $thing ? Data::Dumper->new([$thing])->Terse(1)->Dump : $thing;
	close $fh;

	return $thing;
}

# logErrorToSyslog($errorMessage): log $errorMessage to SYSLOG.
sub logErrorToSyslog {
	my $error = shift;
	my ( $package, $file, $line ) = caller();
	Taranis::Database::logError( { log_error_enabled => 1 } ,"$file, $line : " . ($error || ''), 'error' );
	return $error;
}

sub _decodeUtfOrDie {
	my $bytes = shift;
	return decode('UTF-8', $bytes, Encode::FB_CROAK);
}

# CGI::Simple::param (and our shortcut for it, CGI->param) returns a scalar or a list depending on context and number
# of parameters, which is dangerous (as explained in detail in the 31C3 talk "The Perl Jam",
# https://www.youtube.com/watch?v=gweDBQ-9LuQ).
# Use scalarParam instead to be sure you'll get a scalar (which of course may be still be '' or undefined).
# Comes with free UTF-8 decoding, since all params should always be in UTF-8, and we should always be working with
# decoded strings (i.e. character strings, not byte strings).
sub scalarParam {
	my ($paramName) = @_;
	return _decodeUtfOrDie scalar CGI->param($paramName);
}

# Generate pseudorandom hexadecimal string with $num_bytes entropy, from /dev/urandom.
sub generateToken {
	my ($num_bytes) = @_;

	open(my $fh, '<', '/dev/urandom')             or croak "cannot open /dev/urandom: $!";
	read($fh, my $buf, $num_bytes) == $num_bytes  or croak "failed to read from /dev/urandom: $!";
	return unpack('H*', $buf);
}

# Make digest of some piece of text (i.e. a character string), for use as unique identifier in our database.
# Since MD5 can only deal with bytes, not characters, encode into UTF8 before MD5ing.
sub textDigest($) {
	return md5_base64(encode_utf8(shift));
}

# Normalizes a path, accepts both relative and absolute paths.
sub normalizePath {
	my ($path) = @_;

	if ($path =~ /^\//) {
		$path = realpath($path);
	} else {
		$path = realpath(dirname(__FILE__) . "/../" . $path);
	}

	if (-d $path) {
		$path = $path . '/';
	}

	return $path;
}

# Sanatize //foo.com/bar style links to http://foo.com/bar links
sub sanatizeLink {
	my ($link) = @_;

	if ($link =~ /^\/\//) {
		$link = "http:".$link;
	}

	return $link;
}

# Translate internal item type codes into human text
my %itemtypeTexts = (
	assess  => 'news item',
	analyze => 'analysis',
    # eos/eod/eow/advisory all same
);

sub itemtype2text($) {
	my $type = shift;
	$itemtypeTexts{$type} || $type;
}

=over 4


=item my $filename = find_config $config_base;

Search the directory path in the APPCONFIG_PATH environment variable
for configuration file.  The C<$config_base> is usually a path, like
C<var/cron.often>.  The configuration file is not loaded.

=cut

my @conf_path;
sub find_config($) {
    my $fn = shift;
    return $fn if substr($fn, 0, 1) eq '/';

	unless(@conf_path) {
		# ENV not available at compile-time in mod-perl
		my $conf_path = $ENV{APPCONFIG_PATH} or die "No APPCONFIG_PATH";
		@conf_path    = split /\:/, $conf_path;
	}

    -e "$_/$fn" && return "$_/$fn"
        for @conf_path;

    ();
}


=item my $name = tmp_path $basename;

Produce a file or directory name in the working directory, indicated
by the TMPDIR environment variable.  You have to create and remove
the items yourself.

=cut

sub tmp_path($) {
	my $base = shift;
	my $path = File::Spec->rel2abs($base, $ENV{TMPDIR});

	# We will create upto the parent dir automatically (f.i. it may be in
	# a tmpfs which is cleaned-up at system reboot), but the final dir or
	# file must be created by the routine which uses this output.
	make_path((dirname $path), {mode => 0770});
	$path;
}


=item my $id = simplified_cpe $cpe;

For the purpose of Taranis, the CPEs are too detailed: often, it is
unclear which exact version of a product is in use with the constituent.
So, we can better use a reference which does not include a version
number.

=cut

sub simplified_cpe($) {
	my $cpe = shift;
	my ($prefix, $part, $vendor, $product, $version) =   # there are more
		split /\:/, $cpe;
	"$prefix:$part:$vendor:$product:";
}


=item my $plugins = scan_for_plugins $pkg, %options

Search the C<@INC> path (set by 'use lib' and the PERL5LIB environment
variable) for files which seem to contain code in the C<$pkg> namespace.

It is a pity that there is no assurance that implementers are not
enforced to have matching package names and file names in Perl.  Gladly,
nearly everyone does it right automatically.

Example:

	my $p = scan_for_plugins 'Taranis::Command', load => 1;
	# May load  Taranis::Commmand::Install

=cut

sub scan_for_plugins($%) {
	my ($namespace, %args) = @_;
	(my $subpath = $namespace) =~ s!\:\:!/!g;
	my $autoload = $args{load};

	my %pkgs;
	foreach my $inc (@INC) {
		ref $inc && next;    # ignore code refs
		foreach my $filename (bsd_glob "$inc/$subpath/[!_]*.pm") {

			my $pkg = $filename;
			for($pkg) {
				s!.*\Q$inc/!!;
				s!\.pm$!!;
				s!/!::!g;
			}
			next if $pkgs{$pkg};

			$pkgs{$pkg} = $filename;

			(my $plugin_base = $filename) =~ s!^\Q$inc/\E!!;
			my $has = first { /\Q$plugin_base\E$/ } keys %INC;
			next if $has;

			eval "use $pkg () ;1"
				or die "ERROR: failed to load plugin $pkg from $filename:\n$@";
		}
	}
	\%pkgs;
}

=item my $short_html = shorten_html $html, $size

When the $string is shorter than $size, it gets returned unmodified.  When it
is longer, the $string get shorted.  An attempt is made to chop at word
bounderies.  HTML entities will be stripped-off cleanly.

=cut

sub shorten_html($$) {
	my ($str, $len) = @_;
    return $str if length $str <= $len;
	$len > 7 or die;

	# only fine-tune around shop-off
	substr $str, $len+10, -1, ''
		if length $str > $len+10;

	while(length $str > $len-4) {
	  $str =~ s/\s+(?:\S|\&[a-z]\w{1,5}\;){1,10}$// # strip word
	  || $str =~ s/\&[a-z]\w{1,5}\;$// # entity at the end
	  || $str =~ s/.$//;               # anything to get shorter
	}

	$str . ' ...';
}

=item my $int = val_int $value

Returns the cleaned-up $value, when it is numeric.  May contain blanks.

=item my $date = val_date $value

Return the date as YYYY-MM-DD when it has forms YYYYMMDD or YYYY-MM-DD.

=item my @values = flat $value|\@array|undef

Returns a list of values.  If an C<undef> is passed, the list will be empty.

=cut

sub val_int($)  { defined $_[0] && $_[0] =~ /^\s*(\d+)\s*$/a ? $1 : undef }
sub val_date($) { defined $_[0] && $_[0] =~ /^\s*(\d{4})\-?(\d{2})\-?(\d{2})\s*$/a ? "$1-$2-$3" : undef }
sub flat($) { ref $_[0] eq 'ARRAY' ? @{$_[0]} : defined $_[0] ? $_[0] : () }


=item analysis_name CODE
The analysis name is stored as 8 digit integer, and converted to a name on
many places.  For instance, C<12345678> becomes C<AN-1234-5678>
=cut

sub analysis_name($) {
	$_[0] =~ /^([0-9]{4})([0-9]{4})$/ ? "AN-$1-$2" : "ERROR $_[0]";
}

1;
