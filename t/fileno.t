#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;
use Test2::Tools::Exception qw< lives dies >;
use Test::MockFile qw< strict >;

my $file = Test::MockFile->file( '/foo', '' );

my $fh;
ok( lives( sub { open $fh, '<', '/foo' } ), 'Opened file' );

# fileno should return a value for mocked file handles
ok( defined fileno($fh), 'fileno returns a defined value for a mocked fh' );

ok( lives( sub { close $fh } ), 'Closed file' );

# Each open() should get a unique fileno, even on the same mocked file.
# This mirrors real behavior where fileno is a property of open(), not the file.
subtest 'unique fileno per open filehandle' => sub {
    my $mock_a = Test::MockFile->file( '/unique_a', 'aaa' );
    my $mock_b = Test::MockFile->file( '/unique_b', 'bbb' );

    open my $fh_a, '<', '/unique_a' or die;
    open my $fh_b, '<', '/unique_b' or die;
    open my $fh_a2, '<', '/unique_a' or die;    # second open of same file

    my @filenos = map { fileno($_) } ( $fh_a, $fh_b, $fh_a2 );

    # All three should be defined
    ok( defined $filenos[0], 'fileno for fh_a is defined' );
    ok( defined $filenos[1], 'fileno for fh_b is defined' );
    ok( defined $filenos[2], 'fileno for fh_a2 is defined' );

    # All three should be distinct (even the two opens of /unique_a)
    isnt( $filenos[0], $filenos[1], 'fh_a and fh_b have different filenos' );
    isnt( $filenos[0], $filenos[2], 'fh_a and fh_a2 have different filenos' );
    isnt( $filenos[1], $filenos[2], 'fh_b and fh_a2 have different filenos' );

    close $fh_a;
    close $fh_b;
    close $fh_a2;
};

done_testing();
exit;
