#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use Errno qw/ENOENT EEXIST/;
use Fcntl qw/O_WRONLY O_CREAT/;

use Test::MockFile qw< nostrict >;
use Test::MockFileSys;

note "-------------- MockFileSys: basic construction and singleton --------------";
{
    my $fs = Test::MockFileSys->new;
    ok( $fs, 'MockFileSys->new returns an object' );
    isa_ok( $fs, 'Test::MockFileSys' );

    # Root directory exists
    ok( -d '/', 'root directory exists in MockFileSys' );

    # Singleton enforcement
    like(
        dies { Test::MockFileSys->new },
        qr/already active/,
        'second MockFileSys while first is alive croaks'
    );
}

note "-------------- MockFileSys: singleton released after scope exit --------------";
{
    {
        my $fs = Test::MockFileSys->new;
        ok( $fs, 'created MockFileSys in inner scope' );
    }
    # Should be able to create a new one now
    my $fs2 = Test::MockFileSys->new;
    ok( $fs2, 'can create new MockFileSys after first goes out of scope' );
}

note "-------------- MockFileSys: mkdirs and basic file creation --------------";
{
    my $fs = Test::MockFileSys->new;

    # File creation without parent dir fails
    like(
        dies { $fs->file( '/a/b/c', 'data' ) },
        qr/Parent directory.*does not exist/,
        'file() croaks when parent dir does not exist'
    );

    # mkdirs creates full tree
    $fs->mkdirs('/a/b');
    ok( -d '/a',   '/a exists after mkdirs' );
    ok( -d '/a/b', '/a/b exists after mkdirs' );

    # Now file creation works
    my $mock = $fs->file( '/a/b/c', 'hello' );
    ok( $mock, 'file() returns a mock object' );
    isa_ok( $mock, 'Test::MockFile' );

    # Can read the file via builtins
    ok( open( my $fh, '<', '/a/b/c' ), 'can open file for reading' );
    my $content = do { local $/; <$fh> };
    close $fh;
    is( $content, 'hello', 'file content matches' );
}

note "-------------- MockFileSys: file deduplication --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/x');

    my $mock1 = $fs->file( '/x/f', 'data' );
    my $mock2 = $fs->file('/x/f');
    ok( $mock1 == $mock2, 'file() returns same object for same path (deduplication)' );
}

note "-------------- MockFileSys: dir creation and deduplication --------------";
{
    my $fs = Test::MockFileSys->new;

    my $d1 = $fs->dir('/mydir');
    ok( -d '/mydir', 'dir() creates an existing directory' );

    my $d2 = $fs->dir('/mydir');
    ok( $d1 == $d2, 'dir() returns same object for same path (deduplication)' );

    # dir('/') returns root
    my $root = $fs->dir('/');
    ok( $root, 'dir("/") returns root mock' );
}

note "-------------- MockFileSys: symlink creation --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/links');

    my $mock = $fs->symlink( '/some/target', '/links/mylink' );
    ok( $mock,             'symlink() returns a mock object' );
    ok( -l '/links/mylink', 'symlink is detected by -l' );
    is( readlink('/links/mylink'), '/some/target', 'readlink returns correct target' );
}

note "-------------- MockFileSys: file() croaks at root --------------";
{
    my $fs = Test::MockFileSys->new;
    like(
        dies { $fs->file('/') },
        qr/Cannot create a file at/,
        'file("/") croaks'
    );
}

note "-------------- MockFileSys: mkdirs with multiple paths --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs( '/a/b', '/usr/local/bin', '/etc' );
    ok( -d '/a',              '/a exists' );
    ok( -d '/a/b',            '/a/b exists' );
    ok( -d '/usr',            '/usr exists' );
    ok( -d '/usr/local',      '/usr/local exists' );
    ok( -d '/usr/local/bin',  '/usr/local/bin exists' );
    ok( -d '/etc',            '/etc exists' );
}

note "-------------- MockFileSys: mkdirs idempotency --------------";
{
    my $fs = Test::MockFileSys->new;

    $fs->mkdirs('/a/b');
    $fs->mkdirs('/a/b');    # should not croak
    ok( -d '/a/b', 'mkdirs is idempotent' );
}

