#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Test::MockFile qw< nostrict >;
use Test::MockFileSys;

note "-------------- MockFileSys: constructor and root --------------";
{
    my $fs = Test::MockFileSys->new;

    ok( $fs, 'MockFileSys constructor returns object' );
    isa_ok( $fs, 'Test::MockFileSys' );

    # Root is mocked as existing directory
    ok( -d '/', 'root / is a directory' );
    ok( -e '/', 'root / exists' );

    # path() on root returns a Test::MockFile object
    my $root = $fs->path('/');
    ok( $root, 'path("/") returns a mock object' );
    isa_ok( $root, 'Test::MockFile' );
}

note "-------------- MockFileSys: singleton enforcement --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { Test::MockFileSys->new },
        qr/already active/,
        'Second MockFileSys while first is alive croaks'
    );
}

note "-------------- MockFileSys: singleton released after scope exit --------------";
{
    {
        my $fs = Test::MockFileSys->new;
        ok( $fs, 'first instance alive' );
    }
    # First instance destroyed — should be able to create a new one
    my $fs2 = Test::MockFileSys->new;
    ok( $fs2, 'second instance created after first went out of scope' );
}

note "-------------- MockFileSys: mkdirs creates tree --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs( '/a/b/c', '/usr/local/bin' );

    ok( -d '/a',             '/a created' );
    ok( -d '/a/b',           '/a/b created' );
    ok( -d '/a/b/c',         '/a/b/c created' );
    ok( -d '/usr',           '/usr created' );
    ok( -d '/usr/local',     '/usr/local created' );
    ok( -d '/usr/local/bin', '/usr/local/bin created' );
}

note "-------------- MockFileSys: mkdirs deduplication --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/a/b');
    $fs->mkdirs('/a/c');    # /a already exists, should not croak

    ok( -d '/a/b', '/a/b from first mkdirs' );
    ok( -d '/a/c', '/a/c from second mkdirs' );
}

note "-------------- MockFileSys: file requires parent dir --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { $fs->file( '/no/parent/file.txt', 'data' ) },
        qr/does not exist/,
        'file() croaks when parent dir missing'
    );
}

note "-------------- MockFileSys: file creation and I/O --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/etc');
    my $mock = $fs->file( '/etc/hosts', "127.0.0.1 localhost\n" );

    ok( $mock, 'file() returns mock object' );
    isa_ok( $mock, 'Test::MockFile' );

    ok( -f '/etc/hosts', '-f on mocked file' );
    ok( -e '/etc/hosts', '-e on mocked file' );

    # Read via Perl I/O
    ok( open( my $fh, '<', '/etc/hosts' ), 'open mocked file for reading' );
    my $content = do { local $/; <$fh> };
    close $fh;
    is( $content, "127.0.0.1 localhost\n", 'file content matches' );
}

note "-------------- MockFileSys: file deduplication --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/tmp');
    my $f1 = $fs->file('/tmp/foo', 'hello');
    my $f2 = $fs->file('/tmp/foo');

    ok( $f1 == $f2, 'file() returns same object for same path (deduplication)' );
}

note "-------------- MockFileSys: non-existent file mock --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/tmp');
    $fs->file('/tmp/ghost');    # no contents = non-existent

    ok( !-e '/tmp/ghost', 'non-existent file mock: -e returns false' );
}

note "-------------- MockFileSys: dir creation --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/a');
    my $d = $fs->dir('/a/subdir');

    ok( $d, 'dir() returns mock object' );
    ok( -d '/a/subdir', '-d on mocked directory' );
}

note "-------------- MockFileSys: dir deduplication --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/etc');
    my $d1 = $fs->dir('/etc');
    my $d2 = $fs->dir('/etc');

    ok( $d1 == $d2, 'dir() returns same object for existing dir' );
}

note "-------------- MockFileSys: symlink creation --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/etc');
    $fs->file( '/etc/hosts', '127.0.0.1 localhost' );
    my $link = $fs->symlink( '/etc/hosts', '/etc/hosts.bak' );

    ok( $link, 'symlink() returns mock object' );
    ok( -l '/etc/hosts.bak', '-l on mocked symlink' );
    is( readlink('/etc/hosts.bak'), '/etc/hosts', 'readlink returns target' );
}

note "-------------- MockFileSys: root cannot be a file --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { $fs->file('/') },
        qr/root must be a directory/,
        'file("/") croaks'
    );
}

note "-------------- MockFileSys: write_file requires content --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/tmp');

    like(
        dies { $fs->write_file( '/tmp/foo', undef ) },
        qr/requires content/,
        'write_file with undef contents croaks'
    );

    my $mock = $fs->write_file( '/tmp/bar', 'data' );
    ok( -f '/tmp/bar', 'write_file creates file' );
}

