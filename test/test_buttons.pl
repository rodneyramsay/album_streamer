#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Time::HiRes qw(sleep time);
use POSIX ":sys_wait_h";
use IPC::Open3;
use IO::Select;
use IO::Handle;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $ROOT = abs_path(dirname($FindBin::Bin));
my $PIDAP       = "$ROOT/pidap";
my $PIDAP_BUTTONS = "$ROOT/pidap_buttons.pl";
chdir($ROOT) or die "chdir $ROOT: $!";

my $TMP   = tempdir('pidap_test_XXXX', CLEANUP => 1, TMPDIR => 1);
my $MUSIC = "$TMP/music";
my $LOG   = "$TMP/pidap_buttons.log";

my %PIN = (A => 5, B => 6, X => 16, Y => 24);
my $HOLD          = 0.15;
my $COMBO_HOLD    = 0.30;
my $LONG_PRESS    = 3.20;
my $INTER_GAP     = 0.05;
my $POST_EVENT    = 0.50;

my ($pidap_in, $pidap_out, $pidap_err, $pidap_pid);
my $pidap_out_buf = '';
my $pidap_err_buf = '';
my $current_play_pid = 0;
my $passed = 0;
my $failed = 0;

$SIG{INT} = $SIG{TERM} = sub { cleanup(); exit(1); };

sub log_test {
    my ($msg) = @_;
    print "[TEST] $msg\n";
}

sub make_music {
    my @cats = ('rock', 'jazz');
    my @artists = ('ArtistA', 'ArtistB');
    my @albums = ('Album1', 'Album2');
    for my $c (@cats) {
        for my $a (@artists) {
            for my $alb (@albums) {
                my $dir = "$MUSIC/$c/$a/$alb";
                system('mkdir', '-p', $dir) == 0 or die "mkdir: $!";
                for my $t (1 .. 3) {
                    my $f = "$dir/track0$t.flac";
                    system('sox', '-n', '-r', '44100', '-c', '2', $f, 'synth', '1', 'sine', '1000') == 0
                        or die "sox failed: $?";
                }
            }
        }
    }
    my $count = () = glob("$MUSIC/*/*/*/*.flac");
    log_test("generated $count flac files under $MUSIC");
}

sub start_pidap {
    local $ENV{PIDAP_FAKE_GPIO}       = 1;
    local $ENV{PIDAP_LOG_FILE}        = $LOG;
    local $ENV{PIDAP_VOLUME_CONTROL}  = 'DummyControl';
    local $ENV{PIDAP_VOLUME_STEP}     = 1;
    local $ENV{PIDAP_BUTTON_MAP}      = 'A:vol_up,B:vol_down,X:lock,Y:next_track';

    $pidap_pid = open3($pidap_in, $pidap_out, $pidap_err, 'perl', $PIDAP, '-m', $MUSIC, '-q');
    die "open3 pidap: $!" unless $pidap_pid;
    $pidap_in->autoflush(1);
    $pidap_out->blocking(0);
    $pidap_err->blocking(0);
    log_test("real pidap started pid=$pidap_pid");
}

sub slurp_log {
    return '' unless -r $LOG;
    open(my $fh, '<', $LOG) or return '';
    local $/;
    my $txt = <$fh>;
    close($fh);
    return $txt // '';
}


sub wait_for_log {
    my ($pattern, $timeout) = @_;
    my $start = time();
    while (time() - $start < $timeout) {
        my $log = slurp_log();
        return $1 if $log =~ /($pattern)/s;
        sleep(0.05);
    }
    return undef;
}

