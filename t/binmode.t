#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Test::MockFile ();

subtest 'binmode returns true on mocked filehandle' => sub {
    my $mock = Test::MockFile->file( '/tmp/binmode_test', "hello world" );

    open my $fh, '<', '/tmp/binmode_test' or die "open: $!";
    my $ret = binmode($fh);
    ok( $ret, 'binmode() returns a true value on mocked filehandle' );
    close $fh;
};

subtest 'binmode with encoding layer returns true' => sub {
    my $mock = Test::MockFile->file( '/tmp/binmode_enc', "hello world" );

    open my $fh, '<', '/tmp/binmode_enc' or die "open: $!";
    my $ret = binmode( $fh, ':utf8' );
    ok( $ret, 'binmode($fh, ":utf8") returns a true value on mocked filehandle' );
    close $fh;
};

subtest 'binmode or die pattern works' => sub {
    my $mock = Test::MockFile->file( '/tmp/binmode_die', "content" );

    open my $fh, '<', '/tmp/binmode_die' or die "open: $!";
    my $lived = eval {
        binmode($fh) or die "binmode failed: $!";
        1;
    };
    ok( $lived, 'binmode($fh) or die does not die on mocked filehandle' );
    close $fh;
};

done_testing();
