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
my $PID_FILE = $ENV{PIDAP_PID_FILE} || ($FindBin::Bin . '/pidap.play_pid');
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
my $gpiomon_pid = 0;

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

sub find_gpio_chip {
    return $GPIO_CHIP if $GPIO_CHIP;

    my $chip = '/dev/gpiochip0';
    my @chips;
    if (open(my $gd, '-|', 'gpiodetect')) {
        while (<$gd>) {
            chomp;
            if (/^(\S+)\s+.*\((\d+)\s*lines\)/) {
                push @chips, { name => $1, lines => $2 };
            }
        }
        close($gd);
    }
    if (@chips) {
        # Prefer the SoC chip: most lines, or name containing bcm/pinctrl.
        @chips = sort {
            my $aa = ($a->{name} =~ /bcm|pinctrl/i) ? 1 : 0;
            my $bb = ($b->{name} =~ /bcm|pinctrl/i) ? 1 : 0;
            $bb <=> $aa || $b->{lines} <=> $a->{lines}
        } @chips;
        $chip = '/dev/' . $chips[0]{name};
    }
    return $chip;
}

sub start_gpiomon {
    my $chip = find_gpio_chip();
    log_msg("Using GPIO chip: $chip");

    my @cmd = (
        'gpiomon',
        '--bias=pull-up',
        $chip,
        @BUTTONS,
    );

    my $pid = open(my $fh, '-|', @cmd);
    if (!defined $pid) {
        # Try without bias if the tool/kernel doesn't support it.
        log_msg('gpiomon with --bias failed, trying without bias');
        @cmd = (
            'gpiomon',
            $chip,
            @BUTTONS,
        );
        $pid = open(my $fh2, '-|', @cmd);
        if (!defined $pid) {
            die "Failed to start gpiomon: $!";
        }
        $fh = $fh2;
    }

    $gpiomon_pid = $pid;
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
    log_msg("PID file $PID_FILE -> play pid=$pid") if $pid;
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
    log_msg('Next track');
    kill_play(2);
}

sub restart_album {
    my $pid = get_play_pid();
    if (!$pid) {
        log_msg('Restart album: no play pid');
        return;
    }
    my $flag_file = $PID_FILE;
    $flag_file =~ s/[^\/]+$//;
    $flag_file .= '/' if $flag_file && $flag_file !~ m|/$|;
    $flag_file .= 'pidap.restart';
    log_msg("Writing restart flag: $flag_file");
    if (open(my $rf, '>', $flag_file)) {
        print $rf "1\n";
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
            restart_album();
        } elsif ($func eq 'next_track') {
            next_track();
        } else {
            next_album();
        }
        return;
    }

    if ($func eq 'vol_up' || $func eq 'vol_down') {
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

sub cleanup {
    if ($gpiomon_pid) {
        kill 'TERM', $gpiomon_pid;
        waitpid($gpiomon_pid, 0);
        $gpiomon_pid = 0;
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

my $gpiomon_fh = start_gpiomon();
my $sel = IO::Select->new($gpiomon_fh);

while (1) {
    check_parent();
    check_lock_timeout();

    my @ready = $sel->can_read(0.05);
    if (@ready) {
        my $line = <$gpiomon_fh>;
        if (!defined $line) {
            # EOF: gpiomon exited.
            log_msg('gpiomon closed output, exiting');
            cleanup();
            exit(1);
        }
        chomp $line;
        log_msg("gpiomon: $line") if $ENV{PIDAP_DEBUG};

        # Parse "event: FALLING EDGE offset: 5 timestamp: [...]"
        if ($line =~ /(RISING|FALLING).*?offset:\s*(\d+)/i) {
            my $edge = lc $1;
            my $pin = int($2);
            my $label = $PIN_TO_LABEL{$pin};
            next unless defined $label;

            my $now = Time::HiRes::time();
            if ($now - ($last_event{$pin} || 0) < 0.05) {
                next;
            }
            $last_event{$pin} = $now;

            if ($edge eq 'falling') {
                handle_press($pin, $label);
            } else {
                handle_release($pin, $label);
            }
        }
    }

    # Reap gpiomon if it died unexpectedly.
    my $dead = waitpid($gpiomon_pid, WNOHANG);
    if ($dead == $gpiomon_pid) {
        log_msg("gpiomon exited (rc=$?)");
        exit(1);
    }
}

exit(0);
