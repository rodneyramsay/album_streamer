# album_streamer

Stream music from NAS using album organization.

Command Syntax:

   yass [-c <category>] [-a <artist>] [-l <album>] [-m <mount>] [-p] [-q] [-r]
   
   <category>, <artist>, and <album> arguments can be perl regex or simple string

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
now, album_sreamer loops though all music in randomized (-r) or
alphabetical album order.

Requires
   Proc::Killfam from Proc::ProcessTable
   Term::ReadKey
   Time::HiRes

Use 'export AUDIODEV=hw:<n>' to select sound card <n> for sox playback.


