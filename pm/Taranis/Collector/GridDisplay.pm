# This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

package Taranis::Collector::GridDisplay;

## Taranis::Collector::GridDisplay: render a status "grid" to the user's terminal.
#
# Used in collector/collector.pl, when called with the --grid option, to show what the various collector threads are
# doing.
#
# Every GRID_DRAW_INTERVAL seconds, a line of the "grid" is drawn. The grid is composed of X columns, each with their
# own status. If a column's status has changed since the previous line was drawn, its new status is displayed. If a
# column's status is unchanged, '.' (a dot) is printed. If a column has no status, i.e. its status text is false (empty
# string / undef), nothing is printed for that column.
#
#
# Synopsis:
#
# use Taranis::Collector::GridDisplay qw(startGrid stopGrid setGridColumnText);
#
# # Initiate grid with 5 columns.
# startGrid(5);
#
# # Set status text of column 0 to the string "hi there".
# setGridColumnText(0, "hi there");
# sleep GRID_DRAW_INTERVAL * 2;
#
# # Set status text of columns 1-3 to "active-column-<num>" (which may not fit, in which case it'll be truncated).
# setGridColumnText($_, "active-column-$_") for 1 .. 3;
# sleep GRID_DRAW_INTERVAL * 3;
#
# setGridColumnText(2, "foo");
# setGridColumnText(2, "bar"); # Overrides "foo" from the line before, rendering it useless, since GRID_DRAW_INTERVAL time hasn't passed.
# setGridColumnText(3, '');    # '' being a false value, this means "nothing" (don't even draw dots)
# sleep GRID_DRAW_INTERVAL * 2;
#
# stopGrid;
#
#
# The above will output something like this:
#
# +-------------------------------------------------------------+
# | #0          #1          #2          #3          #4          |
# | hi there                                                    |
# | .                                                           |
# | .           active-colu active-colu active-column-3         |
# | .           .           .           .                       |
# | .           .           .           .                       |
# | .           .           bar                                 |
# | .           .           .                                   |
# +-------------------------------------------------------------+
#
# Observe that columns 1-3 are initially blank, and column 4 stays blank, because they have no status text.


use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use threads;
use threads::shared;
use Term::ReadKey qw(GetTerminalSize);
use Term::ANSIColor qw(colored);
use Time::HiRes qw(usleep);


our @ISA = qw(Exporter);
our @EXPORT_OK = qw(startGrid stopGrid setGridColumnText);

use constant {
	# How much space (in characters) to reserve for the rightmost column.
	GRID_LAST_COLUMN_WIDTH => 20,

	# How long (in seconds) to sleep between grid draw iterations.
	GRID_DRAW_INTERVAL => .2,
};

# (columnNumber => text) mappings. Updated by (the exported) setGridColumnText, which must be thread-safe.
our %gridColumnText :shared;

# The threadid of the displayLoop thread.
our $displayThreadId :shared;

# Set to a true value to signal the displayLoop that it should exit.
our $stopSignal :shared;

# Launch displayLoop thread.
sub startGrid {
	my ($numColumns) = @_;
	$displayThreadId = (
		async { displayLoop($numColumns) }
	)->tid;
}

# Stop displayLoop thread.
sub stopGrid {
	$stopSignal = 1;
	threads->object($displayThreadId)->join();
	undef $displayThreadId;
	undef $stopSignal;
}

# Column 0 is the left-most column.
sub setGridColumnText {
	my ($column, $text) = @_;
	$gridColumnText{$column} = $text;
}

# Render text $title for column $column on the current(!) line of the output. Requires an ANSI-friendly TTY.
sub drawGridColumnText {
	my ($column, $title, $gridColumnWidth) = @_;
	moveCursorToX(int($column * $gridColumnWidth));
	print colored(
		substr($title, 0, GRID_LAST_COLUMN_WIDTH) . ' ',
		colorForColumn($column)
	);
}

sub displayLoop {
	my ($numColumns) = @_;
	my %prevText;

	say '';
	say "Collection threads:";
	drawGridColumnText($_, "#$_", gridColumnWidth($numColumns)) for 0 .. $numColumns - 1;
	say '';

	while (!$stopSignal) {
		my $gridColumnWidth = gridColumnWidth($numColumns);
		# %gridColumnText is shared with (and modified by) other threads, so use a local copy.
		my %currentText = %gridColumnText;

		# Draw unchanged-but-non-empty columns as dots. Do this first, before drawing the column texts, so that the
		# unimportant dots get overwritten if necessary by the more important texts.
		drawGridColumnText($_, '.', $gridColumnWidth) for grep {
			$currentText{$_} and $currentText{$_} eq $prevText{$_}
		} keys %currentText;

		# Draw texts that have changed. Work left-to-right so that columns' texts do not overwrite other columns' texts
		# when they overflow the column width.
		drawGridColumnText($_, $currentText{$_}, $gridColumnWidth) for grep {
			$currentText{$_} ne $prevText{$_}
		} sort {$a <=> $b} keys %currentText;

		%prevText = %currentText;
		print "\n";
		usleep 1_000_000 * GRID_DRAW_INTERVAL;
	}
}

# Move terminal cursor to position $xPosition of the current line (0 = leftmost position).
sub moveCursorToX {
	my ($xPosition) = @_;

	# Carriage return (move cursor to beginning of current line, i.e. X-position 0).
	print "\r";
	# ANSI escape sequence to move cursor $xPosition to the right.
	printf "\033[%dC", $xPosition if $xPosition > 0;
}

# Which color should column number $column have?
sub colorForColumn {
	my ($column) = @_;
	my @niceAnsiColors = qw(red green yellow blue magenta cyan white);

	# Bright colors look nicer, but require a relatively new Term::ANSIColor.
	@niceAnsiColors = map { "bright_$_" } @niceAnsiColors if $Term::ANSIColor::VERSION >= 3;

	# Pick an arbitrary color.
	return $niceAnsiColors[$column % scalar @niceAnsiColors];
}


# Returns the width (in characters) that's available for each thread in the display. This is not necessarily an
# integer; it may well be 1.7 or 23.3333. Callers are expected to deal with that.
sub gridColumnWidth {
	my $numColumns = shift;

	state $terminalWidth = 72;  # Conservative default in case we can't determine the terminal width.

	# Try to refresh terminal width. Do this every time we're called as an easy way to automatically adjust when the
	# terminal size changes. Quite inefficient, but GetTerminalSize is so fast compared to all the other stuff we're
	# doing that that doesn't really matter.
	# GetTerminalSize fails intermittently (throwing an exception) on some terminals. In that case, nevermind
	# refreshing the terminal width and just continue on; we'll get it next time.
	eval {
		($terminalWidth) = GetTerminalSize();
	};

	# Reserve GRID_LAST_COLUMN_WIDTH characters for the rightmost column (since it can't overflow into other columns,
	# but should still fit most source names); divide the rest over the other columns.
	if ($numColumns <= 1) {
		return $terminalWidth - GRID_LAST_COLUMN_WIDTH - 1;
	} else {
		return ($terminalWidth - GRID_LAST_COLUMN_WIDTH - 1) / ($numColumns - 1);
	}
}

1;
