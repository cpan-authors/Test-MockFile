# Copyright (c) 2018, cPanel, LLC.
# All rights reserved.
# http://cpanel.net
#
# This is free software; you can redistribute it and/or modify it under the
# same terms as Perl itself. See L<perlartistic>.

package Test::MockFileSys;

use strict;
use warnings;

use Carp qw(carp confess croak);
use Scalar::Util ();
use File::Basename ();

# We need Test::MockFile loaded for its internals.
# Import nothing — we just need the class and its package variables.
use Test::MockFile ();

our $VERSION = '0.001';

# Singleton tracking — only one MockFileSys alive at a time.
my $_active_instance;

=head1 NAME

Test::MockFileSys - Virtual filesystem container for Test::MockFile

=head1 SYNOPSIS

    use Test::MockFile;    # strict mode by default
    use Test::MockFileSys;

    {
        my $fs = Test::MockFileSys->new;

        # Set up directory structure (like mkdir -p)
        $fs->mkdirs( '/usr/local/bin', '/etc', '/tmp' );

        # Create files (parent dir must exist)
        $fs->file( '/etc/hosts', "127.0.0.1 localhost\n" );
        $fs->file( '/tmp/data.txt', 'hello world' );

        # Create symlinks
        $fs->symlink( '/etc/hosts', '/etc/hosts.bak' );

        # Now use normal Perl I/O — all intercepted by Test::MockFile
        open my $fh, '<', '/etc/hosts' or die $!;
        my $content = <$fh>;
        close $fh;

        # Modify mid-test
        $fs->overwrite( '/tmp/data.txt', 'updated' );

        # Inspect internals
        my $mock = $fs->path('/etc/hosts');    # Test::MockFile object

        # Remove a single mock
        $fs->unmock('/tmp/data.txt');

        # Reset to empty filesystem
        $fs->clear;
    }
    # All mocks gone after scope exit

=head1 DESCRIPTION

Test::MockFileSys provides a higher-level API over L<Test::MockFile> for
tests that need to set up an entire mock filesystem tree. Instead of
manually managing individual mock objects and worrying about scope, users
create a single MockFileSys instance that owns all mocks, auto-creates
implied parent directories via C<mkdirs>, and integrates with strict mode
so that only managed paths are accessible.

When the MockFileSys object goes out of scope, all its mocks are cleaned
up automatically.

=head1 METHODS

=head2 new

    my $fs = Test::MockFileSys->new;

Creates a new MockFileSys container. Only one instance may be alive at a
time — creating a second while the first exists will croak.

The constructor mocks C</> as an existing empty directory and registers a
strict-mode rule that allows access to any path present in
C<%Test::MockFile::files_being_mocked>.

=cut

sub new {
    my ($class) = @_;

    if ($_active_instance) {
        croak("A Test::MockFileSys instance is already active — only one is allowed at a time");
    }

    my $self = bless {
        _mocks        => {},    # path => Test::MockFile object (strong refs)
        _auto_parents => {},    # path => 1 for dirs created by _ensure_parents / mkdirs
        _strict_rule  => undef,
        _root_mock    => undef,
    }, $class;

    # Mock '/' as an existing empty directory.
    # We go through Test::MockFile->dir directly, then mark as existing.
    # dir() alone creates a non-existent dir mock; has_content makes it "real".
    $self->{_root_mock} = Test::MockFile->dir( '/' );
    $self->{_root_mock}{'has_content'} = 1;
    $self->{_mocks}{'/'} = $self->{_root_mock};

    # Register a strict-mode rule: allow any path that's in %files_being_mocked.
    # This acts as a safety net so paths managed by this MockFileSys pass strict checks.
    my $rule = {
        'command_rule' => qr/.*/,
        'file_rule'    => qr/.*/,
        'action'       => sub {
            my ($ctx) = @_;
            return exists $Test::MockFile::files_being_mocked{ $ctx->{'filename'} } ? 1 : undef;
        },
    };
    Test::MockFile->_push_strict_rule($rule);
    $self->{_strict_rule} = $rule;

    $_active_instance = $self;
    Scalar::Util::weaken($_active_instance);

    return $self;
}

=head2 file

    $fs->file( '/path/to/file' );                        # non-existent file mock
    $fs->file( '/path/to/file', 'contents' );            # file with contents
    $fs->file( '/path/to/file', 'contents', \%stats );   # file with contents and stats

