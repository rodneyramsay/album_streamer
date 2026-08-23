package PIDAPAlbum;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(
    get_album_offsets
    soxi_duration
    write_current_album
    read_current_album
    build_resume_cmd
);

our %EXPORT_TAGS = (all => \@EXPORT_OK);

my %ALBUM_OFFSETS_CACHE = ();

sub soxi_duration {
    my ($file) = @_;
    my $out = `soxi -D "$file" 2>/dev/null`;
    return 0 unless defined $out && $out =~ /^([0-9.]+)/;
    return $1 + 0;
}

sub get_album_offsets {
    my ($album) = @_;
    return @{$ALBUM_OFFSETS_CACHE{$album}} if exists $ALBUM_OFFSETS_CACHE{$album};

    my @exts = qw(flac mp3 ogg m4a wav gsm amr);
    my @files;
    for my $ext (@exts) {
        push @files, glob("${album}*/*.$ext");
    }
    @files = sort @files;

    my @durations;
    my @offsets;
    my $cum = 0;
    for my $f (@files) {
        my $d = soxi_duration($f);
        push @durations, $d;
        push @offsets, $cum;
        $cum += $d;
    }

    my $result = [\@files, \@durations, \@offsets, $cum];
    $ALBUM_OFFSETS_CACHE{$album} = $result;
    return @{$result};
}

sub write_current_album {
    my ($album, $start_offset, $files, $durations, $current_album_file) = @_;
    return unless $album && $current_album_file;
    $start_offset ||= 0;
    if (open(my $cf, '>', $current_album_file)) {
        print $cf "album=$album\noffset=$start_offset\n";
        if ($files && $durations && @$files) {
            for my $i (0 .. $#$files) {
                print $cf "track:$i:$durations->[$i]=$files->[$i]\n";
            }
        }
        close($cf);
    } else {
        warn "could not write $current_album_file: $!\n";
    }
}

sub read_current_album {
    my ($current_album_file) = @_;
    my ($album, $offset) = ('', 0);
    my (@files, @durations);
    if (-r $current_album_file && open(my $cf, '<', $current_album_file)) {
        while (<$cf>) {
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
        close($cf);
    }
    return ($album, $offset, \@files, \@durations);
}

sub build_resume_cmd {
    my ($album, $offset, $files, $durations) = @_;
    return undef unless $files && @$files;

    my $cum = 0;
    my $idx = 0;
    my $track_offset = 0;
    for my $i (0 .. $#$files) {
        my $d = $durations->[$i];
        $cum += $d;
        if ($cum > $offset) {
            $idx = $i;
            $track_offset = $offset - ($cum - $d);
            last;
        }
    }

    my @remaining = @$files[$idx .. $#$files];
    my $cmd = 'play ' . join(' ', map { "\"$_\"" } @remaining);
    if ($track_offset > 0) {
        $cmd .= ' trim ' . sprintf('%.2f', $track_offset);
    }
    return $cmd;
}

1;
