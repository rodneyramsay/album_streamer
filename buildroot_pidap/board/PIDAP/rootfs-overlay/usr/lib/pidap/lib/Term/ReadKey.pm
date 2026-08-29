package Term::ReadKey;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ReadKey ReadMode);
use strict;
use warnings;

sub ReadKey { return undef; }
sub ReadMode { return 1; }

1;
