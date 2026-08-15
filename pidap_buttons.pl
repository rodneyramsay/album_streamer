#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(usleep gettimeofday);
use IO::Select;
use FindBin;

use vars qw($VERSION);
$VERSION = '1.0';

my $LOG_FILE = $ENV{PIDAP_LOG_FILE} || '/tmp/pidap_buttons.log';
my $PID_FILE = $ENV{PIDAP_PID_FILE} || ($FindBin::Bin . '/pidap.generated.play_pid');
my $VOLUME_CONTROL = $ENV{PIDAP_VOLUME_CONTROL} || 'Amp';
my $VOLUME_STEP = $ENV{PIDAP_VOLUME_STEP} || 2;
my $LOCK_HOLD_SEC = $ENV{PIDAP_LOCK_HOLD_SEC} || 3.0;
my $GPIO_CHIP = $ENV{PIDAP_GPIO_CHIP} || '';

my @BUTTONS = (5, 6, 16, 24);
my @LABELS = ('A', 'B', 'X', 'Y');

my %PIN_TO_LABEL;
my %LABEL_TO_PIN;
for my $i (0 .. $#BUTTONS) {
    $PIN_TO_LABEL{$BUTTONS[$i]} = $LABELS[$i];
    $LABEL_TO_PIN{$LABELS[$i]} = $BUTTONS[$i];
}

my $DEFAULT_MAP = 'A:vol_up,B:vol_down,X:lock,Y:next_track';
my $BUTTON_MAP = parse_map($ENV{PIDAP_BUTTON_MAP} || $DEFAULT_MAP);

my $locked = 0;
my $x_armed = 0;
my $x_toggled = 0;
my %pressed = ();
my %press_time = ();
my %last_event = ();
my $combo_active_until = 0;
my $y_pending = 0;
my $WIRINGPI_FH = 0;
my $pidap_pid = 0;
my $last_play_pid = 0;
my $album_start = 0;

# Always use our own /proc-based kill function so we are sure to hit
# descendants of the play pid (Proc::Killfam without Proc::ProcessTable
# would only signal the top pid).
{ no strict 'refs'; *killfam = \&_killfam_fallback; }

open(my $LOG, '>>', $LOG_FILE) or warn "Cannot open log $LOG_FILE: $!";
$LOG->autoflush(1) if $LOG;
STDOUT->autoflush(1);
STDERR->autoflush(1);

sub log_msg {
    my ($msg) = @_;
    my ($sec, $usec) = gettimeofday();
    my $ts = localtime($sec);
    my $line = sprintf("[%s.%06d] %s", $ts, $usec, $msg);
    print "$line\n";
    if ($LOG) {
        print $LOG "$line\n";
    }
}

sub parse_map {
    my ($map_str) = @_;
    my %map;
    for my $part (split /,/, $map_str) {
        if ($part =~ /^\s*([A-DXY]):\s*(\w+)\s*$/) {
            $map{$1} = $2;
        }
    }
    return \%map;
}

sub start_wiringpi_interrupts {
    require WiringPi::API;

    log_msg('Initializing WiringPi GPIO (BCM numbering)');
    if (WiringPi::API::setup_gpio() < 0) {
        die "wiringPi setup failed";
    }

    for my $pin (@BUTTONS) {
        WiringPi::API::pin_mode($pin, WiringPi::API::INPUT());
        WiringPi::API::pull_up_down($pin, WiringPi::API::PUD_UP());

        my $cb = sub {
            my ($edge, $ts) = @_;
            my $now = Time::HiRes::time();
            if ($now - ($last_event{$pin} || 0) < 0.05) {
                return;
            }
            $last_event{$pin} = $now;
            my $label = $PIN_TO_LABEL{$pin};
            return unless defined $label;

            if ($edge == WiringPi::API::INT_EDGE_FALLING()) {
                handle_press($pin, $label);
            } else {
                handle_release($pin, $label);
            }
        };

        WiringPi::API::set_interrupt($pin, WiringPi::API::INT_EDGE_BOTH(), $cb);
    }

    my $fd = WiringPi::API::interrupt_fd();
    if ($fd < 0) {
        die "No WiringPi interrupt fd available";
    }
    open(my $fh, '<&', $fd) or die "Failed to duplicate interrupt fd: $!";
    $WIRINGPI_FH = $fh;
    $fh->autoflush(0);
    return $fh;
}

