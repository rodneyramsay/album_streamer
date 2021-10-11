# album_streamer

Stream music from NAS based on album organization. 

This is the basis of a music streamer that will be album centric. The
database for this tool is pure directory sructure hierarchy based:

    <nfs_mount>/<Classification>/<Artist>/<Album>/<Track_name>.flac
    
Where classification can be aribitrary groups. I use Jazz, Classical,
Jam, and Rock but the names are arbitrary, use any categories you
like. The directory based approch make things easier when you go to
simple FAT file table based play order on older or more simple
players.

I like to listen to music an album (or CD :D) at a time and this takes
extra effort with all the different streaming tools I've tried. I
don't like managing play lists or music libraries. I don't need album
art and I don't need a way to fast forward or rewuind inside a
track.

The goal is to have a web front end that help manage things but
for now, album_sreamer loops though all music in randomized album
order.

Requires
   Proc::Killfam from Proc::ProcessTable
   Term::ReadKey
   Time::HiRes

Use 'export AUDIODEV=hw:1' to select sound card #1 for sox playback.


