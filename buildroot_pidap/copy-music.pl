#!/usr/bin/perl
#
# Copy music to the PIDAP Pi with sorted tar streaming over SSH.
# Uses chacha20-poly1305 (faster on Pi Zero) and no compression.
#
# Usage:
#   copy-music.pl <src-path> [<target-parent>]
#
# Examples:
#   copy-music.pl /mnt/wd_my_cloud/Music/Vinyl
#     -> copied to /usr/local/Music/Vinyl on the Pi
#
#   PIDAP_COPY_VERBOSE=1 copy-music.pl /mnt/wd_my_cloud/Music/Vinyl
#     -> lists each file as it is copied, in addition to the rate meter
#
#   copy-music.pl /mnt/wd_my_cloud/Music /usr/local
#     -> copied to /usr/local/Music on the Pi (whole music tree)

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);

my $host = $ENV{PIDAP_HOST} // 'root@192.168.0.31';
my $default_target = '/usr/local/Music';
my $verbose = $ENV{PIDAP_COPY_VERBOSE} // 0;
my $rate_limit = $ENV{PIDAP_COPY_LIMIT} // '';
my $stop_pidap = $ENV{PIDAP_COPY_STOP} // 0;

if (@ARGV < 1 || @ARGV > 2) {
    print STDERR "Usage: $0 <src-path> [<target-parent>]\n";
    print STDERR "Default target parent is $default_target\n";
    print STDERR "Set PIDAP_COPY_VERBOSE=1 to list every file\n";
    print STDERR "Set PIDAP_COPY_LIMIT=2m to cap throughput (e.g. 2m, 5m)\n";
    print STDERR "Set PIDAP_COPY_STOP=1 to stop pidap during the copy\n";
    exit 1;
}

my $src = $ARGV[0];
my $target_parent = $ARGV[1] // $default_target;

unless (-e $src) {
    die "ERROR: source does not exist: $src\n";
}

my $src_dir = dirname(abs_path($src));
my $src_base = basename($src);

my $ssh_opts = q{-o Ciphers=chacha20-poly1305@openssh.com -o Compression=no};

# Use pv for a rate meter if it is installed on the host.
my $has_pv = (system('command -v pv >/dev/null 2>&1') == 0);

# tar create options:
#  --sort=name    reproducible/ordered archive
#  -C             source directory
#  -c             create
#  -h             follow symlinks
#  -v             list files (with PIDAP_COPY_VERBOSE)
#  -f -           write archive to stdout
my $tar_opts = '--sort=name -C ' . qshell($src_dir) . ' -ch' . ($verbose ? 'v' : '') . 'f - ' . qshell($src_base);

# Remote tar extract.
my $remote_tar = "tar -C " . qshell($target_parent) . " -x" . ($verbose ? 'v' : '') . "f -";

print "Copying $src_dir/$src_base to ${host}:${target_parent}/$src_base ...\n";

# Stop pidap during the copy if requested (less CPU / DMA contention).
if ($stop_pidap) {
    my $stop_cmd = "ssh $ssh_opts " . qshell($host) . " "
                 . qshell("killall pidap pidap-menu pidap-buttons pidap-playlist 2>/dev/null; /etc/init.d/S99pidap stop 2>/dev/null || true");
    system($stop_cmd);
    print "pidap stopped for copy\n";
}

# Sync the Pi's clock to the host before the copy so extracted files
# do not get "time stamp in the future" warnings.
my $epoch = qx{date -u +%s};
chomp($epoch) if $epoch;
if ($epoch =~ /^\d+$/) {
    my $remote_cmd = q{date -u -s @} . $epoch;
    my $sync_cmd = "ssh $ssh_opts " . qshell($host) . " " . qshell($remote_cmd);
    my $sync_rc = system($sync_cmd);
    print "Pi time synced to epoch $epoch UTC\n" if $sync_rc == 0;
}

my $cmd;
if ($has_pv) {
    my $pv_opts = '-i 2 -trb';
    $pv_opts .= ' -L ' . $rate_limit if $rate_limit =~ /^\d+[kmKM]?$/;
    $cmd = "tar $tar_opts | pv $pv_opts | ssh $ssh_opts " . qshell($host) . " " . qshell($remote_tar);
    print "Rate meter: pv" . ($rate_limit ? " (limit $rate_limit)" : '') . "\n";
} else {
    $cmd = "tar $tar_opts | ssh $ssh_opts " . qshell($host) . " " . qshell($remote_tar);
    print "(install 'pv' on this host to see transfer rate)\n";
}

my $rc = system($cmd);
if ($rc != 0) {
    restart_pidap() if $stop_pidap;
    die "ERROR: copy failed (exit $rc)\n";
}

restart_pidap() if $stop_pidap;
print "Done.\n";

sub restart_pidap {
    my $start_cmd = "ssh $ssh_opts " . qshell($host) . " "
                  . qshell("/etc/init.d/S99pidap start 2>/dev/null || true");
    system($start_cmd);
    print "pidap restarted\n";
}

# Very simple shell-quoting helper: wraps strings in single quotes and
# escapes any embedded single quotes.
sub qshell {
    my ($s) = @_;
    $s =~ s/'/'\''/g;
    return "'$s'";
}