Creates a mock file at the given path. The parent directory must already
be a mocked existing directory (use C<mkdirs> to set up the tree first),
or this method will croak.

If the path is already mocked within this MockFileSys, returns the
existing mock object (deduplication).

=cut

sub file {
    my ( $self, $file, $contents, @stats ) = @_;

    defined $file && length $file
      or croak("file() requires a path");

    my $path = Test::MockFile::_abs_path_to_file($file);

    $path eq '/'
      and croak("Cannot mock '/' as a file — root must be a directory");

    # Deduplication: return existing mock if present
    if ( my $existing = $self->{_mocks}{$path} ) {
        return $existing;
    }

    # Check for conflict with standalone mocks outside this MockFileSys
    if ( $Test::MockFile::files_being_mocked{$path} ) {
        croak("Path $path is already mocked outside this MockFileSys");
    }

    # Parent directory must exist and be a directory
    $self->_check_parent_exists($path);

    my $mock = Test::MockFile->file( $path, $contents, @stats );
    $self->{_mocks}{$path} = $mock;

    return $mock;
}

=head2 dir

    $fs->dir( '/path/to/dir' );
    $fs->dir( '/path/to/dir', \%opts );

Creates a mock directory at the given path. The parent directory must
already be a mocked existing directory, or this method will croak.

If the path is already mocked within this MockFileSys, returns the
existing mock object.

Note: the root directory C</> is always created by the constructor.
Calling C<< $fs->dir('/') >> returns the existing root mock.

=cut

sub dir {
    my ( $self, $dirname, @opts ) = @_;

    defined $dirname && length $dirname
      or croak("dir() requires a path");

    my $path = Test::MockFile::_abs_path_to_file($dirname);

    # Cleanup trailing slashes (same as MockFile.pm)
    $path =~ s{[/\\]$}{}xmsg if $path ne '/';

    # Deduplication: return existing mock if present
    if ( my $existing = $self->{_mocks}{$path} ) {
        return $existing;
    }

    # Check for conflict with standalone mocks
    if ( $Test::MockFile::files_being_mocked{$path} ) {
        croak("Path $path is already mocked outside this MockFileSys");
    }

    # Parent must exist (except for root, which is created in constructor)
    if ( $path ne '/' ) {
        $self->_check_parent_exists($path);
    }

    my $mock = Test::MockFile->dir( $path, @opts );
    $mock->{'has_content'} = 1;    # mark as existing directory
    $self->{_mocks}{$path} = $mock;

    return $mock;
}

=head2 symlink

    $fs->symlink( $target, '/path/to/link' );

Creates a mock symlink at C<$path> pointing to C<$target>. The parent
directory of the link path must be a mocked existing directory.

If the path is already mocked within this MockFileSys, returns the
existing mock object.

=cut

sub symlink {
    my ( $self, $readlink, $file ) = @_;

    defined $file && length $file
      or croak("symlink() requires a link path");

    my $path = Test::MockFile::_abs_path_to_file($file);

    # Deduplication
    if ( my $existing = $self->{_mocks}{$path} ) {
        return $existing;
    }

    # Check for conflict
    if ( $Test::MockFile::files_being_mocked{$path} ) {
        croak("Path $path is already mocked outside this MockFileSys");
    }

    $self->_check_parent_exists($path);

    my $mock = Test::MockFile->symlink( $readlink, $path );
    $self->{_mocks}{$path} = $mock;

    return $mock;
}

=head2 mkdirs

    $fs->mkdirs( '/a/b/c', '/usr/local/bin', '/etc' );

Creates directory trees (like C<mkdir -p>). For each path, creates
directory mocks for all intermediate components that don't already
exist. All created directories have C<has_content =E<gt> 1>.

Croaks if an intermediate path is already mocked as a non-directory
(e.g., a file at C</a/b> blocks C<mkdirs('/a/b/c')>).

=cut

sub mkdirs {
    my ( $self, @paths ) = @_;

    @paths or croak("mkdirs() requires at least one path");

    for my $raw_path (@paths) {
        my $path = Test::MockFile::_abs_path_to_file($raw_path);
        $self->_mkdirs_single($path);
    }

    return;
}

=head2 write_file

    $fs->write_file( '/path/to/file', 'contents' );
    $fs->write_file( '/path/to/file', 'contents', \%stats );

