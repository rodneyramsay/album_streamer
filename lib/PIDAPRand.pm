package PIDAPRand;

use strict;
use warnings;
use Fcntl qw(O_RDONLY);
use Time::HiRes;

sub _read_seed {
    for my $dev ('/dev/hwrng', '/dev/urandom') {
        if (sysopen(my $fh, $dev, O_RDONLY)) {
            my $buf = '';
            my $n = sysread($fh, $buf, 4);
            close($fh) if $fh;
            if ($n && $n == 4) {
                return unpack('L', $buf);
            }
        }
    }
    # Last resort: a less-than-ideal but still variable fallback.
    return int(Time::HiRes::time() * 1_000_000) ^ $$;
}

srand(_read_seed());

1;