note "-------------- MockFileSys: write_file --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/tmp');

    my $mock = $fs->write_file( '/tmp/data', 'content' );
    ok( $mock, 'write_file returns mock' );

    ok( open( my $fh, '<', '/tmp/data' ), 'can read write_file result' );
    my $data = do { local $/; <$fh> };
    close $fh;
    is( $data, 'content', 'write_file content correct' );

    # write_file requires content
    like(
        dies { $fs->write_file( '/tmp/nodata', undef ) },
        qr/requires defined contents/,
        'write_file croaks with undef contents'
    );
}

note "-------------- MockFileSys: overwrite getter/setter --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/d');
    $fs->file( '/d/f', 'original' );

    # Getter
    is( $fs->overwrite('/d/f'), 'original', 'overwrite() getter returns contents' );

    # Setter
    $fs->overwrite( '/d/f', 'updated' );
    ok( open( my $fh, '<', '/d/f' ), 'open after overwrite' );
    my $data = do { local $/; <$fh> };
    close $fh;
    is( $data, 'updated', 'overwrite() setter updates contents' );

    # Overwrite on unmanaged path croaks
    like(
        dies { $fs->overwrite('/nonexistent') },
        qr/not managed/,
        'overwrite on unmanaged path croaks'
    );
}

note "-------------- MockFileSys: path() accessor --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/p');
    my $mock = $fs->file( '/p/q', 'data' );

    my $retrieved = $fs->path('/p/q');
    ok( $retrieved == $mock, 'path() returns the correct mock object' );

    ok( !defined $fs->path('/nonexistent'), 'path() returns undef for unmanaged path' );
}

note "-------------- MockFileSys: unmock --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/u');
    $fs->file( '/u/f', 'data' );

    ok( -e '/u/f', 'file exists before unmock' );
    $fs->unmock('/u/f');
    ok( !-e '/u/f', 'file gone after unmock' );

    # unmock on root croaks
    like(
        dies { $fs->unmock('/') },
        qr/Cannot unmock/,
        'unmock("/") croaks'
    );

    # unmock on unmanaged path croaks
    like(
        dies { $fs->unmock('/nonexistent') },
        qr/not managed/,
        'unmock on unmanaged path croaks'
    );
}

note "-------------- MockFileSys: unmock with children croaks --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/parent/child');
    $fs->file( '/parent/child/file', 'data' );

    like(
        dies { $fs->unmock('/parent') },
        qr/still has mocked children/,
        'unmock on parent with children croaks'
    );
}

note "-------------- MockFileSys: clear resets everything --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/a/b');
    $fs->file( '/a/b/c', 'data' );

    ok( -e '/a/b/c', 'file exists before clear' );
    $fs->clear;
    ok( !-e '/a/b/c', 'file gone after clear' );
    ok( !-e '/a/b',   'dir gone after clear' );
    ok( !-e '/a',     'parent dir gone after clear' );
    ok( -d '/',       'root still exists after clear' );

    # Can re-use after clear
    $fs->mkdirs('/new');
    $fs->file( '/new/file', 'fresh' );
    ok( -e '/new/file', 'can create files after clear' );
}

note "-------------- MockFileSys: mkdir builtin with strict fs mode --------------";
{
    my $fs = Test::MockFileSys->new;

    # mkdir on empty fs: parent / exists, so single-level mkdir works
    ok( mkdir('/topdir'), 'mkdir "/topdir" succeeds (parent / exists)' );
    ok( -d '/topdir', '/topdir is a directory' );

    # Nested mkdir without parents fails
    ok( !mkdir('/topdir/a/b'), 'mkdir "/topdir/a/b" fails (parent /topdir/a missing)' );
    is( $! + 0, ENOENT, 'errno is ENOENT for failed mkdir' );

    # Create the intermediate, then nested works
    ok( mkdir('/topdir/a'), 'mkdir "/topdir/a" succeeds' );
    ok( mkdir('/topdir/a/b'), 'mkdir "/topdir/a/b" succeeds after parent created' );
}

note "-------------- MockFileSys: open for write fails without parent dir --------------";
{
    my $fs = Test::MockFileSys->new;

    # Write to file with no parent dir should fail
    ok( !open( my $fh, '>', '/no/such/file' ), 'open ">" fails without parent dir' );
    is( $! + 0, ENOENT, 'errno is ENOENT' );

    # Create parent, then write succeeds
    $fs->mkdirs('/no/such');
    ok( open( my $fh2, '>', '/no/such/file' ), 'open ">" succeeds after mkdirs' );
    print $fh2 'test data';
    close $fh2;

    ok( open( my $rfh, '<', '/no/such/file' ), 'can read back written file' );
    my $data = do { local $/; <$rfh> };
    close $rfh;
    is( $data, 'test data', 'file content is correct' );
}

