#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Time::HiRes qw(sleep);

my $ROOT = abs_path(dirname($FindBin::Bin));
my $RUN_DIR = $ENV{PIDAP_RUN_DIR} || $ROOT;
chdir($ROOT) or die "chdir $ROOT: $!";

my %PIN = (A => 5, B => 6, X => 16, Y => 24);
my $HOLD       = 0.15;
my $POST_EVENT = 0.50;

my $passed = 0;
my $failed = 0;

sub log_test {
    my ($msg) = @_;
    print "[TEST] $msg\n";
}

sub play_pid {
    my $file = "$RUN_DIR/pidap.generated.play_pid";
    return 0 unless -r $file;
    open(my $fh, '<', $file) or return 0;
    my $line = <$fh>;
    close($fh);
    return 0 unless defined $line && $line =~ /(\d+)/;
    return int($1);
}

sub play_state {
    my ($pid) = @_;
    return '' unless $pid && -r "/proc/$pid/status";
    open(my $fh, '<', "/proc/$pid/status") or return '';
    my $state = '';
    while (<$fh>) {
        if (/^State:\s*(\S)/) { $state = $1; last; }
    }
    close($fh);
    return $state;
}

sub is_playing {
    my ($pid) = @_;
    return play_state($pid) ne 'T';
}

sub is_paused {
    my ($pid) = @_;
    return play_state($pid) eq 'T';
}

sub gpio_set {
    my ($pin, $state) = @_;
    return 1 if system("pinctrl set $pin op $state >/dev/null 2>&1") == 0;
    return 1 if system("raspi-gpio set $pin op $state >/dev/null 2>&1") == 0;
    return 0;
}

sub press {
    my ($label) = @_;
    my $pin = $PIN{$label} // die "unknown label $label";
    gpio_set($pin, 'dl') or die "could not drive $label (pin $pin) low";
}

sub release {
    my ($label) = @_;
    my $pin = $PIN{$label} // die "unknown label $label";
    gpio_set($pin, 'dh') or die "could not drive $label (pin $pin) high";
}

sub tap {
    my ($label) = @_;
    press($label);
    sleep($HOLD);
    release($label);
    sleep($POST_EVENT);
}

sub run_tests {
    log_test("--- Pause/resume end-to-end ---");

    my $pid = play_pid();
    unless ($pid) {
        log_test("FAIL: no play pid");
        $failed++;
        return;
    }
    log_test("play pid is $pid, initial state " . play_state($pid));

    unless (is_playing($pid)) {
        log_test("FAIL: play not running before test");
        $failed++;
        return;
    }

    tap('X');
    if (is_paused($pid)) {
        log_test("PASS: X pauses playback (state " . play_state($pid) . ")");
        $passed++;
    } else {
        log_test("FAIL: X did not pause playback (state " . play_state($pid) . ")");
        $failed++;
    }

    tap('X');
    if (is_playing($pid)) {
        log_test("PASS: X resumes playback (state " . play_state($pid) . ")");
        $passed++;
    } else {
        log_test("FAIL: X did not resume playback (state " . play_state($pid) . ")");
        $failed++;
    }

    log_test("--- Done. Passed: $passed / Failed: $failed ---");
}

run_tests();
exit($failed ? 1 : 0);
