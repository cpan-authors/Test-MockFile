#!/usr/bin/perl -w

# Test Unix semantics: unlink on a file with open handles should not
# affect reads through those handles. The directory entry is removed
# (-e returns false), but open filehandles continue to see the data.

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;

use Test::MockFile qw< nostrict >;

# Test 1: Read after unlink — handle should still see the original data
{
    my $mock = Test::MockFile->file( "/tmp/unlink_read", "important data" );

    open my $fh, '<', '/tmp/unlink_read' or die "open: $!";

    # Unlink while handle is open
    ok( unlink('/tmp/unlink_read'), "unlink succeeds on open file" );
    ok( !-e '/tmp/unlink_read',    "file no longer exists after unlink" );

    # The open handle should still be able to read the data
    my $content = do { local $/; <$fh> };
    is( $content, "important data", "read through open handle returns original data after unlink" );

    close $fh;
}

# Test 2: eof() should not warn after unlink
{
    my $mock = Test::MockFile->file( "/tmp/unlink_eof", "data" );

    open my $fh, '<', '/tmp/unlink_eof' or die "open: $!";

    # Read to end
    my $content = do { local $/; <$fh> };

    unlink('/tmp/unlink_eof');

    # eof() on the open handle should not produce warnings
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    my $is_eof = eof($fh);
    is( \@warnings, [], "no warnings from eof() after unlink" );
    ok( $is_eof, "eof is true after reading all data" );

    close $fh;
}

# Test 3: Multiple handles — all should retain access
{
    my $mock = Test::MockFile->file( "/tmp/unlink_multi", "shared data" );

    open my $fh1, '<', '/tmp/unlink_multi' or die "open fh1: $!";
    open my $fh2, '<', '/tmp/unlink_multi' or die "open fh2: $!";

    unlink('/tmp/unlink_multi');

    my $c1 = do { local $/; <$fh1> };
    my $c2 = do { local $/; <$fh2> };

    is( $c1, "shared data", "first handle reads data after unlink" );
    is( $c2, "shared data", "second handle reads data after unlink" );

    close $fh1;
    close $fh2;
}

# Test 4: Write handle still works after unlink
{
    my $mock = Test::MockFile->file( "/tmp/unlink_write", "" );

    open my $fh, '+>', '/tmp/unlink_write' or die "open: $!";
    print $fh "before";

    unlink('/tmp/unlink_write');

    # Writing to the handle after unlink should still work
    print $fh " after";
    seek( $fh, 0, 0 );
    my $content = do { local $/; <$fh> };
    is( $content, "before after", "write and read through handle work after unlink" );

    close $fh;
}

# Test 5: sysread after unlink
{
    my $mock = Test::MockFile->file( "/tmp/unlink_sysread", "sysread data" );

    open my $fh, '<', '/tmp/unlink_sysread' or die "open: $!";
    unlink('/tmp/unlink_sysread');

    my $buf;
    my $n = sysread( $fh, $buf, 1024 );
    is( $n,    12,             "sysread returns correct byte count after unlink" );
    is( $buf, "sysread data", "sysread returns correct data after unlink" );

    close $fh;
}

# Test 6: getc after unlink
{
    my $mock = Test::MockFile->file( "/tmp/unlink_getc", "AB" );

    open my $fh, '<', '/tmp/unlink_getc' or die "open: $!";
    unlink('/tmp/unlink_getc');

    is( getc($fh), "A", "getc returns first char after unlink" );
    is( getc($fh), "B", "getc returns second char after unlink" );

    close $fh;
}

done_testing;
