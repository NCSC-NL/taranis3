# This file is part of Taranis, Copyright TNO.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Clustering::Document;

use strict;

use Taranis::Clustering::Tokenizer;
use Lingua::Identify qw(:language_identification);
use Time::Local;
use HTML::Entities;

my $DEBUG = 0;

my $TOKENIZER = Taranis::Clustering::Tokenizer->new();
my $TWEET_CATEGORY   = 6;

## Constructor

sub new() {
	my $class = shift;
 	bless {}, $class;
}

sub get($) {
	my ($self, $attr) = @_;

	warn "WARNING: $attr not defined in Document object\n"
		if ! defined $self->{$attr} && $DEBUG;

	$self->{$attr} // '';
}

sub set($$) {
	my ($self, $attr, $value) = @_;
	$self->{$attr} = $value;
}

sub load($$) {
	my ($self, $fields, $language) = @_;

	$self->{ID}        = $fields->{digest};
	$self->{Title}     = clean($fields->{title});
	$self->{Description} = clean($fields->{description});
	$self->{Timestamp} = $fields->{created};
	$self->{Epoch}     = $self->timestampToEpoch($fields->{created});
	$self->{Category}  = $fields->{category};
	$self->{Source}    = $fields->{source};
	$self->{URL}       = $fields->{link};
	$self->{Status}    = $fields->{status};
	$self->{ClusterID} = $fields->{cluster_id};
	$self->{Score}     = $fields->{cluster_score} || 'SEED';

	## hack for tweets: ignore the title (which is a copy of the tweet text)
	#
	if($self->{Category} == $TWEET_CATEGORY){
	  $self->{Title} = '';
	}

	## tokenize the text
	#
	for('Title', 'Description'){
	  my $t = decode_entities($self->{$_});
	  specialTweetTreatment(\$t);
	  my @tokens = $TOKENIZER->tokenize( $t );
	  $self->{Text} .= ' '.join(" ", @tokens);
	}

	$self->{Text} =~ s/\s{2,}/ /g;

	## set the language if language param for document has been set, otherwise
	#  guess it
	if ( $language ) {
	  $self->{Lang} = $language;
	} else {
	  $self->{Lang} = langof($self->{Text})
	    if defined($self->{Text}) && length($self->{Text});
	}

	## create the language model (i.e. the probability distribution)
	$self->createLanguageModel();
	$self;
}

sub timestampToEpoch{
	my ($self, $t) = @_;

	defined $t
		or return '';

	$t =~ s/[+.].*$//;  # remove TZ and milisecs

	my ($year, $mon, $mday, $hour, $min, $sec)= split /[\s:_\-]/, $t;
	timegm($sec, $min, $hour, $mday, $mon-1, $year);
}

sub createLanguageModel() {
	my $self   = shift;

	my $total  = 0;
	my (%tf, %probs);
  	foreach my $t (split " ", $self->{Text}) {
		$tf{$t}++;
    	$total++;
  	}

	my %probs = map +( $_ => $tf{$_}/$total ), keys %tf;

	$self->{TF}     = \%tf;
	$self->{Probs}  = \%probs;
	$self->{Tokens} = [ keys %tf ];
	$self->{Doclen} = $total;
}

sub clean{
	my $string = shift;
	$string =~ s/\#{2,}/ /g;
	$string =~ s/\s{2,}/ /g;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	$string;
}

sub specialTweetTreatment{
	my $textref = shift;
	$$textref =~ s/\@\w+//g;
	$$textref =~ s/\brt\b//ig;
	$$textref =~ s/\bhttp:[\\\/\.\w+]+\/(\w+)\b/$1/g;
	$$textref =~ s/(?:profile_url|status_id)//ig;
}

sub getWordFreq($) {
	my ($self, $word) = @_;
	$self->{TF}{$word} // 0;
}

1;

__END__

=head1 NAME

Document - A module for storing document information

=head1 SYNOPSIS

use Document;

my $doc = Document->new->load($record, $lang);

=head1 DESCRIPTION

=head1 METHODS

=head2 Constructor

=over

=item my $doc = $class->new

=item $doc->load($settings, $language);

=back

=head1 AUTHORS

Copyright (c) 2012-2013, TNO. All rights reserved.

=head1 VERSION

1.0


