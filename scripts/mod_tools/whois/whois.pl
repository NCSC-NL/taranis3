#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use strict;
use Taranis::Template;
use Taranis::Config;
use Taranis::FunctionalWrapper qw(Config);
use Taranis::HttpUtil qw(lwpRequest);
use Taranis qw(:all);
use JSON;
use Net::hostent;
use Socket;

use Data::Dumper;

my @EXPORT_OK = qw(displayWhois getWhoisHost doWhoisLookup);

sub whois_export {
	return @EXPORT_OK;
}

sub displayWhois {
	my ( %kvArgs) = @_;	
	
	my $vars;
	my $tt = Taranis::Template->new;
	$vars->{body_multiple} = 0;
	$vars->{body_result}   = 0;
	$vars->{body_error}    = 0;
	
	my $htmlContent = $tt->processTemplate( 'whois.tt', $vars, 1 );
	my $htmlFilters = $tt->processTemplate( 'whois_filters.tt', $vars, 1 );
	
	my @js = ('js/whois.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
}

sub getWhoisHost {
	my ( %kvArgs) = @_;	
	
	my $tt = Taranis::Template->new;
	
	my ( $host, $whoisPage, $vars );

	my $whoisHost = $kvArgs{whois};

	$whoisHost =~ s/\ //gi;
	$whoisHost =~ s/https?\:\/\///gi;
	
	if (index($whoisHost, "/") > -1) {
		$whoisPage = substr( $whoisHost, index( $whoisHost, "/" ) );
		$whoisHost = substr( $whoisHost, 0, index( $whoisHost, "/" ) );
	}
	
	$whoisHost =~ s/($whoisHost)\/.*$/$1/;

	eval{ 
		$host = gethost( $whoisHost );
	};
	
	if ( $host ) {
		my @hostIpNumbers;
	
		if ( @{ $host->addr_list } > 1 ) {

			for my $addr ( @{ $host->addr_list } ) {
				push @hostIpNumbers, inet_ntoa( $addr );
			}
		} else {
			push @hostIpNumbers, inet_ntoa( $host->addr );
		}
	
		my %host_ipnrs = map( { $_ => 1 } @hostIpNumbers );
		my @ips = sort keys %host_ipnrs;
	
		$vars->{body_multiple} = 1;
		$vars->{body_result}   = 0;
		$vars->{body_error}    = 0;
		$vars->{ips}           = \@ips;
		$vars->{whois_page}    = $whoisPage;
		$vars->{whois_host}	   = $whoisHost;		
	} else {
		$vars->{body_error} = 1;
	}
	
	my $htmlContent = $tt->processTemplate( 'whois.tt', $vars, 1 );
	my $htmlFilters = $tt->processTemplate('whois_filters.tt', $vars, 1);
	
	my @js = ('js/whois.js');
	
	return { content => $htmlContent, filters => $htmlFilters, js => \@js };
	
}

sub doWhoisLookup {
	my ( %kvArgs) = @_;	
	
	my ( $vars, @whoisResults, $idx1, $idx2 );
	my $tt = Taranis::Template->new;

	my $whoisIp = $kvArgs{whois};
	my $whoisPage = $kvArgs{page};
	my $whoisHost = $kvArgs{host};
	my $myIp = $ENV{'REMOTE_ADDR'};

	$vars->{body_result} = 1;
	$vars->{body_multiple} 	= 0;
	$vars->{body_error} = 0;
    $vars->{get_ip} = $myIp;
    $vars->{get_whois_ip} = $whoisIp;

### Whois #1: Team Cymru
	my $cymru = httpPOST (
		"http://asn.cymru.com/cgi-bin/whois.cgi",
		Content => "action=do_whois&addr=" . $myIp . "&family=ipv4&method_whois=whois&flag_cc=cc&bulk_paste=" . $whoisIp . "&submit_paste=Submit",
	);
	$idx1 = index(uc($cymru), "<PRE>") + 51;
	$idx2 = index(uc($cymru), "</PRE>");
	$cymru = substr($cymru, $idx1+5, $idx2 - $idx1 - 5);
	push @whoisResults, { source => "Cymru", output => $cymru };

### Whois #2: RIPE
	my $ripe = httpGET("http://rest.db.ripe.net/search?source=ripe&query-string=" . $whoisIp, accept => 'application/json');
	my $ripeResponse;
	eval{
		$ripeResponse = from_json($ripe);
	};

	if ( $@ ) {
		logErrorToSyslog( $@ );
	} else {
		my $ripeOutput = '<div><table style="border: none !important; font-family: courier; font-size: 11px; color: #666">';
			foreach my $object ( @{ $ripeResponse->{objects}->{object} } ) {
				foreach my $attribute ( @{ $object->{attributes}->{attribute} } ) {
					$ripeOutput .= '<tr><td style="border: none;padding-right: 10px;">' . $attribute->{name} . '</td>';
					$ripeOutput .= '<td style="border: none;">' . $attribute->{value} .'</td></tr>';
				}
				$ripeOutput .= "<tr><td>&nbsp;</td><td>&nbsp;</td></tr>";
			}
		$ripeOutput =~ s/^(.*?)<tr><td>&nbsp;<\/td><td>&nbsp;<\/td><\/tr>$/$1/;
		$ripeOutput .= '</table></div>';
		push @whoisResults, { source => "RIPE", output => $ripeOutput };
	}
### Whois #3: ARIN
	my $arin = httpGET ("http://whois.arin.net/rest/ip/" . $whoisIp);

	$arin =~ s/<registrationDate>/Registration date\:/gi;
	$arin =~ s/<\/registrationDate>/\n/gi;
	$arin =~ s/<ref>/Reference\:/gi;
	$arin =~ s/<\/ref>/\n/gi;
	$arin =~ s/<endAddress>/End Address\:/gi;
	$arin =~ s/<\/endAddress>/\n/gi;
	$arin =~ s/<handle>/Handle\:/gi;
	$arin =~ s/<\/handle>/\n/gi;
	$arin =~ s/<name>/Name\:/gi;
	$arin =~ s/<\/name>/\n/gi;
	$arin =~ s/<netBlocks>//gi;
	$arin =~ s/<\/netBlocks>//gi;
	$arin =~ s/<netBlock>/\nNetblock\:/gi;
	$arin =~ s/<\/netBlock>/\n/gi;
	$arin =~ s/<cidrLength>/\nCIDR Length\:/gi;
	$arin =~ s/<\/cidrLength>/\n/gi;
	$arin =~ s/<startAddress>/Start Address\:/gi;
	$arin =~ s/<updateDate>/Update Date\:/gi;
	$arin =~ s/<description>/Description\:/gi;
	$arin =~ s/<\/description>/\n/gi;
	$arin =~ s/<type>/Type\:/gi;
	$arin =~ s/<\/type>/\n/gi;
	$arin =~ s/<\/netBlock>/\n/gi;
	$arin =~ s/<\//<\/\n/gi;
	$arin =~ s/<orgRef(.*?)\/orgRef>//gi;
	$arin =~ s/<parentNetRef(.*?)\/parentNetRef>//gi;
	$arin =~ s/<version(.*?)\/version>//gi;
	$arin =~ s/<(.*?)>//gi;

	if ( $arin ) {
		push @whoisResults, { source => "ARIN", output => $arin };
	}

### Whois #5: APNIC
	my $apnic = httpPOST (
		"http://wq.apnic.net/apnic-bin/whois.pl",
		Content => "searchtext=" . $whoisIp . "&whois=Go",
	);
	$idx1 = index(uc($apnic), "<PRE>");
	$idx2 = index(uc($apnic), "</PRE><DIV");
	$apnic = substr($apnic, $idx1 + 5, $idx2 - $idx1 - 5);
	$apnic =~ s/<(.*?)>//gi;
	if (index(uc($apnic), "RANGE ARE NOT REGISTERED") > -1) { $apnic = ""; }
	if (index(uc($apnic), "DOES NOT CONTAIN") > -1) { $apnic = ""; }
	if (index(uc($apnic), "NOT ALLOCATED TO APNIC") > -1) { $apnic = ""; }
	if (index(uc($apnic), "PLEASE SEARCH ONE OF THE") > -1) { $apnic = ""; }
	if ( $apnic ) {
		push @whoisResults, { source => "APNIC", output => $apnic };
	}

### Whois #6: LACNIC
	my $lacnic = httpPOST (
		"http://lacnic.net/cgi-bin/lacnic/whois?lg=EN",
		Content => "query=" . $whoisIp . "&Submit=Whois+Search",
	);
	$idx1 = index(uc($lacnic), "<PRE>");
	$idx2 = index(uc($lacnic), "</PRE>");
	$lacnic = substr($lacnic, $idx1 + 5, $idx2 - $idx1 - 5);
	$lacnic =~ s/<(.*?)>//gi;
	if (index(uc($lacnic), "THIS INFORMATION HAS BEEN PARTIALLY MIRRORED") > -1) { $lacnic = ""; }
	if (index(uc($lacnic), "ARIN RESOURCE:") > -1) { $lacnic = ""; }
	if (index(uc($lacnic), "RIPENCC RESOURCE:") > -1) { $lacnic = ""; }
	if (index(uc($lacnic), "AFRINIC RESOURCE:") > -1) { $lacnic = ""; }
	if (index(uc($lacnic), "APNIC RESOURCE:") > -1) { $lacnic = ""; }
	if ( $lacnic ) {
		push @whoisResults, { source => "LACNIC", output => $lacnic };
	}

### Whois #7: Robtex
#	my $robtex = httpGET ("http://www.robtex.com/ip/" . $whoisIp . ".html");
#	my $idx = index ($robtex, "<table class=\"t\" sum");
#	$robtex = substr ($robtex, $idx + 10);
#	$idx = index ($robtex, "td0");
#	my $records = "";
#	while ($idx > 0) {
#		$robtex = substr ($robtex, $idx + 3);
#		$idx = index ($robtex, "/dns/");
#		$robtex = substr ($robtex, $idx + 5);
#		$idx = index ($robtex, ".html");
#		$records = $records . "- " . substr ($robtex, 0, $idx) . "<br/>";
#		$robtex = substr ($robtex, $idx + 5);
#		$idx = index ($robtex, "td0");
#	}
#	if ($records ne "") {
#		$records = "Passive DNS results for " . $whoisIp . ":<br /><br />".  $records;
#		push @whoisResults, { source => "Robtex", output => $records };
#	}

### Whois #8: Get domain WHOIS (if applicable)
#	if ($whoisHost ne $whoisIp) {
#		my $whois_host_tmp =  $whoisHost;
#		my $count = ($whois_host_tmp =~ tr/\.//);
#		while ($count > 1) {
#			$idx1 = index($whois_host_tmp, ".");
#			$whois_host_tmp = substr($whois_host_tmp, $idx1+1);
#			$count = ($whois_host_tmp =~ tr/\.//);
#		}
#		my $domwhois = httpGET ("http://www.whois-search.com/whois/" . $whois_host_tmp);
#		$idx1 = index ($domwhois, "<pre>");
#		$idx2 = index ($domwhois, "</pre>");
#		$domwhois = trim(substr($domwhois, $idx1 + 5, $idx2 - $idx1 - 6));
#		$domwhois =~ s/\/text2image/http\:\/\/www.whois-search.com\/text2image/gi;
#		push @whoisResults, { source => "WhoisSearch", output => $domwhois };
#	}

### Whois #9: analyze malicious page
	my $page = httpGET ("http://" . $whoisHost . $whoisPage);
	$page =~ s/'/"/gi;
	my $uc_page = uc($page);
	my @indexes;
	my $i = 0;
	for ($i = 0; $i < length($page); $i++) {
		if (substr($uc_page, $i, 6) eq " SRC=\"") { 
			push @indexes, { index => ($i + 6) } 
		};
	}         
	for ($i = 0; $i < length($page); $i++) {
		if (substr($uc_page, $i, 6) eq "HREF=\"") { 
			push @indexes, { index => ($i + 6) } 
		};
	}         

	my $idx = 0;
	my $tmp = "";
	my $link = "";
	my @links;
	foreach ( @indexes ) { 
		$tmp = substr ($page, $_->{index});
		$idx = index ($tmp, "\"");
		$link = substr ($tmp, 0, $idx); 
		if (substr (uc($link), 0, 4) ne "HTTP") { 
			if (substr ($link, 0, 1) eq "/") {
				$link = "http://" . $whoisHost . $link; 
			} else {
				my $lastslash = 0;
				if (length($whoisPage) == 0) { $whoisPage = "/"; }
				for (my $i = 0; $i < length ($whoisHost . $whoisPage); $i++) {
					if (substr ($whoisHost . $whoisPage, $i, 1) eq "/") {
						$lastslash = $i;
					}
				}
				$link = "http://" . substr ($whoisHost . $whoisPage, 0, $lastslash) . $link; 
			}
		}
		push @links, $link;
	}
	@links = sort(@links);

	my $linktext = "Links on 'http://" . $whoisHost . $whoisPage . "':<br/><br/>";
	my $prev_link = "";
	foreach ( @links ) {
		if ($prev_link ne $_) {
			my $printlink = $_;
			if ( length( $printlink ) > 85) { 
				$printlink = substr ($printlink, 0, 85) . "[...]"; 
			}
			$linktext .= "- <a href=\"" . $_ . "\">" . $printlink . "</a><br/>"; 
		}
		$prev_link = $_;
	}
	push @whoisResults, { source => "Taranis", output => $linktext };

### Final step: Notice-and-Take Down (NTD) mail
	my $body = "";
	foreach ( @whoisResults ) {
		$body .= $_->{output};
	}

	my %abuse_to;
	$abuse_to{lc $_}++ for $body =~ m/abuse\@[a-z0-9.\-]+/gi;
	my $abuse_to = keys %abuse_to ? join('; ', keys %abuse_to) : '<unknown>';

	$vars->{abuse} = { source => "Taranis", cymru => $cymru, abuse_to => $abuse_to };
	$vars->{whois_ip} = $whoisIp;
	$vars->{whois_page} = $whoisPage;
	$vars->{abuse_mail} = $tt->processTemplate( "abuse.tt", $vars, 'noprint' );
	push @whoisResults, { source => "Taranis", output => $vars->{abuse_mail} };

	$vars->{results} = \@whoisResults;

	my $htmlContent = $tt->processTemplate( 'whois.tt', $vars, 1 );
	
	return { content => $htmlContent };
}

## HELPERS
sub httpGET {
	my ($url, %headers) = @_;
	my $res = lwpRequest(get => $url, %headers);

	if ( $res->is_success ) {
		return $res->content;
	} else {
		return "ERROR: " . $res->status_line;
	}
}

sub httpPOST {
	my ($url, %headers) = @_;
	my $res = lwpRequest(post => $url, %headers);

	if ( $res->is_success ) {
		return $res->content;
	} else {
		return "ERROR: " . $res->status_line;
	}
}

1;
