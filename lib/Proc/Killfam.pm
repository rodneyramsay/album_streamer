package Proc::Killfam;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(killfam);
use strict;
use warnings;

sub killfam {
    my ($sig, @pids) = @_;
    return 1;
}

1;
