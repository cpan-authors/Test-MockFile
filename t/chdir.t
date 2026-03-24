#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Errno qw/ENOENT ENOTDIR/;
use Cwd ();

use Test::MockFile qw< nostrict >;

my $real_cwd = Cwd::getcwd();

subtest "chdir to mocked directory" => sub {
    my $mock_dir = Test::MockFile->new_dir("/tmp/mock_chdir_test");

    ok( -d "/tmp/mock_chdir_test", "Mock dir exists via -d" );

    $! = 0;
    is( chdir("/tmp/mock_chdir_test"), 1, "chdir to mocked dir succeeds" );
    is( $! + 0, 0, ' - $! is unset' );

    is( Cwd::getcwd(),  "/tmp/mock_chdir_test", "Cwd::getcwd returns virtual cwd" );
    is( Cwd::cwd(),     "/tmp/mock_chdir_test", "Cwd::cwd returns virtual cwd" );
    is( Cwd::fastcwd(), "/tmp/mock_chdir_test", "Cwd::fastcwd returns virtual cwd" );

    # Restore real cwd
    CORE::chdir($real_cwd);
};

subtest "chdir to non-existent mocked dir fails" => sub {
    my $mock_dir = Test::MockFile->dir("/tmp/mock_chdir_noexist");

    ok( !-d "/tmp/mock_chdir_noexist", "Mock dir does not exist" );

    $! = 0;
    is( chdir("/tmp/mock_chdir_noexist"), 0, "chdir to non-existent mock fails" );
    is( $! + 0, ENOENT, " - \$! is ENOENT" );
};

subtest "chdir to mocked file fails with ENOTDIR" => sub {
    my $mock_file = Test::MockFile->file("/tmp/mock_chdir_file", "content");

    $! = 0;
    is( chdir("/tmp/mock_chdir_file"), 0, "chdir to file fails" );
    is( $! + 0, ENOTDIR, ' - $! is ENOTDIR' );
};

subtest "relative path resolution uses virtual cwd" => sub {
    my $mock_dir  = Test::MockFile->new_dir("/tmp/mock_cwd_parent");
    my $mock_file = Test::MockFile->file("/tmp/mock_cwd_parent/hello.txt", "world");

    chdir("/tmp/mock_cwd_parent");
    is( Cwd::getcwd(), "/tmp/mock_cwd_parent", "Virtual cwd is set" );

    # Open a file with a relative path — should resolve against virtual cwd
    open( my $fh, '<', 'hello.txt' ) or die "open failed: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    is( $content, "world", "Relative open resolves against virtual cwd" );

    # Restore real cwd
    CORE::chdir($real_cwd);
};

subtest "chdir with no args uses HOME" => sub {
    local $ENV{HOME} = "/tmp/mock_chdir_home";
    my $mock_dir = Test::MockFile->new_dir("/tmp/mock_chdir_home");

    is( chdir(), 1, "chdir() with no args uses HOME" );
    is( Cwd::getcwd(), "/tmp/mock_chdir_home", "Virtual cwd set to HOME" );

    CORE::chdir($real_cwd);
};

subtest "real chdir clears virtual cwd" => sub {
    my $mock_dir = Test::MockFile->new_dir("/tmp/mock_chdir_clear");

    chdir("/tmp/mock_chdir_clear");
    is( Cwd::getcwd(), "/tmp/mock_chdir_clear", "Virtual cwd is set" );

    # Real chdir to actual directory should clear virtual cwd
    CORE::chdir($real_cwd);
    chdir($real_cwd);
    is( Cwd::getcwd(), $real_cwd, "Real chdir clears virtual cwd" );
};

subtest "mock destruction clears virtual cwd" => sub {
    {
        my $mock_dir = Test::MockFile->new_dir("/tmp/mock_chdir_destroy");
        chdir("/tmp/mock_chdir_destroy");
        is( Cwd::getcwd(), "/tmp/mock_chdir_destroy", "Virtual cwd is set" );
    }

    # Mock went out of scope — virtual cwd should be cleared
    isnt( Cwd::getcwd(), "/tmp/mock_chdir_destroy", "Virtual cwd cleared on mock destruction" );
};

subtest "chdir to unmocked path falls through" => sub {
    # chdir to a real directory should work normally
    $! = 0;
    my $result = chdir($real_cwd);
    is( $result, 1, "chdir to real directory succeeds" );
    is( $! + 0, 0, ' - $! is unset' );
    is( Cwd::getcwd(), $real_cwd, "Real getcwd after real chdir" );
};

subtest "stat -d after chdir to mocked dir" => sub {
    my $mock_dir  = Test::MockFile->new_dir("/tmp/mock_chdir_stat");
    my $mock_sub  = Test::MockFile->new_dir("/tmp/mock_chdir_stat/sub");

    chdir("/tmp/mock_chdir_stat");

    ok( -d "sub", "-d on relative path works after chdir to mocked dir" );

    CORE::chdir($real_cwd);
};

done_testing();
