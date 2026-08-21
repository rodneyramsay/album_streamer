# album_streamer

Stream music from NAS using album organization. 

Also PIDAP!! Pi Digital Album Player. An album based streamer for RPI Zero + Porate-Audio Headphone Amp!!

Command Syntax:

   yass [-c <category>] [-a <artist>] [-l <album>] [-m <mount>] [-p] [-q] [-r]
   
   <category>, -a, and -l arguments can be perl regex or simple string

   In program control keys:
   
      n - Next LP
      t - Next Track
      x - Exit


======================================================================

This is the basis of a music streamer that is album centric. The audio
database for this tool is pure directory sructure hierarchy based:

    <nfs_mount>/<Classification>/<Artist>/<Album>/<Track_name>.flac

Where classification can be aribitrary groups. I use Jazz, Classical,
Jam, and Rock but the names are arbitrary, use any categories you
like. The directory based approch makes things easier when using
simple FAT file table based play order on older or more simple
players.

For now, there is only provision for FLAC audio but other formats can
be added.
    
I like to listen to music one album (or CD :D) at a time and this takes
extra effort with all the different streaming tools I've tried. I
don't like managing play lists or music libraries. I don't need album
art and I don't need a way to fast forward or re-wind inside a
track.

The goal is to have a web front end that help manage things but for
now, album_streamer loops though all music in randomized (-r) or
alphabetical album order.

Requires
   Proc::Killfam from Proc::ProcessTable
   Term::ReadKey
   Time::HiRes

Use 'export AUDIODEV=hw:\<n\>' to select sound card <n> for sox playback.

Use 'export AUDIODEV=pulse' to select bluetooth speaker on pulse based system

## pidap — Pi Digital Audio Player

`pidap` is an album-centric, random FLAC player for the Raspberry Pi Pirate Audio board. It is split into two programs:

- `pidap_playlist` — runs first at boot to mount USB music partitions and build or preserve `pidap.generated.playlist`.
- `pidap` — the player. It reads the generated playlist and plays the albums.

The music is expected to be organized as:

    <mount>/<Category>/<Artist>/<Album>/<Track>.flac

The default root is `/usr/local/Music`. USB partitions are mounted under `/media/USB01`, `/media/USB02`, etc. and included when the playlist is built.

Typical flow:

    perl pidap_playlist   # mount USBs, generate playlist if needed
    perl pidap            # play the generated playlist

`pidap_playlist` exits quickly and prints `USB mounts ready, using existing playlist` when a playlist is already present and no boot button is held, so it can safely run on every boot to keep mounts in place.

Useful environment variables:

- `PIDAP_BUTTON_MAP` — button mapping (default `A:vol_up,B:vol_down,X:lock,Y:next_track`)
- `PIDAP_VOLUME_CONTROL`, `PIDAP_INITIAL_VOLUME`, `PIDAP_VOLUME_STEP`
- `PIDAP_LED_PATH`, `PIDAP_LED_TRIGGER`

Hold a button at boot when `pidap_playlist` runs to force different behavior:

- **A** — build a new random playlist
- **B** — build a new sorted playlist
- **X** — keep the playlist, reset place/resume


