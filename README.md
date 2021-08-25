# album_streamer
Stream music from NAS based on album organization. 

This is the basis of a music streamer that will be album centric. The database for this tool is pure directory sructure hierarchy based:

    <nfs_mount>/<Classification>/<Artist>/<Album>/<Track_name>.flac
    
Where classification can be aribitrary groups. I use Jazz, Classical, Jam, Rock, etc. The directory based approch make things easier when you go to simple FAT file table based play order. Anyway, I like to listen to music an album (or CD :D) at a time. The goal is to have a web front end that help manage things but for now, album_sreamer loops though all music in randomized album order.
