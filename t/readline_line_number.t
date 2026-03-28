#!/usr/bin/perl -w

# Test that $. (input line number) is correctly updated when reading
# from mocked filehandles. Perl does not auto-increment $. for tied
# handles, so Test::MockFile::FileHandle must set it explicitly.

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;

use Test::MockFile qw< nostrict >;

# Test 1: $. increments with each readline in scalar context
{
    my $mock = Test::MockFile->file( '/tmp/lineno.txt', "line1\nline2\nline3\n" );
    open my $fh, '<', '/tmp/lineno.txt' or die $!;

    my $line = <$fh>;
    is( $., 1, '$. is 1 after first readline' );
    is( $line, "line1\n", 'first line content correct' );

    $line = <$fh>;
    is( $., 2, '$. is 2 after second readline' );

    $line = <$fh>;
    is( $., 3, '$. is 3 after third readline' );

    $line = <$fh>;
    ok( !defined $line, 'undef at EOF' );
    is( $., 3, '$. stays at 3 after EOF' );

    close $fh;
}

# Test 2: $. works in list context (slurp)
{
    my $mock = Test::MockFile->file( '/tmp/slurp.txt', "a\nb\nc\n" );
    open my $fh, '<', '/tmp/slurp.txt' or die $!;

    my @lines = <$fh>;
    is( scalar @lines, 3, 'got 3 lines in list context' );
    is( $., 3, '$. is 3 after reading all lines in list context' );

    close $fh;
}

# Test 3: $. resets for a new handle
{
    my $mock = Test::MockFile->file( '/tmp/reset.txt', "alpha\nbeta\n" );

    open my $fh1, '<', '/tmp/reset.txt' or die $!;
    <$fh1>;
    <$fh1>;
    is( $., 2, '$. is 2 after reading 2 lines from fh1' );

    # Open a second handle to the same file — $. should track per-handle
    open my $fh2, '<', '/tmp/reset.txt' or die $!;
    <$fh2>;
    is( $., 1, '$. is 1 after reading 1 line from fh2' );

    # Reading from fh1 again restores fh1's counter (Perl switches $.
    # to the handle being read, even when returning undef at EOF).
    my $eof = <$fh1>;
    ok( !defined $eof, 'fh1 is at EOF' );
    is( $., 2, '$. switches to fh1 counter (2) even at EOF' );

    close $fh1;
    close $fh2;
}

# Test 4: $. works with while(<$fh>) pattern
{
    my $mock = Test::MockFile->file( '/tmp/while.txt', "x\ny\nz\n" );
    open my $fh, '<', '/tmp/while.txt' or die $!;

    my @seen;
    while ( my $line = <$fh> ) {
        push @seen, $.;
    }
    is( \@seen, [ 1, 2, 3 ], '$. tracks correctly inside while loop' );

    close $fh;
}

# Test 5: $. with custom $/ (record separator)
{
    local $/ = ':';
    my $mock = Test::MockFile->file( '/tmp/sep.txt', "field1:field2:field3:" );
    open my $fh, '<', '/tmp/sep.txt' or die $!;

    <$fh>;
    is( $., 1, '$. is 1 after first record with custom $/' );
    <$fh>;
    is( $., 2, '$. is 2 after second record' );
    <$fh>;
    is( $., 3, '$. is 3 after third record' );

    close $fh;
}

done_testing;
