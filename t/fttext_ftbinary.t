#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Test::MockFile ();

subtest '-T on text file returns true' => sub {
    my $mock = Test::MockFile->file( '/tmp/ft_text', "Hello world\nThis is plain text.\n" );

    ok( -T '/tmp/ft_text',  '-T returns true for text content' );
    ok( !-B '/tmp/ft_text', '-B returns false for text content' );
};

subtest '-B on binary file returns true' => sub {
    my $mock = Test::MockFile->file( '/tmp/ft_bin', "\x00\x01\x02\x03\xFF\xFE" );

    ok( -B '/tmp/ft_bin',  '-B returns true for binary content (NUL bytes)' );
    ok( !-T '/tmp/ft_bin', '-T returns false for binary content (NUL bytes)' );
};

subtest '-T and -B on empty file both return true' => sub {
    my $mock = Test::MockFile->file( '/tmp/ft_empty', '' );

    ok( -T '/tmp/ft_empty', '-T returns true for empty file' );
    ok( -B '/tmp/ft_empty', '-B returns true for empty file' );
};

subtest 'high-bit characters trigger binary detection' => sub {
    # More than 30% high-bit bytes → binary
    my $binary_data = "AB" . ( "\x80" x 8 );    # 2 text + 8 high-bit = 80% odd
    my $mock = Test::MockFile->file( '/tmp/ft_highbit', $binary_data );

    ok( -B '/tmp/ft_highbit',  '-B returns true for high-bit heavy content' );
    ok( !-T '/tmp/ft_highbit', '-T returns false for high-bit heavy content' );
};

subtest 'mostly text with few control chars is still text' => sub {
    # Less than 30% odd chars → text
    my $mostly_text = "Hello world\n" x 10 . "\x01";    # 121 bytes, 1 odd = <1%
    my $mock = Test::MockFile->file( '/tmp/ft_mostly_text', $mostly_text );

    ok( -T '/tmp/ft_mostly_text',  '-T returns true for mostly-text content' );
    ok( !-B '/tmp/ft_mostly_text', '-B returns false for mostly-text content' );
};

subtest '-T and -B on nonexistent mocked file return false' => sub {
    my $mock = Test::MockFile->file('/tmp/ft_noexist');

    ok( !-T '/tmp/ft_noexist', '-T returns false for nonexistent file' );
    ok( !-B '/tmp/ft_noexist', '-B returns false for nonexistent file' );
};

subtest '-T on directory returns false, -B returns true' => sub {
    my $mock = Test::MockFile->new_dir('/tmp/ft_dir');

    ok( !-T '/tmp/ft_dir', '-T returns false for directory' );
    ok( -B '/tmp/ft_dir',  '-B returns true for directory' );
};

subtest '-T and -B fall through for non-mocked files' => sub {
    # $0 is the test script itself — a real text file
    ok( -T $0,  '-T returns true for real text file (this script)' );
    ok( !-B $0, '-B returns false for real text file (this script)' );
};

subtest '-T with tab, newline, carriage return is text' => sub {
    my $content = "col1\tcol2\tcol3\r\ndata1\tdata2\tdata3\r\n";
    my $mock = Test::MockFile->file( '/tmp/ft_whitespace', $content );

    ok( -T '/tmp/ft_whitespace', '-T returns true for content with tabs and CR/LF' );
};

done_testing();
