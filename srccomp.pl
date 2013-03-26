#!/usr/bin/perl

use strict;
use warnings;
use SuffixTree;
use Compress::Zlib;

sub gettokens($)
{
	my ($source) = @_;

	# strip // comments (tokenizer can't handle them)
	$source =~ s!//.*! !gm;

	# detect strings
	$source =~ s!".*?[^"\\](?:\\\\)*"!"string"!g;

	# word split
	my $tokens = "";
	while($source =~ m!([0-9][Xx]?[0-9A-Fa-f.+-]*)|(if|while|do|for|void|return|break|continue)|(\w+(?:(?:->|\.)\w+)*)|(\S)!g)
	{
		$tokens .=
			defined $1 ? '0' :
			defined $2 ? substr($2, 0, 1) :
			defined $3 ? 'X' :
			$4;
	}
	$tokens =~ s!/\*.*?\*/!!g;
	$tokens =~ s!"X"!S!g;
	$tokens =~ s!""!s!g;

	$tokens =~ s!
		X
		(
			\(
				(
					(?:
						(?> [^()]+ )
						|
						(?1)
					)*
				)
			\)
		)
	!F!gx;

	return $tokens;
}

sub indexlist($$)
{
	my ($s, $sub) = @_;
	my @l = ();
	my $i = 0;
	while(($i = index $s, $sub, $i) >= 0)
	{
		push @l, $i;
		++$i;
	}
	return @l;
}

my $z = 0;
my %worthcache;
sub worth($)
{
	my ($s) = @_;
	return length $s if $z == 0;
	my $c = $worthcache{$s};
	return $c if defined $c;
	return $worthcache{$s} = length compress $s, 1;
}

sub findsubseq_tree($$$$);
sub findsubseq_tree($$$$)
{
	my ($s, $tree, $tlen, $n) = @_;

	return () if $s eq "";
	return () if $n <= 0;

	my $best = 0;
	my $bestlen = 0;
	my $beststr = "";
	my $beststart_s = 0;
	my $beststart_t = 0;
	for my $start(0..(length $s)-1)
	{
		for my $len(1..(length $s)-$start)
		{
			my $sub = substr $s, $start, $len;
			my $i = find_substring $tree, $sub;
			$i -= 1;
			last if $i >= $tlen;
			last if $i < 0;
			my $worth = worth $sub;
			next if $worth <= $best;
			$best = $worth;
			$bestlen = $len;
			$beststr = $sub;
			$beststart_s = $start;
			$beststart_t = $i;
		}
	}

	return () if $best == 0;

	my @ret = ([$beststart_s, $beststart_t, $bestlen, $best]);

	my $pre = substr $s, 0, $beststart_s;
	my $post = substr $s, $beststart_s + $bestlen;

	push @ret,                                                                        findsubseq_tree $pre, $tree, $tlen, $n - 1;
	push @ret, map { [$_->[0] + $beststart_s + $bestlen, $_->[1], $_->[2], $_->[3]] } findsubseq_tree $post, $tree, $tlen, $n - 1;

	@ret = sort { $b->[3] <=> $a->[3] } @ret;
	@ret = @ret[0..$n-1] if @ret > $n;

	return @ret;
}

sub findsubseq($$$)
{
	my ($s, $t, $n) = @_;

	my $tree = create_tree $t;
	my @ret = findsubseq_tree($s, $tree, length($t), $n);
	delete_tree $tree;
	return @ret;
}

my $i = 0;
my @src = ({}, {});
for(@ARGV)
{
	if($_ =~ /-([0-9])/)
	{
		$z = $1;
		next;
	}
	if($_ eq '--')
	{
		$i = 1;
		next;
	}
	print STDERR "$_\n";
	open my $fh, '<', $_;
	my $src = do { undef local $/; <$fh>; };
	close $fh;
	$src[$i]{$_} = gettokens $src;
}

# find longest common subsequence
my ($a, $b) = @src;
while(my ($afile, $atext) = each %$a)
{
	while(my ($bfile, $btext) = each %$b)
	{
		my @matches = findsubseq $atext, $btext, 16;
		print STDERR "$afile vs $bfile\n";
		print "Best matches for $afile -- $bfile are:\n";
		for(@matches)
		{
			my ($astart, $bstart, $len, $worth) = @$_;
			my $str = substr $atext, $astart, $len;
			printf "  A=%05.2f%% B=%05.2f%% l=%d w=%d %s\n", $astart * 100.0 / length $atext, $bstart * 100.0 / length $btext, $len, $worth, $str;
		}
	}
}