sub expect_log {
    my ($desc, $pattern, $timeout) = @_;
    my $res = wait_for_log($pattern, $timeout // 2.0);
    if ($res) {
        log_test("PASS: $desc (saw '$res')");
        $passed++;
    } else {
        log_test("FAIL: $desc (pattern '$pattern' not found)");
        $failed++;
    }
}

sub drain_pidap {
    my $sel = IO::Select->new($pidap_out, $pidap_err);
    while (my @ready = $sel->can_read(0.05)) {
        for my $fh (@ready) {
            my $buf;
            my $n = sysread($fh, $buf, 4096);
            next unless $n;
            if ($fh == $pidap_out) { $pidap_out_buf .= $buf; }
            else                   { $pidap_err_buf .= $buf; }
        }
    }
}

sub wait_for_pidap_out {
    my ($pattern, $timeout) = @_;
    my $start = time();
    while (time() - $start < $timeout) {
        drain_pidap();
        if ($pidap_out_buf =~ /($pattern)/s) {
            $pidap_out_buf = $' if $';
            return $1;
        }
        sleep(0.05);
    }
    drain_pidap();
    if ($pidap_out_buf =~ /($pattern)/s) {
        $pidap_out_buf = $' if $';
        return $1;
    }
    return undef;
}

sub expect_pidap_out {
    my ($desc, $pattern, $timeout) = @_;
    my $res = wait_for_pidap_out($pattern, $timeout // 5.0);
    if ($res) {
        log_test("PASS: $desc (pidap output '$res')");
        $passed++;
    } else {
        log_test("FAIL: $desc (pattern '$pattern' not in pidap output)");
        $failed++;
    }
}

sub read_play_pid {
    my $file = "$ROOT/pidap.generated.play_pid";
    for my $i (1 .. 30) {
        last if -r $file;
        sleep(0.05);
    }
    open(my $fh, '<', $file) or return 0;
    my $line = <$fh>;
    close($fh);
    return 0 unless defined $line && $line =~ /(\d+)/;
    return int($1);
}

sub wait_play_pid {
    my $pid;
    for my $i (1 .. 30) {
        $pid = read_play_pid();
        return $pid if $pid;
        sleep(0.05);
    }
    return 0;
}

sub play_is_alive {
    my ($pid) = @_;
    return 0 unless $pid;
    return kill(0, $pid) > 0;
}

sub play_state {
    my ($pid) = @_;
    return '' unless $pid;
    open(my $fh, '<', "/proc/$pid/status") or return '';
    my $state = '';
    while (<$fh>) {
        if (/^State:\s*(\S)/) { $state = $1; last; }
    }
    close($fh);
    return $state;
}

sub wait_for_play {
    my $pid = wait_play_pid();
    if ($pid && play_is_alive($pid)) {
        $current_play_pid = $pid;
        return 1;
    }
    return 0;
}

sub expect_play_alive {
    my ($desc) = @_;
    if (play_is_alive($current_play_pid)) {
        log_test("PASS: $desc (play $current_play_pid alive)");
        $passed++;
    } else {
        log_test("FAIL: $desc (play not alive)");
        $failed++;
    }
}

sub expect_play_killed {
    my ($desc) = @_;
    for my $i (1 .. 20) {
        last unless play_is_alive($current_play_pid);
        sleep(0.05);
    }
    if (!play_is_alive($current_play_pid)) {
        log_test("PASS: $desc (play killed)");
        $passed++;
    } else {
        log_test("FAIL: $desc (play still alive)");
        $failed++;
    }
}

sub send_edge {
    my ($label, $edge) = @_;
    my $pin = $PIN{$label} // die "unknown label $label";
    print $pidap_in "$pin $edge\n";
    $pidap_in->flush;
}

sub press   { my ($l) = @_; send_edge($l, 'falling'); }
sub release { my ($l) = @_; send_edge($l, 'rising'); }

sub tap {
    my ($l) = @_;
    press($l);
    sleep($HOLD);
    release($l);
    sleep($POST_EVENT);
}

sub combo {
    my (@labels) = @_;
    for my $i (0 .. $#labels) {
        sleep($INTER_GAP) if $i > 0;
        press($labels[$i]);
    }
    sleep($COMBO_HOLD);
    for my $i (0 .. $#labels) {
        sleep($INTER_GAP) if $i > 0;
        release($labels[$#labels - $i]);
    }
    sleep($POST_EVENT);
}

sub long_press {
    my ($l) = @_;
    press($l);
    sleep($LONG_PRESS);
    release($l);
    sleep($POST_EVENT);
}

sub cleanup {
    if ($pidap_in) { close($pidap_in); $pidap_in = undef; }
    if ($pidap_pid) {
        kill('TERM', $pidap_pid);
        waitpid($pidap_pid, WNOHANG);
    }
    for my $f (glob("$ROOT/pidap.generated.*")) {
        unlink($f) if -f $f;
    }
}

sub wait_for_initial_play {
    log_test("waiting for pidap to start first album...");
    expect_pidap_out('initial album', 'Album Name\(\d+\):\s*\S+', 10.0);
    wait_for_play() or die "play did not start";
    log_test("play started pid=$current_play_pid");
}

# -------------------- tests --------------------

sub run_tests {
    make_music();
    start_pidap();
    wait_for_initial_play();

    log_test("--- Test 1: Y next track ---");
    tap('Y');
    expect_log('Y => next track', 'Next track: sending SIGUSR1', 2.0);
    expect_play_killed('Y kills current play');
    wait_for_play();

    log_test("--- Test 2: A+X next track ---");
    tap('A');
    # ignore vol_up log from the A tap, then A+X combo
    sleep(0.3);
    combo('A', 'X');
    expect_log('A+X => next track', 'Next track: sending SIGUSR1', 2.0);
    expect_play_killed('A+X kills current play');
    wait_for_play();

    log_test("--- Test 3: A+Y next album ---");
    my $before = $pidap_out_buf;
    combo('A', 'Y');
    expect_log('A+Y => next album', 'Next album', 2.0);
    expect_play_killed('A+Y kills play');
    expect_pidap_out('A+Y changed album', 'Album Name\(\d+\):\s*\S+', 5.0);
    wait_for_play();

    log_test("--- Test 4: B+Y previous album ---");
    combo('B', 'Y');
    expect_log('B+Y => SIGUSR2', 'Previous/restart: sending SIGUSR2', 2.0);
    expect_play_killed('B+Y kills play');
    expect_pidap_out('B+Y changed album', 'Album Name\(\d+\):\s*\S+', 5.0);
    wait_for_play();

    log_test("--- Test 5: B+X previous track ---");
    # wait a moment to be inside track 1 (within 5s)
    sleep(0.5);
    combo('B', 'X');
    expect_log('B+X => previous track', 'Previous track flag', 2.0);
    expect_play_killed('B+X kills play');
    wait_for_play();

    log_test("--- Test 6: X short press pause ---");
    tap('X');
    expect_log('X short => toggle pause', 'Toggling pause', 2.0);
    # wait a bit then check play is paused (state T)
    sleep(0.2);
    my $state = play_state($current_play_pid);
    if ($state eq 'T') {
        log_test("PASS: play process is paused (state T)");
        $passed++;
    } else {
        log_test("FAIL: play process not paused (state=$state)");
        $failed++;
    }
    # tap X again to resume
    tap('X');
    sleep(0.2);
    $state = play_state($current_play_pid);
    if ($state ne 'T') {
        log_test("PASS: play process resumed");
        $passed++;
    } else {
        log_test("FAIL: play process still paused after resume");
        $failed++;
    }

    log_test("--- Test 7: X long press lock ---");
    long_press('X');
    expect_log('X long => lock', 'Lock toggled', 5.0);
    # volume should still work when locked
    tap('A');
    expect_log('A while locked => vol up', 'Volume up', 2.0);
    # unlock
    long_press('X');
    expect_log('X long => unlock', 'Lock toggled', 5.0);

    log_test("--- Test 8: random stress ---");
    my @pool = ('A', 'B', 'X', 'Y', ['A','X'], ['B','X'], ['A','Y'], ['B','Y']);
    for my $i (1 .. 8) {
        my $ev = $pool[int(rand(@pool))];
        if (ref $ev) { combo(@$ev); } else { tap($ev); }
        sleep(0.2);
        if (!play_is_alive($current_play_pid)) {
            wait_for_play();
        }
    }
    if (play_is_alive($current_play_pid) || wait_for_play()) {
        log_test("PASS: random sequence completed without losing play");
        $passed++;
    } else {
        log_test("FAIL: play did not survive random sequence");
        $failed++;
    }

    log_test("--- Done. Passed: $passed / Failed: $failed ---");
}

run_tests();
cleanup();
exit($failed ? 1 : 0);