Like C<file()> but requires content (croaks if content is undef).

=cut

sub write_file {
    my ( $self, $file, $contents, @stats ) = @_;

    defined $contents
      or croak("write_file() requires content — use file() for non-existent files");

    return $self->file( $file, $contents, @stats );
}

=head2 overwrite

    $fs->overwrite( '/path/to/file', 'new contents' );   # setter
    my $contents = $fs->overwrite( '/path/to/file' );     # getter

Updates the contents of an existing mock file. Croaks if the path is not
mocked within this MockFileSys.

With no second argument, returns current contents (getter mode).

=cut

sub overwrite {
    my ( $self, $file, @rest ) = @_;

    defined $file && length $file
      or croak("overwrite() requires a path");

    my $path = Test::MockFile::_abs_path_to_file($file);
    my $mock = $self->{_mocks}{$path}
      or croak("Cannot overwrite '$path' — not mocked in this MockFileSys");

    # Getter mode
    return $mock->contents() unless @rest;

    # Setter mode
    my $new_contents = $rest[0];
    $mock->contents($new_contents);

    # Update mtime/ctime
    my $now = time;
    $mock->{'mtime'} = $now;
    $mock->{'ctime'} = $now;

    return $mock;
}

=head2 mkdir

    $fs->mkdir( '/path/to/dir' );
    $fs->mkdir( '/path/to/dir', 0755 );

Convenience alias for C<dir()>. If a numeric mode is provided, it is
applied to the directory's permissions.

=cut

sub mkdir {
    my ( $self, $dirname, $mode ) = @_;

    my $mock = $self->dir($dirname);

    if ( defined $mode ) {
        # Apply mode like Test::MockFile does
        my $perms = Test::MockFile::S_IFPERMS() & int($mode);
        $mock->{'mode'} = ( $perms & ~umask ) | Test::MockFile::S_IFDIR();
    }

    return $mock;
}

=head2 path

    my $mock_obj = $fs->path('/path/to/file');

Returns the underlying L<Test::MockFile> object for the given path, or
C<undef> if the path is not mocked within this MockFileSys.

=cut

sub path {
    my ( $self, $file ) = @_;

    defined $file && length $file
      or return undef;

    my $path = Test::MockFile::_abs_path_to_file($file);
    return $self->{_mocks}{$path};
}

=head2 unmock

    $fs->unmock('/path/to/file');

Removes a single path from the MockFileSys container. The underlying
L<Test::MockFile> object goes out of scope and is destroyed.

Croaks if the path has mocked children still present in this
MockFileSys.

=cut

sub unmock {
    my ( $self, $file ) = @_;

    defined $file && length $file
      or croak("unmock() requires a path");

    my $path = Test::MockFile::_abs_path_to_file($file);

    $path eq '/'
      and croak("Cannot unmock '/' — use clear() to reset the filesystem");

    exists $self->{_mocks}{$path}
      or croak("Cannot unmock '$path' — not mocked in this MockFileSys");

    # Check for children
    my @children = grep { $_ ne $path && m{^\Q$path/\E} } keys %{ $self->{_mocks} };
    if (@children) {
        my $list = join ', ', sort @children;
        croak("Cannot unmock '$path' — still has mocked children: $list");
    }

    # Remove from our tracking. The strong ref drop triggers MockFile DESTROY.
    delete $self->{_mocks}{$path};
    delete $self->{_auto_parents}{$path};

    return;
}

=head2 clear

    $fs->clear;

Destroys all mocks and resets the virtual filesystem to an empty tree
(just the root C</> mock remains). Useful for multi-scenario tests.

=cut

sub clear {
    my ($self) = @_;

    # Destroy all mocks in reverse-depth order (deepest first), skipping root.
    my @paths = sort { length($b) <=> length($a) || $b cmp $a }
                grep { $_ ne '/' }
                keys %{ $self->{_mocks} };

    for my $path (@paths) {
        delete $self->{_mocks}{$path};
    }

    $self->{_auto_parents} = {};

    # Root mock should still be alive. If it got destroyed somehow, recreate it.
    if ( !$Test::MockFile::files_being_mocked{'/'} ) {
        $self->{_root_mock} = Test::MockFile->dir('/');
        $self->{_root_mock}{'has_content'} = 1;
        $self->{_mocks}{'/'} = $self->{_root_mock};
    }

    return;
}

# ---- Internal methods ----

