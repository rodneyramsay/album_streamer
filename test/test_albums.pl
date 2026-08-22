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

my ($initial_album, $initial_offset);

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

sub play_is_alive {
    my ($pid) = @_;
    return 0 unless $pid;
    return kill(0, $pid) != 0;
}

sub wait_for_play {
    my ($timeout) = @_;
    my $end = Time::HiRes::time() + $timeout;
    while (Time::HiRes::time() < $end) {
        my $pid = play_pid();
        return $pid if $pid && play_is_alive($pid);
        sleep(0.05);
    }
    return 0;
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

sub combo {
    my ($a, $b) = @_;
    press($a);
    sleep(0.05);
    press($b);
    sleep($HOLD);
    release($b);
    sleep(0.05);
    release($a);
    sleep($POST_EVENT);
}

sub wait_for_pid_change {
    my ($before, $timeout) = @_;
    my $end = Time::HiRes::time() + $timeout;
    while (Time::HiRes::time() < $end) {
        my $pid = play_pid();
        return $pid if $pid && $pid != $before && play_is_alive($pid);
        sleep(0.05);
    }
    return 0;
}

sub read_playlist {
    my @albums;
    my $file = "$ROOT/pidap.generated.playlist";
    return @albums unless -r $file;
    open(my $fh, '<', $file) or return @albums;
    while (<$fh>) {
        chomp;
        next unless $_;
        if (m/^\s*(?:CUESHEET:\s*)?\d+\s+(.+)$/) {
            push @albums, $1;
        } elsif (m/^(.+)$/) {
            push @albums, $1;
        }
    }
    close($fh);
    return @albums;
}

sub read_current_album {
    my ($album, $offset) = ('', 0);
    my $file = "$RUN_DIR/pidap.generated.current_album";
    return ($album, $offset) unless -r $file;
    open(my $fh, '<', $file) or return ($album, $offset);
    while (<$fh>) {
        chomp;
        $album = $1 if (/^album=(.+)/);
        $offset = $1 if (/^offset=([0-9.]+)/);
    }
    close($fh);
    return ($album, $offset);
}

sub album_index {
    my ($path, $albums) = @_;
    for my $i (0 .. $#$albums) {
        return $i if $albums->[$i] eq $path;
    }
    return -1;
}

sub record_starting_position {
    ($initial_album, $initial_offset) = read_current_album();
    log_test("starting on album [$initial_album] offset $initial_offset");
    return if $initial_album;
    log_test("FAIL: could not read starting album");
    $failed++;
}

sub restore_player {
    log_test("--- restore player to starting position ---");

    my @playlist = read_playlist();
    unless (@playlist) {
        log_test("FAIL: could not read playlist; cannot restore");
        $failed++;
        return;
    }

    my $initial_i = album_index($initial_album, \@playlist);
    if ($initial_i < 0) {
        log_test("FAIL: starting album not in playlist; cannot restore");
        $failed++;
        return;
    }

    my ($current_album, $current_offset) = read_current_album();
    my $current_i = album_index($current_album, \@playlist);
    if ($current_i < 0) {
        log_test("FAIL: current album not in playlist; cannot restore");
        $failed++;
        return;
    }

    my $steps = ($initial_i - $current_i + @playlist) % @playlist;
    for my $s (1 .. $steps) {
        my $before = play_pid();
        combo('A', 'Y');
        my $after = wait_for_pid_change($before, 5.0);
        unless ($after) {
            log_test("FAIL: A+Y did not change play process on step $s");
            $failed++;
            return;
        }
    }

    my $restart_file = "$RUN_DIR/pidap.generated.restart";
    if (open(my $rf, '>', $restart_file)) {
        print $rf "offset=$initial_offset\n";
        close($rf);
    } else {
        log_test("FAIL: could not write restart file");
        $failed++;
        return;
    }

    my $pid = play_pid();
    if ($pid) {
        kill(9, $pid);
    } else {
        log_test("FAIL: no play pid to restart");
        $failed++;
        return;
    }

    my $after = wait_for_pid_change($pid, 5.0);
    unless ($after) {
        log_test("FAIL: did not restart after kill");
        $failed++;
        return;
    }

    my ($restored_album, $restored_offset) = read_current_album();
    if ($restored_album eq $initial_album && abs($restored_offset - $initial_offset) < 1.0) {
        log_test("PASS: restored to starting album and offset");
        $passed++;
    } else {
        log_test("FAIL: restored album [$restored_album] offset $restored_offset, expected [$initial_album] offset $initial_offset");
        $failed++;
    }
}

sub album_change_passes {
    my ($label, $before, $after, $before_idx, $after_idx) = @_;
    if ($before ne $after) {
        log_test("PASS: $label changed album ($before_idx -> $after_idx)");
        $passed++;
    } else {
        log_test("FAIL: $label did not change play process");
        $failed++;
    }
}

sub run_tests {
    log_test("--- Album navigation end-to-end ---");

    my $pid = wait_for_play(5.0);
    unless ($pid) {
        log_test("FAIL: no live play pid; is pidap running?");
        $failed++;
        return;
    }
    log_test("play pid is $pid, state " . play_state($pid));

    record_starting_position();

    my @playlist = read_playlist();
    my ($before_album, $before_offset) = read_current_album();
    my $before_i = album_index($before_album, \@playlist);

    # A+Y -- next album
    log_test("--- A+Y next album ---");
    my $ppid = play_pid();
    combo('A', 'Y');
    my $new_pid = wait_for_pid_change($ppid, 5.0);
    my ($after_album, $after_offset) = read_current_album();
    my $after_i = album_index($after_album, \@playlist);
    if ($new_pid) {
        log_test("PASS: A+Y changed album ($before_i -> $after_i)");
        $passed++;
    } else {
        log_test("FAIL: A+Y did not change play process");
        $failed++;
    }

    # A+Y -- next album again
    log_test("--- A+Y next album again ---");
    $before_album = $after_album;
    $before_i = $after_i;
    $ppid = play_pid();
    combo('A', 'Y');
    $new_pid = wait_for_pid_change($ppid, 5.0);
    ($after_album, $after_offset) = read_current_album();
    $after_i = album_index($after_album, \@playlist);
    if ($new_pid) {
        log_test("PASS: A+Y changed album ($before_i -> $after_i)");
        $passed++;
    } else {
        log_test("FAIL: A+Y did not change play process");
        $failed++;
    }

    # B+Y -- previous album
    log_test("--- B+Y previous album ---");
    $before_album = $after_album;
    $before_i = $after_i;
    $ppid = play_pid();
    combo('B', 'Y');
    $new_pid = wait_for_pid_change($ppid, 5.0);
    ($after_album, $after_offset) = read_current_album();
    $after_i = album_index($after_album, \@playlist);
    if ($new_pid) {
        log_test("PASS: B+Y changed album ($before_i -> $after_i)");
        $passed++;
    } else {
        log_test("FAIL: B+Y did not change play process");
        $failed++;
    }

    # B+Y -- previous album again
    log_test("--- B+Y previous album again ---");
    $before_album = $after_album;
    $before_i = $after_i;
    $ppid = play_pid();
    combo('B', 'Y');
    $new_pid = wait_for_pid_change($ppid, 5.0);
    ($after_album, $after_offset) = read_current_album();
    $after_i = album_index($after_album, \@playlist);
    if ($new_pid) {
        log_test("PASS: B+Y changed album ($before_i -> $after_i)");
        $passed++;
    } else {
        log_test("FAIL: B+Y did not change play process");
        $failed++;
    }

    restore_player();

    log_test("--- Done. Passed: $passed / Failed: $failed ---");
}

run_tests();
exit($failed ? 1 : 0);
