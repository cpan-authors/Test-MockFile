# Copyright (c) 2018, cPanel, LLC.
# All rights reserved.
# http://cpanel.net
#
# This is free software; you can redistribute it and/or modify it under the
# same terms as Perl itself. See L<perlartistic>.

package Test::MockFileSys;

use 5.016;
use strict;
use warnings;

use Carp qw(croak confess);
use Cwd        ();
use File::Spec ();
use Scalar::Util ();

use Errno qw/ENOENT/;

use Test::MockFile ();

our $VERSION = '0.001';

# Singleton tracking — only one MockFileSys alive at a time
my $_active_instance;

=head1 NAME

Test::MockFileSys - Scoped virtual filesystem built on Test::MockFile

=head1 SYNOPSIS

    use Test::MockFile;
    use Test::MockFileSys;

    {
        my $fs = Test::MockFileSys->new;

        # Set up directory tree
        $fs->mkdirs('/usr/local/bin', '/etc', '/tmp');

        # Create files (parent dirs must exist)
        $fs->file('/etc/passwd', "root:x:0:0:root:/root:/bin/bash\n");
        $fs->file('/tmp/data.txt', 'hello world');

        # Use normal Perl builtins — all intercepted
        open my $fh, '<', '/etc/passwd' or die $!;
        my $line = <$fh>;
        close $fh;

        mkdir '/tmp/subdir' or die $!;

        # Open for write fails if parent doesn't exist
        open(my $fh2, '>', '/no/such/file') and die "should have failed";
        # $! == ENOENT

        # Inspect or modify mocks
        $fs->overwrite('/tmp/data.txt', 'new content');
        my $mock = $fs->path('/tmp/data.txt');  # Test::MockFile object

        # Reset to empty filesystem
        $fs->clear;
    }
    # All mocks cleaned up when $fs goes out of scope

=head1 DESCRIPTION

Test::MockFileSys provides a virtual empty filesystem for tests. Users
create a MockFileSys instance, set up directory trees with C<mkdirs>,
then interact using normal Perl builtins (C<open>, C<mkdir>, C<unlink>,
C<readdir>). Operations fail realistically when prerequisites aren't
met — writing to a file fails with C<ENOENT> if the parent directory
hasn't been created, just like a real filesystem. All path accesses are
intercepted (no real filesystem I/O), and everything is cleaned up when
the MockFileSys object goes out of scope.

Only one MockFileSys instance may be active at a time.

=head1 METHODS

=cut

# Normalize a path to absolute
sub _normalize_path {
    my ($path) = @_;

    return unless defined $path;

    # Make absolute
    if ( $path !~ m{^/} ) {
        $path = Cwd::getcwd() . '/' . $path;
    }

    # Resolve . and .. and collapse slashes
    my @parts;
    for my $part ( split m{/}, $path ) {
        next if $part eq '' || $part eq '.';
        if ( $part eq '..' ) {
            pop @parts;
            next;
        }
        push @parts, $part;
    }

    return '/' . join( '/', @parts );
}

# Return the parent directory of a path, or undef for root
sub _parent_dir {
    my ($path) = @_;
    return undef if !defined $path || $path eq '/';
    ( my $parent = $path ) =~ s{/[^/]+$}{};
    return length $parent ? $parent : '/';
}

=head2 new

    my $fs = Test::MockFileSys->new;

Creates a new MockFileSys instance. Mocks C</> as an existing directory
with autovivify enabled so all path accesses are intercepted. Enables
strict filesystem mode so operations on paths without existing parents
fail with C<ENOENT>.

Only one instance may be active at a time; creating a second while the
first exists will croak.

=cut

