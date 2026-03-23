#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;

use Test::MockFile;    # strict mode enabled by default

# --- Strict mode: pipe modes on mocked files die ---

subtest 'pipe mode |- on mocked file dies in strict mode' => sub {
    my $mock = Test::MockFile->file( '/tmp/pipe_strict_out', 'data' );

    my $err = dies {
        open my $fh, '|-', '/tmp/pipe_strict_out';
        close $fh if $fh;
    };

    like(
        $err,
        qr/pipe mode '\|-'.*mocked file.*\/tmp\/pipe_strict_out.*not supported/,
        'strict mode dies with pipe mode violation message',
    );
};

subtest 'pipe mode -| on mocked file dies in strict mode' => sub {
    my $mock = Test::MockFile->file( '/tmp/pipe_strict_in', 'data' );

    my $err = dies {
        open my $fh, '-|', '/tmp/pipe_strict_in';
        close $fh if $fh;
    };

    like(
        $err,
        qr/pipe mode '-\|'.*mocked file.*\/tmp\/pipe_strict_in.*not supported/,
        'strict mode dies with pipe mode violation message',
    );
};

done_testing();
