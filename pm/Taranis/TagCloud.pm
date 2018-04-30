# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::TagCloud;

use Taranis::Config;
use Taranis qw(:all);
use Tie::IxHash;
use HTML::Entities qw(decode_entities);
use strict;

sub new {
	my $class = shift;

	my $blFile = Taranis::Config->getSetting('tagcloud_blacklist');
	my $blText = fileToString(find_config $blFile);
	
	my $self = {
		blacklist => $blText,
		minimumTagLength => 4
	};
	return( bless( $self, $class ) );
}

sub createTagsListFromText {
	my ( $self, %args ) = @_;
	my ( @tags );
	tie my %list, "Tie::IxHash";
	my $text = decode_entities( $args{text} );

	foreach my $tag ( split /\s/, $text ) {

		$tag=~ tr/*//d;
		$tag=~ tr/(//d;
		$tag=~ tr/)//d;
		$tag=~ tr/""//d;
		$tag=~ tr/''//d;
		$tag=~ tr/?//d;
		$tag=~ tr/,//d;
		$tag=~ tr/. //d;
		$tag=~ tr/-//d;
		$tag=~ tr/"//d;
		$tag=~ tr/'//d;
		$tag=~ tr/‘//d;
		$tag=~ tr/!//d;
		$tag=~ tr/;//d;
		$tag= lc( $tag );
		$tag=~ s/\[//gi;
		$tag=~ s/\]//gi;
		$tag=~ s/://gi;
		$tag=~ s/#//gi;
		$tag=~ s/\&rsquos//gi;

		$tag= '' unless defined $tag;


		if ( trim $tag ) {
			push @tags, trim $tag;
		}
	}

	my %seen = ();
	my @uniq = ();
	foreach my $uniqTag( @tags )	{
		unless ( $seen{ $uniqTag } ) {
			# if we get here, we have not seen it before
			$seen{ $uniqTag } = 1;
			push @uniq, $uniqTag;
		}
	}

	my %count;
	$count{$_}++ for @tags; # Here are the counts
	
	$list{$_} = $count{$_}  for (sort { $count{$b} <=> $count{$a} } keys %count);
	
	return \%list;
}

sub isBlacklisted {
	my ( $self, $tag ) = @_;

	# tag is too short
	if ( length( $tag ) <= $self->{minimumTagLength} ) {
		return 1;
	}
	
	# tag is in blacklist file
	if ( $self->{blacklist} =~ /\n\Q$tag\E\n/gi ) {
		return 1;
	}

	# tag is url
	if ( substr ($tag, 0, 4) eq "http" ) {
		return 1;
	}

	# tag starts with @
	if (substr ($tag, 0, 1) eq "@") {
		return 1;
	}

	# tag contains &
	if (index ($tag, "&") > -1) {
		return 1;
	}

	return 0;
}

sub resizeList {
	my ( $self, %args) = @_;

	my $level = $args{level} || undef;
	my $maximumUniqWords = $args{maximumUniqWords} || undef;
	my $list = $args{list};

	my %levels;
		
	foreach my $tag ( keys %$list ) {
		
		if ( defined $maximumUniqWords && $maximumUniqWords == 0 ) {
			delete $list->{$tag};
		} else {
			$maximumUniqWords--;
		}
		
		if ( exists( $list->{$tag} ) ) {
			if ( defined $level && $level == 0 ) {
				delete $list->{$tag};
			} else {
				if ( !exists( $levels{ $list->{$tag} } ) ) {
					$levels{ $list->{$tag} } = 1;
					$level--;
				}
			}
		}
	}
	
	return $list;
}

sub sortList {
	my ( $self, $list ) = @_;
	tie my %sortedList, 'Tie::IxHash';
	$sortedList{$_} = $list->{$_}  for ( reverse sort { $list->{$a} <=> $list->{$b} } keys %$list);
	return  \%sortedList;
}

1;

=head1 NAME

Taranis::TagCloud

=head1 SYNOPSIS

  use Taranis::TagCloud;

  my $obj = Taranis::TagCloud->new();

  $obj->createTagsListFromText( text => $text );

  $obj->isBlacklisted( $tag );

  $obj->resizeList( list => \%sortedList, maximumUniqWords => $maximumUniqWords, level => $level );

  $obj->sortList( \%unsortedList );

=head1 DESCRIPTION

Facilitates in creating a list of words with word count from a text.

=head1 METHODS

=head2 new()

Constructor of the C<Taranis::TagCloud> module.

    my $obj = Taranis::TagCloud->new();

Sets the file path of the blacklist file:

    $obj->{blacklist};

Sets the minimum characterlength for tags:

    $obj->{minimumTagLength};

Returns the blessed object.

=head2 createTagsListFromText( text => $text )

Creates a list of tags and count values from C<$text>.

    $obj->createTagsListFromText( text => 'some long text with many more words...' );

Returns an HASH reference with keys being the tags and values being the tagcount.

=head2 isBlacklisted( $tag )

Checks if C<$tag> is allowed as tag. Checks tag against a blacklist, minimum character length, if tag starts with 'http' or '@' and if it contains the character '&'.

    $obj->isBlacklisted( 'NCSC' );

Returns TRUE or FALSE.

=head2 resizeList( list => \%sortedList, maximumUniqWords => $maximumUniqWords, level => $level )

Resizes a list of tags using parameters C<maximumUniqWords> and C<level>.
The C<$sortedList> can be obtained using sortList(). 

    $obj->resizeList( list => \%sortedList, maximumUniqWords => 20, level => 20 );

Returns an HASH reference.

=head2 sortList( \%unsortedList )

Sorts a taglist by the tagcount.

    $obj->sortList( \%unsortedList );
    
Returns an HASH reference.

=cut
