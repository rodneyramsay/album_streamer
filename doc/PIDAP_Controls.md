# pidap Pirate Audio Button Controls

These are the default button mappings for `pidap`. The mapping can be overridden with the `PIDAP_BUTTON_MAP` environment variable.

## Buttons

| Button | Short press | Long press (>= 3 s) |
|--------|-------------|---------------------|
| **A**  | Volume up   | --                   |
| **B**  | Volume down | --                   |
| **X**  | Pause / Resume playback | Toggle lock / unlock |
| **Y**  | Enter menu  | --                   |

## Combos

| Combo | Action | Notes |
|-------|--------|-------|
| **A + Y** | Next album | -- |
| **A + X** | Next track | -- |
| **B + Y** | Restart current album | If you are on the first track and within the first 15 seconds, it jumps to the previous album instead. |
| **B + X** | Previous track | -- |
| **A + B** | Restart current track | If you are within the first 15 seconds of the track, it jumps to the previous track instead. If you are on the first track and within the first 15 seconds, it jumps to the previous album. |

## Menu Mode

Press **Y** to enter the menu. The menu starts at the **track** level of the currently playing album.

| Button | Action in menu |
|--------|----------------|
| **A**  | Move cursor up |
| **B**  | Move cursor down |
| **X**  | Select / drill down one level |
| **Y**  | Go back one level |

- The menu opens on the track list for the currently playing album.
- At the track list, press **X** to start playback from the selected track.
- Press **Y** from the track list to return to the album list.
- At the album list, press **X** to show the tracks for the selected album.
- Press **Y** from the album list to return to the artist list.
- At the artist list, press **X** to show the albums for the selected artist.
- Press **Y** from the artist list to return to the genre list.
- At the genre list, press **X** to show the artists for the selected genre.
- Press **Y** from the genre list to exit the menu and resume playback.

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