sub get_play_pid {
    my $pid = 0;
    if (open(my $pf, '<', $PID_FILE)) {
        my $line = <$pf>;
        close($pf);
        if (defined $line && $line =~ /(\d+)/) {
            $pid = int($1);
        }
    }
    return $pid;
}

sub _killfam_fallback {
    my ($sig, @pids) = @_;
    for my $pid (@pids) {
        next unless $pid;
        # Kill descendants first so they don't get reparented.
        my @children = _get_children($pid);
        _killfam_fallback($sig, @children);
        kill $sig, $pid;
    }
}

sub _get_children {
    my ($ppid) = @_;
    my @children;
    opendir(my $dh, '/proc') or return @children;
    while (my $entry = readdir($dh)) {
        next unless $entry =~ /^\d+$/;
        if (open(my $st, '<', "/proc/$entry/status")) {
            while (<$st>) {
                if (/^PPid:\s*(\d+)/) {
                    push @children, $entry if $1 == $ppid;
                    last;
                }
            }
            close($st);
        }
    }
    closedir($dh);
    return @children;
}

sub get_pid_parent {
    my ($pid) = @_;
    return 0 unless $pid && -r "/proc/$pid/status";
    if (open(my $st, '<', "/proc/$pid/status")) {
        while (<$st>) {
            if (/^PPid:\s*(\d+)/) {
                close($st);
                return int($1);
            }
        }
        close($st);
    }
    return 0;
}

sub get_process_cmdline {
    my ($pid) = @_;
    return '' unless $pid && -r "/proc/$pid/cmdline";
    if (open(my $c, '<', "/proc/$pid/cmdline")) {
        my $cmd = do { local $/; <$c> };
        close($c);
        return '' unless defined $cmd;
        $cmd =~ s/\0/ /g;
        return $cmd;
    }
    return '';
}

sub get_process_name {
    my ($pid) = @_;
    return '' unless $pid && -r "/proc/$pid/comm";
    if (open(my $c, '<', "/proc/$pid/comm")) {
        my $name = <$c>;
        close($c);
        return '' unless defined $name;
        chomp $name;
        return $name;
    }
    return '';
}

sub is_pidap {
    my ($pid) = @_;
    return 0 unless $pid && $pid > 1;
    my $name = get_process_name($pid);
    return 0 unless $name && ($name eq 'perl' || $name eq 'pidap');
    my $cmd = get_process_cmdline($pid);
    return ($cmd =~ /\bpidap\b/) ? 1 : 0;
}

sub init_pidap_pid {
    if (@ARGV && $ARGV[0] =~ /^\d+$/) {
        $pidap_pid = int($ARGV[0]);
        log_msg("Using pidap PID from command line: $pidap_pid");
        return;
    }
    my $ppid = getppid();
    if (is_pidap($ppid)) {
        $pidap_pid = $ppid;
        log_msg("Using pidap PID from parent: $pidap_pid");
        return;
    }
    log_msg('WARNING: not started by pidap and no pidap PID given; Y/B+Y signals disabled');
}

sub find_pidap_pid {
    return $pidap_pid || 0;
}

sub is_play_paused {
    my ($pid) = @_;
    return 0 unless $pid;
    if (open(my $st, '<', "/proc/$pid/stat")) {
        my $line = <$st>;
        close($st);
        if (defined $line && $line =~ /^\d+\s+\S+\s+(\S)/) {
            return ($1 eq 'T') ? 1 : 0;
        }
    }
    return 0;
}

sub toggle_pause {
    my $pid = get_play_pid();
    if (!$pid) {
        log_msg('No play process, cannot toggle pause');
        return;
    }
    if (is_play_paused($pid)) {
        log_msg('Resuming playback');
        killfam('CONT', $pid);
    } else {
        log_msg('Pausing playback');
        killfam('STOP', $pid);
    }
}

sub kill_play {
    my ($sig) = @_;
    my $pid = get_play_pid();
    if (!$pid) {
        log_msg('kill_play: no play pid');
        return;
    }
    log_msg("kill_play sig=$sig pid=$pid");
    my $sent = killfam($sig, $pid);
    log_msg("kill_play sent signal to $sent process(es)");
    if ($sent == 0) {
        log_msg("kill_play failed: $!");
    }
}