sub new {
    my ($class) = @_;

    if ($_active_instance) {
        croak("A Test::MockFileSys instance is already active. Only one may exist at a time.");
    }

    # Check that / isn't already mocked by something else
    if ( $Test::MockFile::files_being_mocked{'/'} ) {
        croak("Path / is already mocked outside this MockFileSys");
    }

    my $self = bless {
        _mocks        => {},    # path => Test::MockFile object (strong refs)
        _auto_parents => {},    # path => 1 for dirs auto-created by _ensure_parents
        _root_mock    => undef, # the root / mock
        _strict_rule  => undef, # our strict rule in @STRICT_RULES
    }, $class;

    # Create root directory mock with autovivify
    $self->{_root_mock} = Test::MockFile->dir( '/', { autovivify => 1 } );

    # Materialize root as existing directory
    # (dir() creates it as non-existent based on child count, so force it)
    $self->{_root_mock}{'has_content'} = 1;

    # Enable strict filesystem mode (parent-dir checks)
    $Test::MockFile::_strict_fs_mode = 1;

    # Register a strict rule that allows any path in %files_being_mocked
    $self->{_strict_rule} = {
        'command_rule' => qr/.*/,
        'file_rule'    => qr/.*/,
        'action'       => sub {
            my ($ctx) = @_;
            return exists $Test::MockFile::files_being_mocked{ $ctx->{'filename'} } ? 1 : undef;
        },
    };
    push @Test::MockFile::STRICT_RULES, $self->{_strict_rule};

    $_active_instance = $self;
    Scalar::Util::weaken($_active_instance);

    return $self;
}

=head2 file

    my $mock = $fs->file('/path/to/file');
    my $mock = $fs->file('/path/to/file', $contents);
    my $mock = $fs->file('/path/to/file', $contents, \%stats);

Creates a mock file at the given path. The parent directory must already
be a mocked existing directory (croak otherwise). If a mock already
exists at this path, returns the existing object (deduplication).

C<$contents> of C<undef> creates a non-existent file placeholder.

=cut

sub file {
    my ( $self, $path, $contents, @stats ) = @_;

    my $abs = _normalize_path($path);
    defined $abs or croak("No path provided to file()");
    $abs eq '/' and croak("Cannot create a file at /");

    # Deduplication: return existing mock
    if ( my $existing = $self->{_mocks}{$abs} ) {
        return $existing;
    }

    # Check parent directory exists
    my $parent = _parent_dir($abs);
    $self->_require_parent_dir($parent);

    # Check not mocked outside this MockFileSys
    if ( $Test::MockFile::files_being_mocked{$abs} && !$self->{_auto_parents}{$abs} ) {
        croak("Path $abs is already mocked outside this MockFileSys");
    }

    # If an auto-created parent placeholder exists at this path, remove it first
    if ( $self->{_auto_parents}{$abs} ) {
        croak("Path $abs is already mocked as a directory by this MockFileSys");
    }

    my $mock = Test::MockFile->file( $abs, $contents, @stats );
    $self->{_mocks}{$abs} = $mock;

    return $mock;
}

=head2 dir

    my $mock = $fs->dir('/path/to/dir');
    my $mock = $fs->dir('/path/to/dir', \%opts);

Creates a mock directory at the given path. The parent directory must
already be a mocked existing directory. Returns existing mock if path
is already managed.

The directory is created as an existing (stat-able) directory with
C<has_content = 1>.

=cut

sub dir {
    my ( $self, $path, $opts ) = @_;

    my $abs = _normalize_path($path);
    defined $abs or croak("No path provided to dir()");

    # Root is always managed by the constructor
    return $self->{_root_mock} if $abs eq '/';

    # Deduplication: return existing mock
    if ( my $existing = $self->{_mocks}{$abs} ) {
        return $existing;
    }

    # Auto-parent that was already created — return it
    if ( $self->{_auto_parents}{$abs} && $Test::MockFile::files_being_mocked{$abs} ) {
        my $mock = $Test::MockFile::files_being_mocked{$abs};
        # Promote from auto_parent to explicit mock
        $self->{_mocks}{$abs} = $mock;
        delete $self->{_auto_parents}{$abs};
        return $mock;
    }

    # Check parent directory exists
    my $parent = _parent_dir($abs);
    $self->_require_parent_dir($parent);

    # Check not mocked outside this MockFileSys
    if ( $Test::MockFile::files_being_mocked{$abs} ) {
        croak("Path $abs is already mocked outside this MockFileSys");
    }

    my $mock = Test::MockFile->dir($abs);
    # Make it an existing directory
    $mock->{'has_content'} = 1;

    $self->{_mocks}{$abs} = $mock;

    return $mock;
}

