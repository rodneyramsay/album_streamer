#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(sleep);

my $VOLUME_CONTROL = $ENV{PIDAP_VOLUME_CONTROL} || 'Amp';
my $VOLUME_STEP    = $ENV{PIDAP_VOLUME_STEP}    || 2;

my %PIN = (A => 5, B => 6, X => 16, Y => 24);
my $HOLD       = 0.15;
my $POST_EVENT = 0.50;

my $passed = 0;
my $failed = 0;
my $initial_volume;

sub log_test {
    my ($msg) = @_;
    print "[TEST] $msg\n";
}

sub amixer_cmd {
    my ($cmd) = @_;
    return qx{$cmd 2>&1};
}

sub probe_amixer {
    my $out = amixer_cmd("amixer sget '$VOLUME_CONTROL'");
    my $ok = ($? == 0) ? 1 : 0;
    log_test("amixer sget $VOLUME_CONTROL: " . ($ok ? 'ok' : 'not available'));
    return $ok;
}

sub set_volume {
    my ($pct) = @_;
    amixer_cmd("amixer sset '$VOLUME_CONTROL' '${pct}%'");
}

sub get_volume {
    my $out = amixer_cmd("amixer sget '$VOLUME_CONTROL'");
    return undef unless $? == 0;
    my @p = ($out =~ /\[(\d+)%\]/g);
    return undef unless @p;
    my $sum = 0;
    $sum += $_ for @p;
    return int($sum / @p + 0.5);
}

sub expect_volume_changed {
    my ($desc, $before, $after, $expected_min, $direction) = @_;
    my $actual = $after - $before;
    my $ok = 0;
    if ($direction eq 'up') {
        $ok = ($actual >= $expected_min);
    } elsif ($direction eq 'down') {
        $ok = ($actual <= -$expected_min);
    }
    if ($ok) {
        log_test("PASS: $desc ($before% -> $after%, delta $actual)");
        $passed++;
    } else {
        my $wanted = ($direction eq 'up') ? ">= +$expected_min" : "<= -$expected_min";
        log_test("FAIL: $desc ($before% -> $after%, expected $wanted, got $actual)");
        $failed++;
    }
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
    log_test("--- Volume end-to-end ---");

    unless (probe_amixer()) {
        log_test("FAIL: amixer / $VOLUME_CONTROL not available");
        $failed++;
        return;
    }

    $initial_volume = get_volume();
    unless (defined $initial_volume) {
        log_test("FAIL: could not read initial volume");
        $failed++;
        return;
    }
    log_test("initial volume is $initial_volume%");

    # A: volume up
    set_volume(50);
    my $before = get_volume();
    tap('A');
    my $after = get_volume();
    expect_volume_changed('A raises volume', $before, $after, $VOLUME_STEP, 'up');

    # B: volume down
    set_volume(50);
    $before = get_volume();
    tap('B');
    $after = get_volume();
    expect_volume_changed('B lowers volume', $before, $after, $VOLUME_STEP, 'down');

    if (defined $initial_volume) {
        set_volume($initial_volume);
        my $restored = get_volume() // '?';
        log_test("volume restored to $restored% (was $initial_volume%)");
    }

    log_test("--- Done. Passed: $passed / Failed: $failed ---");
}

run_tests();
exit($failed ? 1 : 0);
