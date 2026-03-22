use strict;
use warnings;

use Test2::Bundle::Extended;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;
use Test2::Tools::Exception qw< lives >;

use Test::MockFile qw< nostrict >;

# Force _goto_is_available() to return false, simulating Perl < 5.015
# where the fallback CORE:: calls are used instead of goto.
# Also disable _upgrade_barewords to simulate Perl 5.12 where the
# bareword detection via Internals::SvREADONLY doesn't work,
# leaving $_[0] as a plain string like "DIR".
{
    no warnings 'redefine';
    *Test::MockFile::_goto_is_available = sub { 0 };
    *Test::MockFile::_upgrade_barewords = sub { return ( 0, @_ ) };
}

# Test that opendir/readdir/closedir with lexical handles work
# even when goto is not available (the fallback path).
ok(
    lives(
        sub {
            opendir( my $dh, '.' ) or die "opendir failed: $!";
            my @entries = readdir($dh);
            closedir($dh);
            die "no entries" unless @entries;
        }
    ),
    'opendir/readdir/closedir work via fallback path with lexical handle',
);

# Test with File::Find which uses bareword DIR internally.
# This reproduces GH#294: on Perl 5.12 the fallback CORE::opendir()
# failed with "Can't use string as a symbol ref under strict refs".
require File::Find;
ok(
    lives(
        sub {
            File::Find::find(
                {
                    'wanted'   => sub { 1 },
                    'no_chdir' => 1,
                },
                '.',
            );
        }
    ),
    'File::Find works via fallback path (bareword DIR handle)',
);

is( "$@", '', 'No observed error' );

done_testing();