# Verify that the parent directory of $path is a mocked existing directory
# within this MockFileSys. Croaks on failure.
sub _check_parent_exists {
    my ( $self, $path ) = @_;

    my $parent = _parent_dir($path);

    my $parent_mock = $self->{_mocks}{$parent};
    unless ($parent_mock) {
        croak("Parent directory '$parent' does not exist in this MockFileSys — use mkdirs() to create it first");
    }

    # Parent must be an existing directory
    unless ( $parent_mock->is_dir ) {
        croak("Parent path '$parent' is not a directory");
    }

    return 1;
}

# Create a full directory tree for a single path (mkdir -p semantics).
# Creates all intermediate components that don't already exist.
sub _mkdirs_single {
    my ( $self, $target_path ) = @_;

    # Split into components and build up incrementally
    my @parts = split m{/}, $target_path;
    shift @parts;    # remove empty string before leading /

    my $current = '';
    for my $part (@parts) {
        $current .= "/$part";

        # Already mocked in this MockFileSys? Verify it's a directory.
        if ( my $existing = $self->{_mocks}{$current} ) {
            if ( $existing->is_dir ) {
                next;
            }
            else {
                croak("Cannot mkdirs through '$current' — it is already mocked as a non-directory");
            }
        }

        # Already mocked outside? Check it's a dir.
        if ( my $existing = $Test::MockFile::files_being_mocked{$current} ) {
            if ( $existing->is_dir ) {
                # Take ownership — store in our tracking
                $self->{_mocks}{$current} = $existing;
                $self->{_auto_parents}{$current} = 1;
                next;
            }
            else {
                croak("Cannot mkdirs through '$current' — it is already mocked as a non-directory");
            }
        }

        # Create the directory mock and mark as existing
        my $mock = Test::MockFile->dir($current);
        $mock->{'has_content'} = 1;
        $self->{_mocks}{$current} = $mock;
        $self->{_auto_parents}{$current} = 1;
    }

    return;
}

# Return the parent directory of an absolute path.
# _parent_dir('/a/b/c') => '/a/b'
# _parent_dir('/a')     => '/'
sub _parent_dir {
    my ($path) = @_;

    return '/' if $path eq '/';

    ( my $parent = $path ) =~ s{/[^/]+$}{};
    return length($parent) ? $parent : '/';
}

sub DESTROY {
    my ($self) = @_;
    ref $self or return;

    # 1. Remove strict rule from @STRICT_RULES
    if ( my $rule = $self->{_strict_rule} ) {
        Test::MockFile->_remove_strict_rule($rule);
        $self->{_strict_rule} = undef;
    }

    # 2. Delete all explicitly-managed mocks deepest-first (skipping root)
    my @paths = sort { length($b) <=> length($a) || $b cmp $a }
                grep { $_ ne '/' }
                keys %{ $self->{_mocks} };

    for my $path (@paths) {
        delete $self->{_mocks}{$path};
    }

    # 3. Destroy root mock last
    delete $self->{_mocks}{'/'};
    $self->{_root_mock} = undef;

    # 4. Clear singleton
    $_active_instance = undef;
}

1;

__END__

=head1 STRICT MODE INTEGRATION

When L<Test::MockFile> is loaded in strict mode (the default), MockFileSys
registers a single dynamic strict rule that allows access to any path
present in C<%Test::MockFile::files_being_mocked>. This means:

=over 4

=item * Paths created via C<file()>, C<dir()>, C<symlink()>, or C<mkdirs()>
are accessible.

=item * Paths not managed by this MockFileSys (and not mocked elsewhere)
will trigger a strict-mode violation, as expected.

=back

=head1 SINGLETON ENFORCEMENT

Only one MockFileSys instance may be alive at a time. This prevents
conflicts between multiple filesystem containers. If you need to reset
the filesystem mid-test, use C<clear()> instead of creating a new instance.

=head1 PARENT DIRECTORY SEMANTICS

Operations that create files, directories, or symlinks require the parent
directory to already exist as a mocked directory. This matches real
filesystem behavior. Use C<mkdirs()> to set up directory trees before
creating files:

    my $fs = Test::MockFileSys->new;
    $fs->mkdirs('/usr/local/bin');
    $fs->file('/usr/local/bin/perl', '#!/usr/bin/perl');

=head1 SEE ALSO

L<Test::MockFile>

=cut