sub run_amixer {
    my ($direction) = @_;
    my $sign = ($direction eq 'up') ? '+' : '-';
    my $cmd = "amixer sset $VOLUME_CONTROL ${VOLUME_STEP}%${sign}";
    log_msg("Volume $direction: $cmd");
    my $out = qx{$cmd 2>&1};
    my $rc = $? >> 8;
    chomp $out if defined $out;
    log_msg("amixer rc=$rc out=$out");
}

sub next_album {
    log_msg('Next album');
    kill_play(9);
    $combo_active_until = time + 0.3;
}

sub next_track {
    log_msg('Next track: sending SIGUSR1 to pidap');
    my $pidap_pid = find_pidap_pid();
    if ($pidap_pid) {
        kill 'USR1', $pidap_pid;
    } else {
        log_msg('No pidap to signal');
    }
}

sub previous_album {
    log_msg('Previous album');
    my $flag_file = $PID_FILE;
    $flag_file =~ s/[^\/]+$//;
    $flag_file .= '/' if $flag_file && $flag_file !~ m|/$|;
    $flag_file .= 'pidap.generated.previous';
    if (open(my $rf, '>', $flag_file)) {
        print $rf "1\n";
        close($rf);
    } else {
        log_msg("Could not write previous flag: $!");
    }
    kill_play(9);
    $combo_active_until = time + 0.3;
}

sub read_current_album {
    my $cf = $PID_FILE;
    $cf =~ s/[^\/]+$//;
    $cf .= '/' if $cf && $cf !~ m|/$|;
    $cf .= 'pidap.generated.current_album';
    my ($album, $offset, @files, @durations);
    if (open(my $f, '<', $cf)) {
        while (<$f>) {
            chomp;
            if (/^album=(.+)/) {
                $album = $1;
            } elsif (/^offset=([0-9.]+)/) {
                $offset = $1;
            } elsif (/^track:(\d+):([0-9.]+)=(.+)/) {
                my ($idx, $dur, $path) = ($1, $2, $3);
                $files[$idx] = $path;
                $durations[$idx] = $dur;
            }
        }
        close($f);
    }
    return ($album, $offset, \@files, \@durations, $cf);
}

sub current_track_info {
    my ($album, $start_offset, $files, $durations) = read_current_album();
    return undef unless $album && @$durations;
    my $total = 0;
    $total += $_ for @$durations;
    my $now = Time::HiRes::time();
    my $start = $album_start || $now;
    my $elapsed = $now - $start;
    $elapsed = 0 if $elapsed < 0;
    if ($elapsed >= $total) {
        my $i = $#$durations;
        my $track_start = $total - $durations->[$i];
        return [$i, 0.0, $track_start];
    }
    my $cum = 0;
    for my $i (0 .. $#$durations) {
        $cum += $durations->[$i];
        if ($cum > $elapsed) {
            my $track_time = $elapsed - ($cum - $durations->[$i]);
            my $track_start = $cum - $durations->[$i];
            return [$i, $track_time, $track_start];
        }
    }
    my $i = $#$durations;
    my $track_start = $total - $durations->[$i];
    return [$i, 0.0, $track_start];
}

sub previous_or_restart {
    my $pidap_pid = find_pidap_pid();
    log_msg("Previous/restart: sending SIGUSR2 to pidap pid=$pidap_pid");
    if ($pidap_pid) {
        kill 'USR2', $pidap_pid;
    } else {
        log_msg('No pidap to signal');
    }
}

sub restart_album {
    my ($offset) = @_;
    $offset ||= 0;
    my $pid = get_play_pid();
    if (!$pid) {
        log_msg('Restart album: no play pid');
        return;
    }
    my $flag_file = $PID_FILE;
    $flag_file =~ s/[^\/]+$//;
    $flag_file .= '/' if $flag_file && $flag_file !~ m|/$|;
    $flag_file .= 'pidap.generated.restart';
    log_msg("Writing restart flag: $flag_file");
    if (open(my $rf, '>', $flag_file)) {
        if ($offset > 0) {
            print $rf "offset=$offset\n";
        } else {
            print $rf "1\n";
        }
        close($rf);
    } else {
        log_msg("Could not write restart flag: $!");
    }
    kill_play(9);
    $combo_active_until = time + 0.3;
}