=head2 symlink

    my $mock = $fs->symlink($target, '/path/to/link');

Creates a mock symbolic link at the given path pointing to C<$target>.
The parent directory must exist. Returns existing mock if path is
already managed.

=cut

sub symlink {
    my ( $self, $target, $path ) = @_;

    my $abs = _normalize_path($path);
    defined $abs or croak("No path provided to symlink()");
    $abs eq '/' and croak("Cannot create a symlink at /");

    # Deduplication
    if ( my $existing = $self->{_mocks}{$abs} ) {
        return $existing;
    }

    # Check parent
    my $parent = _parent_dir($abs);
    $self->_require_parent_dir($parent);

    # Check not externally mocked
    if ( $Test::MockFile::files_being_mocked{$abs} && !$self->{_auto_parents}{$abs} ) {
        croak("Path $abs is already mocked outside this MockFileSys");
    }

    my $mock = Test::MockFile->symlink( $target, $abs );
    $self->{_mocks}{$abs} = $mock;

    return $mock;
}

# Check that a parent directory is a mocked existing directory
sub _require_parent_dir {
    my ( $self, $parent ) = @_;
    return if !defined $parent;    # root has no parent

    my $parent_mock = $Test::MockFile::files_being_mocked{$parent};
    if ( !$parent_mock || !$parent_mock->is_dir() || !$parent_mock->{'has_content'} ) {
        croak("Parent directory $parent does not exist (use mkdirs to create directory trees)");
    }
}

=head2 mkdirs

    $fs->mkdirs('/a/b/c', '/usr/local/bin', '/etc');

Creates directory mocks for each path and all intermediate components,
like C<mkdir -p>. Each path's full ancestor chain is created. Idempotent:
existing directories are skipped.

=cut

sub mkdirs {
    my ( $self, @paths ) = @_;

    for my $path (@paths) {
        my $abs = _normalize_path($path);
        defined $abs or croak("Undefined path passed to mkdirs()");

        # Build list of dirs to create from root down
        my @components;
        my $dir = $abs;
        while ( $dir ne '/' ) {
            unshift @components, $dir;
            $dir = _parent_dir($dir);
        }

        for my $comp (@components) {
            # Already explicitly managed
            next if $self->{_mocks}{$comp};
            # Already auto-created
            next if $self->{_auto_parents}{$comp};

            # Check for existing mock (could be autovivified by root)
            if ( my $existing = $Test::MockFile::files_being_mocked{$comp} ) {
                if ( $existing->is_dir() ) {
                    # Adopt the existing dir mock (e.g., autovivified intermediate dir)
                    $existing->{'has_content'} = 1;
                    $self->{_auto_parents}{$comp} = 1;
                    $self->{_mocks}{$comp} = $existing;
                    next;
                }
                else {
                    croak("Cannot create directory $comp — path is already mocked as a non-directory");
                }
            }

            # Create directory mock
            my $mock = Test::MockFile->dir($comp);
            $mock->{'has_content'} = 1;
            $self->{_auto_parents}{$comp} = 1;

            # Keep a strong ref so it stays alive
            $self->{_mocks}{$comp} = $mock;
        }
    }

    return;
}

=head2 write_file

    $fs->write_file('/path/to/file', $contents);
    $fs->write_file('/path/to/file', $contents, \%stats);

Like C<file()> but requires content (croaks if C<$contents> is undef).

=cut

sub write_file {
    my ( $self, $path, $contents, @stats ) = @_;

    croak("write_file() requires defined contents") unless defined $contents;
    return $self->file( $path, $contents, @stats );
}

=head2 overwrite

    $fs->overwrite('/path/to/file', $new_contents);   # setter
    my $contents = $fs->overwrite('/path/to/file');     # getter

Updates the contents of an existing mock file. With no second argument,
returns the current contents (getter mode). Croaks if the path is not
managed by this MockFileSys.

=cut

