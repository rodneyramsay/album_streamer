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

## Status LED

`pidap` can drive a status LED (default is the Pi on-board `ACT`/`led0` LED; override with `PIDAP_LED_PATH` and `PIDAP_LED_TRIGGER`).

- The LED is turned off when `pidap` starts and stays off while an album is playing.
- The LED flashes slowly while a new album is being loaded.
- The LED flashes quickly each time playback crosses a track boundary, including when you jump to the next/previous track.
- The LED turns off again as soon as the play process is running and after each track-boundary blink.
- This is pure visual feedback; the loading and playback paths themselves are unchanged, so playback stays gapless.

## Track Boundary Precomputation

`pidap` precomputes the duration and start offset of every track in the current album when it begins playback, and stores this in `pidap.generated.current_album`. The button handler uses this data to know which track is playing and to jump to the start of a specific track or the previous track. The button handler no longer needs to call `soxi` itself, so track skips and restarts are available immediately.

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

- Playlist order is saved in the mount point as `pidap.generated.playlist` and only regenerated if missing.
- The current album index is saved as `pidap.generated.place` in the mount point.
- If playback is paused when power is removed, `pidap.generated.resume` lets `pidap` resume from the same track/offset on next boot.
