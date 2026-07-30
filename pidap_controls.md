# pidap Pirate Audio Button Controls

These are the default button mappings for `pidap`. The mapping can be overridden with the `PIDAP_BUTTON_MAP` environment variable.

## Buttons

| Button | Short press | Long press (>= 3 s) |
|--------|-------------|---------------------|
| **A**  | Volume up   | –                   |
| **B**  | Volume down | –                   |
| **X**  | Pause / Resume playback | Toggle lock / unlock |
| **Y**  | Next track  | –                   |

## Combos

| Combo | Action | Notes |
|-------|--------|-------|
| **A + Y** | Next album | – |
| **B + Y** | Restart current album | If you are on the first track and within the first 15 seconds, it jumps to the previous album instead. |
| **A + B** | Restart current track | If you are within the first 15 seconds of the track, it jumps to the previous track instead. If you are on the first track and within the first 15 seconds, it jumps to the previous album. |

## Lock State

- Holding **X** for 3 seconds toggles the lock.
- When locked, the volume buttons (**A** and **B**) still work.
- When locked, track/album navigation, pause/resume, and combos are ignored.
- The only way to unlock is another long **X** press (3 seconds).

## Command Line

```
pidap [-c <category>] [-a <artist>] [-l <album>] [-m <mount>] [-p] [-q]
```

- `-c <category>` – filter by category (Perl regex or simple string)
- `-a <artist>` – filter by artist
- `-l <album>` – filter by album
- `-m <mount>` – music root (default `/usr/local/Music`)
- `-p` – stop after playing the playlist once
- `-q` – quiet

## Persistence

- Playlist order is saved in the mount point as `pidap.playlist` and only regenerated if missing.
- The current album index is saved as `pidap.place` in the mount point.
- If playback is paused when power is removed, `pidap.resume` lets `pidap` resume from the same track/offset on next boot.