note "-------------- MockFileSys: sysopen with O_CREAT fails without parent dir --------------";
{
    my $fs = Test::MockFileSys->new;

    ok( !sysopen( my $fh, '/no/parent/file', O_WRONLY | O_CREAT ),
        'sysopen O_CREAT fails without parent dir' );
    is( $! + 0, ENOENT, 'errno is ENOENT for sysopen' );
}

note "-------------- MockFileSys: readdir shows created files --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/rd');
    $fs->file( '/rd/alpha', 'a' );
    $fs->file( '/rd/beta',  'b' );

    ok( opendir( my $dh, '/rd' ), 'opendir on managed dir' );
    my @entries = sort readdir($dh);
    closedir $dh;

    is( \@entries, [qw/. .. alpha beta/], 'readdir returns correct entries' );
}

note "-------------- MockFileSys: readdir after builtin open creates file --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/dynamic');

    ok( open( my $fh, '>', '/dynamic/newfile' ), 'create file via open' );
    print $fh 'content';
    close $fh;

    ok( opendir( my $dh, '/dynamic' ), 'opendir after file creation' );
    my @entries = sort readdir($dh);
    closedir $dh;

    is( \@entries, [qw/. .. newfile/], 'readdir shows dynamically created file' );
}

note "-------------- MockFileSys: cleanup on scope exit --------------";
{
    {
        my $fs = Test::MockFileSys->new;
        $fs->mkdirs('/scoped/dir');
        $fs->file( '/scoped/dir/file', 'data' );
        ok( -e '/scoped/dir/file', 'file exists in scope' );
    }

    # After scope exit, mocks should be gone
    # In nostrict mode, stat falls through to real FS
    ok( !-e '/scoped/dir/file', 'file cleaned up after scope exit' );
}

note "-------------- MockFileSys: no leftover state after DESTROY --------------";
{
    {
        my $fs = Test::MockFileSys->new;
        $fs->mkdirs('/cleanup/test');
        $fs->file( '/cleanup/test/f', 'x' );
    }

    # Verify global state is clean
    ok( !exists $Test::MockFile::files_being_mocked{'/'},
        'root mock removed from files_being_mocked' );
    ok( !exists $Test::MockFile::files_being_mocked{'/cleanup'},
        '/cleanup removed from files_being_mocked' );
    ok( !exists $Test::MockFile::files_being_mocked{'/cleanup/test'},
        '/cleanup/test removed from files_being_mocked' );
    ok( !exists $Test::MockFile::files_being_mocked{'/cleanup/test/f'},
        '/cleanup/test/f removed from files_being_mocked' );

    # Verify strict_fs_mode is off
    is( $Test::MockFile::_strict_fs_mode, 0, '_strict_fs_mode cleared after DESTROY' );
}

note "-------------- MockFileSys: conflicting external mock detection --------------";
{
    my $external = Test::MockFile->file( '/ext/file', 'ext' );
    my $ext_dir  = Test::MockFile->dir('/ext');

    my $fs = Test::MockFileSys->new;
    like(
        dies { $fs->file( '/ext/file', 'conflict' ) },
        qr/already mocked outside/,
        'file() croaks when path is externally mocked'
    );
}

note "-------------- MockFileSys: mkdir helper method --------------";
{
    my $fs = Test::MockFileSys->new;
    my $mock = $fs->mkdir( '/mdir', 0755 );
    ok( -d '/mdir', 'mkdir() creates directory' );
    ok( $mock, 'mkdir() returns mock' );
}

note "-------------- MockFileSys: unlink on dynamically created file --------------";
{
    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/ul');

    ok( open( my $fh, '>', '/ul/temp' ), 'create file' );
    print $fh 'data';
    close $fh;

    ok( -e '/ul/temp', 'file exists before unlink' );
    ok( unlink('/ul/temp'), 'unlink succeeds' );
    ok( !-e '/ul/temp', 'file gone after unlink' );
}

done_testing();