sub toggle_lock {
    $locked = !$locked;
    log_msg($locked ? 'Locked' : 'Unlocked');
}

sub is_pressed {
    my ($label) = @_;
    return $pressed{$label} ? 1 : 0;
}

sub handle_press {
    my ($pin, $label) = @_;
    $pressed{$label} = 1;
    $press_time{$label} = Time::HiRes::time();

    my $func = $BUTTON_MAP->{$label};
    log_msg("Button $label pressed, func=$func");

    if ($func eq 'lock') {
        $x_armed = 1;
        $x_toggled = 0;
        return;
    }

    if ($locked) {
        log_msg("Button $label ignored (locked)");
        return;
    }

    if ($func eq 'next_track' || $func eq 'next') {
        if (is_pressed('A')) {
            next_album();
        } elsif (is_pressed('B')) {
            previous_or_restart();
        } elsif ($func eq 'next_track') {
            $y_pending = 1;
        } else {
            next_album();
        }
        return;
    }

    if ($func eq 'vol_up' || $func eq 'vol_down') {
        if ($y_pending) {
            if ($func eq 'vol_up') {
                next_album();
            } else {
                previous_or_restart();
            }
            $y_pending = 0;
            return;
        }
        # Volume is applied on release unless a combo fired.
        return;
    }

    log_msg("Unknown function $func for button $label");
}

sub handle_release {
    my ($pin, $label) = @_;
    $pressed{$label} = 0;

    my $func = $BUTTON_MAP->{$label};

    if ($func eq 'lock') {
        if (!$x_toggled && !$locked) {
            toggle_pause();
        }
        $x_armed = 0;
        $x_toggled = 0;
        return;
    }

    if (time < $combo_active_until) {
        log_msg("Button $label release ignored (combo active)");
        return;
    }

    if (is_pressed('Y')) {
        log_msg("Button $label release ignored (Y held)");
        return;
    }

    if ($locked) {
        return;
    }

    if ($func eq 'next_track' && $y_pending) {
        next_track();
        $y_pending = 0;
        return;
    }

    if ($func eq 'vol_up') {
        run_amixer('up');
    } elsif ($func eq 'vol_down') {
        run_amixer('down');
    }
}

sub check_lock_timeout {
    return unless $x_armed && !$x_toggled;
    return unless $pressed{'X'};
    my $elapsed = Time::HiRes::time() - $press_time{'X'};
    if ($elapsed >= $LOCK_HOLD_SEC) {
        $x_toggled = 1;
        toggle_lock();
    }
}

sub check_parent {
    my $ppid = getppid();
    if ($ppid == 1) {
        log_msg('Parent gone, exiting');
        cleanup();
        exit(0);
    }
}

sub check_play_pid {
    my $pid = get_play_pid();
    return unless $pid;
    if ($pid != $last_play_pid) {
        $last_play_pid = $pid;
        my @ra = read_current_album();
        my $offset = $ra[1] || 0;
        $album_start = Time::HiRes::time() - $offset;
        log_msg("New play pid $pid, album_start set to $album_start (offset $offset)");
    }
}

sub cleanup {
    if ($WIRINGPI_FH) {
        close($WIRINGPI_FH);
        $WIRINGPI_FH = 0;
    }
    if ($INC{'WiringPi/API.pm'}) {
        WiringPi::API::stop_interrupts();
    }
}

sub handle_signal {
    my ($sig) = @_;
    log_msg("Caught $sig, cleaning up");
    cleanup();
    exit(0);
}

$SIG{INT} = \&handle_signal;
$SIG{TERM} = \&handle_signal;
$SIG{HUP} = 'IGNORE';

log_msg("pidap_buttons.pl starting, PID=$$");
log_msg("Button map: " . join(',', map { "$_." . ($BUTTON_MAP->{$_} || '') } @LABELS));

my $wiringpi_fh = start_wiringpi_interrupts();
my $sel = IO::Select->new($wiringpi_fh);

init_pidap_pid();

while (1) {
    check_parent();
    check_lock_timeout();

    my @ready = $sel->can_read(0.05);
    if (@ready) {
        WiringPi::API::dispatch_interrupts();
    }
}

exit(0);
