#!/usr/bin/perl -w

use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;

use Test::MockFile qw( nostrict );

# --- Non-strict mode: pipe modes on mocked files produce a warning ---

subtest 'pipe mode |- on mocked file warns in nostrict' => sub {
    my $mock = Test::MockFile->file( '/tmp/pipe_mock_out', 'data' );
    my @w;
    local $SIG{__WARN__} = sub { push @w, $_[0] };

    open my $fh, '|-', '/tmp/pipe_mock_out';
    close $fh if $fh;

    ok( scalar @w >= 1, 'got at least one warning for |- on mocked file' );
    like(
        $w[0],
        qr/pipe mode '\|-'.*mocked file.*\/tmp\/pipe_mock_out.*not supported/,
        'warning mentions pipe mode, mocked file path, and unsupported',
    );
};

subtest 'pipe mode -| on mocked file warns in nostrict' => sub {
    my $mock = Test::MockFile->file( '/tmp/pipe_mock_in', 'data' );
    my @w;
    local $SIG{__WARN__} = sub { push @w, $_[0] };

    open my $fh, '-|', '/tmp/pipe_mock_in';
    close $fh if $fh;

    ok( scalar @w >= 1, 'got at least one warning for -| on mocked file' );
    like(
        $w[0],
        qr/pipe mode '-\|'.*mocked file.*\/tmp\/pipe_mock_in.*not supported/,
        'warning mentions pipe mode, mocked file path, and unsupported',
    );
};

subtest 'pipe mode on unmocked file does not produce pipe-specific warning' => sub {
    my @w;
    local $SIG{__WARN__} = sub { push @w, $_[0] };

    # /usr/bin/true is unmocked — should NOT get the pipe-mode-on-mock warning
    open my $fh, '-|', '/usr/bin/true';
    close $fh if $fh;

    my @pipe_warnings = grep { /pipe mode.*mocked file.*not supported/ } @w;
    is( \@pipe_warnings, [], 'no pipe-mode-on-mock warning for unmocked file' );
};

done_testing();