sub overwrite {
    my ( $self, $path, @args ) = @_;

    my $abs = _normalize_path($path);
    my $mock = $self->{_mocks}{$abs};
    $mock or croak("Cannot overwrite $abs — not managed by this MockFileSys");

    # Getter mode
    if ( !@args ) {
        return $mock->contents();
    }

    # Setter mode
    my $new_contents = $args[0];
    $mock->contents($new_contents);
    my $now = time;
    $mock->{'mtime'} = $now;
    $mock->{'ctime'} = $now;

    return $mock;
}

=head2 mkdir

    $fs->mkdir('/path/to/dir');
    $fs->mkdir('/path/to/dir', $mode);

Alias for C<dir()> with optional permissions. Creates a single directory
(parent must exist).

=cut

sub mkdir {
    my ( $self, $path, $mode ) = @_;
    my $mock = $self->dir($path);
    if ( defined $mode ) {
        $mock->{'mode'} = ( $mode & Test::MockFile::S_IFPERMS() ) | Test::MockFile::S_IFDIR();
    }
    return $mock;
}

=head2 path

    my $mock = $fs->path('/some/path');

Returns the underlying L<Test::MockFile> object for the given path,
or C<undef> if the path is not managed by this MockFileSys.

=cut

sub path {
    my ( $self, $path ) = @_;
    my $abs = _normalize_path($path);
    return $self->{_mocks}{$abs};
}

=head2 unmock

    $fs->unmock('/path/to/file');

Removes a single path from the MockFileSys, destroying its mock. Croaks
if the path has mocked children managed by this instance.

=cut

sub unmock {
    my ( $self, $path ) = @_;

    my $abs = _normalize_path($path);
    $abs eq '/' and croak("Cannot unmock / — it is the root of the MockFileSys");

    my $mock = $self->{_mocks}{$abs};
    $mock or croak("Cannot unmock $abs — not managed by this MockFileSys");

    # Check for children
    my $prefix = $abs . '/';
    my @children = grep { index( $_, $prefix ) == 0 } keys %{ $self->{_mocks} };
    if (@children) {
        croak("Cannot unmock $abs — still has mocked children: " . join( ', ', sort @children ));
    }

    delete $self->{_mocks}{$abs};
    delete $self->{_auto_parents}{$abs};
    # $mock goes out of scope here, triggering Test::MockFile DESTROY

    return 1;
}

=head2 clear

    $fs->clear;

Destroys all mocks and resets the virtual filesystem to an empty tree
(just the root C</> mock remains). Useful for multi-scenario tests.

=cut

sub clear {
    my ($self) = @_;

    # Delete all mocks deepest-first (excluding root)
    my @paths = sort { length($b) <=> length($a) || $b cmp $a }
        grep { $_ ne '/' }
        keys %{ $self->{_mocks} };

    for my $path (@paths) {
        delete $self->{_mocks}{$path};
    }

    $self->{_auto_parents} = {};

    # Also clean up any autovivified children on the root mock
    if ( $self->{_root_mock} ) {
        delete $self->{_root_mock}{'_autovivified_children'};
        # Re-establish root as existing directory
        $self->{_root_mock}{'has_content'} = 1;
    }

    return;
}

sub DESTROY {
    my ($self) = @_;

    # Tolerate partial cleanup during global destruction
    return if ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} eq 'DESTRUCT';

    # 1. Disable strict fs mode
    $Test::MockFile::_strict_fs_mode = 0;

    # 2. Remove our strict rule
    if ( $self->{_strict_rule} ) {
        my $rule = $self->{_strict_rule};
        @Test::MockFile::STRICT_RULES = grep { $_ != $rule } @Test::MockFile::STRICT_RULES;
        $self->{_strict_rule} = undef;
    }

    # 3. Delete all explicitly-managed mocks (deepest first)
    if ( $self->{_mocks} ) {
        my @paths = sort { length($b) <=> length($a) || $b cmp $a }
            keys %{ $self->{_mocks} };
        for my $path (@paths) {
            delete $self->{_mocks}{$path};
        }
    }

    # 4. Destroy root mock (cascades to autovivified children)
    $self->{_root_mock} = undef;

    # 5. Clear singleton
    $_active_instance = undef;
}

=head1 SEE ALSO

L<Test::MockFile>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.

=cut

1;