note "-------------- MockFileSys: overwrite getter/setter --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/tmp');
    $fs->file( '/tmp/data', 'original' );

    # Getter
    is( $fs->overwrite('/tmp/data'), 'original', 'overwrite getter' );

    # Setter
    $fs->overwrite( '/tmp/data', 'modified' );

    ok( open( my $fh, '<', '/tmp/data' ), 'open after overwrite' );
    my $content = do { local $/; <$fh> };
    close $fh;
    is( $content, 'modified', 'overwrite setter changes content' );
}

note "-------------- MockFileSys: overwrite on unmocked path croaks --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { $fs->overwrite('/nonexistent') },
        qr/not mocked/,
        'overwrite on unmocked path croaks'
    );
}

note "-------------- MockFileSys: mkdir convenience method --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/usr');
    $fs->mkdir( '/usr/bin', 0755 );

    ok( -d '/usr/bin', 'mkdir creates directory' );
}

note "-------------- MockFileSys: path returns mock or undef --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/etc');
    $fs->file( '/etc/passwd', 'root:x:0:0' );

    my $mock = $fs->path('/etc/passwd');
    ok( $mock, 'path() returns mock for existing path' );
    isa_ok( $mock, 'Test::MockFile' );

    is( $fs->path('/nowhere'), undef, 'path() returns undef for unknown path' );
}

note "-------------- MockFileSys: unmock removes single path --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/tmp');
    $fs->file( '/tmp/remove-me', 'data' );

    ok( -f '/tmp/remove-me', 'file exists before unmock' );

    $fs->unmock('/tmp/remove-me');

    ok( !$fs->path('/tmp/remove-me'), 'path() returns undef after unmock' );
}

note "-------------- MockFileSys: unmock root croaks --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { $fs->unmock('/') },
        qr/Cannot unmock '\/'/,
        'unmock root croaks'
    );
}

note "-------------- MockFileSys: unmock dir with children croaks --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/a/b');
    $fs->file( '/a/b/c', 'data' );

    like(
        dies { $fs->unmock('/a/b') },
        qr/still has mocked children/,
        'unmock dir with children croaks'
    );
}

note "-------------- MockFileSys: unmock unmocked path croaks --------------";
{
    my $fs = Test::MockFileSys->new;

    like(
        dies { $fs->unmock('/nonexistent') },
        qr/not mocked/,
        'unmock unknown path croaks'
    );
}

note "-------------- MockFileSys: clear resets to empty tree --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs( '/a/b', '/usr' );
    $fs->file( '/a/b/c', 'data' );

    $fs->clear;

    ok( -d '/', 'root still exists after clear' );
    ok( !$fs->path('/a'), '/a gone after clear' );
    ok( !$fs->path('/a/b'), '/a/b gone after clear' );
    ok( !$fs->path('/usr'), '/usr gone after clear' );
}

note "-------------- MockFileSys: clear then reuse --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/old');
    $fs->file( '/old/data', 'old' );

    $fs->clear;

    $fs->mkdirs('/new');
    $fs->file( '/new/data', 'fresh' );

    ok( -f '/new/data', 'new file after clear+reuse' );
    ok( open( my $fh, '<', '/new/data' ), 'read new file after clear' );
    my $content = do { local $/; <$fh> };
    close $fh;
    is( $content, 'fresh', 'content is correct after clear+reuse' );
}

note "-------------- MockFileSys: scope cleanup frees all mocks --------------";
{
    {
        my $fs = Test::MockFileSys->new;
        $fs->mkdirs('/scoped');
        $fs->file( '/scoped/test', 'data' );
    }
    # After scope exit, /scoped should not be in %files_being_mocked
    ok( !$Test::MockFile::files_being_mocked{'/scoped'},      '/scoped cleared after scope exit' );
    ok( !$Test::MockFile::files_being_mocked{'/scoped/test'}, '/scoped/test cleared after scope exit' );
    ok( !$Test::MockFile::files_being_mocked{'/'},            '/ cleared after scope exit' );
}

note "-------------- MockFileSys: conflict with standalone mock --------------";
{
    my $standalone = Test::MockFile->file('/standalone', 'data');

    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/standalone-dir');

    # /standalone was mocked outside — should croak
    like(
        dies { $fs->file('/standalone') },
        qr/already mocked outside/,
        'file() croaks on conflict with standalone mock'
    );

    undef $standalone;
}

note "-------------- MockFileSys: mkdirs through non-directory croaks --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/a');
    $fs->file( '/a/notadir', 'I am a file' );

    like(
        dies { $fs->mkdirs('/a/notadir/sub') },
        qr/non-directory/,
        'mkdirs through a file croaks'
    );
}

done_testing;
