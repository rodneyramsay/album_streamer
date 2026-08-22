# PIDAP User's Manual

PIDAP (Pi Digital Audio Player) is an album-centric FLAC player designed for the Raspberry Pi with the Pirate Audio board. It plays music from local or USB storage in album order, randomizing the album sequence while keeping each album's internal track order.

## Architecture

PIDAP is split into three programs, plus a helper control script:

- `pidap_playlist` — runs first at boot to mount USB music partitions and build or preserve `pidap.generated.playlist`.
- `pidap-menu` — a daemon that draws the on-screen menu and reads button navigation commands from a FIFO.
- `pidap` — the player. It reads the generated playlist, plays the albums, and reads menu results from `pidap-menu`.
- `pidap-ctl` — a convenience script for systemd service control: `pidap-ctl {start|stop|restart|status}`.

`pidap_playlist` should always run before the others because it is the only part that mounts USB drives. If the playlist already exists and no boot button is held, `pidap_playlist` simply ensures the mounts are in place and exits.

The menu and player communicate through named pipes (FIFOs) so neither has to busy-wait:

- `pidap.generated.menu_in` — `pidap_buttons.pl` writes navigation commands (`show`, `up`, `down`, `select`, `back`).
- `pidap.generated.menu_out` — `pidap-menu` writes the selected album and track offset.
- `pidap.generated.menu_mode` — a flag file that tells `pidap_buttons.pl` the menu is active.

## Music Library Layout

Music is expected to be organized as:

    <music_root>/<Category>/<Artist>/<Album>/<Track>.flac

For example:

    /usr/local/Music/Rock/ZZ_Top/Eliminator/01.flac

- `<Category>` — any top-level grouping (e.g., `Rock`, `Jam`, `Vinyl`).
- `<Artist>` — the artist or band name.
- `<Album>` — the album name.
- `<Track>.flac` — one FLAC track per file. Album tracks are played in alphabetical order.

The default music root is `/usr/local/Music`. USB partitions are mounted under `/media/USB01`, `/media/USB02`, etc. If a USB drive has a top-level `Music` directory, that directory is used as a music root; otherwise the mount point itself is used.

## `pidap_playlist`

```
perl pidap_playlist [-c <category>] [-a <artist>] [-l <album>] [-m <mount>] [-q]
```

### Options

- `-c <category>` — only include albums whose category matches this Perl regex or plain string.
- `-a <artist>` — only include albums whose artist matches this regex.
- `-l <album>` — only include albums whose album name matches this regex.
- `-m <mount>` — use a different music root (default `/usr/local/Music`).
- `-q` — quiet mode.

### USB Mounting

Before building the playlist, `pidap_playlist` looks for removable USB partitions and mounts them under `/media/USB01`, `/media/USB02`, etc. Mounted USB roots are recorded in `pidap.generated.usb_mounts`.

### Boot-Time Button Behavior

Hold one of the buttons while `pidap_playlist` starts to force different behavior:

- **A** — delete the existing playlist and build a new random one.
- **B** — delete the existing playlist and build a new sorted one.
- **X** — keep the existing playlist, delete the saved place and resume files.

If no button is held and `pidap.generated.playlist` already exists, `pidap_playlist` just ensures USB mounts are present and exits without rebuilding.

## `pidap`

```
perl pidap [-p] [-q]
```

### Options

- `-p` — stop after playing through the playlist once.
- `-q` — quiet mode.

`pidap` reads `pidap.generated.playlist` and plays the albums. It does not mount USBs or generate the playlist; it assumes `pidap_playlist` has already run.

### Playback

- Albums are played in the order stored in `pidap.generated.playlist`.
- Tracks inside an album are played in alphabetical order.
- When an album finishes, `pidap` advances to the next album in the playlist.
- When the playlist finishes, it starts over from the beginning (unless `-p` was used).

### Resuming

If `pidap` is paused when power is removed, it saves the current album and offset to `pidap.generated.resume`. On the next run, playback resumes from that point if the album is still in the playlist.

If playback was stopped normally, the current album index is saved to `pidap.generated.place`. `pidap` uses this to resume from the last played album.

## `pidap-menu`

`pidap-menu` is a daemon that listens for `show` commands from `pidap_buttons.pl`, draws the menu on the screen, and writes the chosen album/offset back to `pidap`. It is started by `pidap-menu.service` and is expected to be running before `pidap-play.service` starts.

The menu is divided into a tree of lists:

1. **Root** — choose between `Playlist` (all albums in playlist order) and every genre found in the music library.
2. **Playlist** — all albums in the playlist order; selecting an album opens its track list.
3. **Genre** — artists in that genre.
4. **Artist** — albums by that artist.
5. **Album** — tracks in that album; press **X** to start playing from the selected track.

Use **A** / **B** to move the cursor, **X** to select or drill down, and **Y** to go back one level.

## `pidap-ctl`

`pidap-ctl` is a helper script for systemd. Run it as root:

```
sudo /home/rodney/album_streamer/pidap-ctl {start|stop|restart|status}
```

It `daemon-reload`s, stops services in reverse order, and starts them in the correct dependency order (`pidap-playlist`, `pidap-menu`, `pidap-play`).

## Persistence and Runtime Files

PIDAP keeps several small generated files in its working directory. Do not edit them manually unless you understand their purpose.

| File | Purpose |
|------|---------|
| `pidap.generated.playlist` | Album play order, written by `pidap_playlist` and read by `pidap`. |
| `pidap.generated.place` | Current album index while playing. Deleted when the playlist finishes. |
| `pidap.generated.resume` | Paused album and track offset, used to resume after an unclean shutdown. |
| `pidap.generated.current_album` | Track list and durations for the active album, used by the button handler and menu. |
| `pidap.generated.usb_mounts` | List of currently mounted USB directories, maintained by `pidap_playlist`. |
| `pidap.generated.play_pid` | PID of the active playback process. |
| `pidap.generated.menu_in` | FIFO that `pidap_buttons.pl` writes menu commands to. |
| `pidap.generated.menu_out` | FIFO that `pidap-menu` writes selected album/offset to. |
| `pidap.generated.menu_mode` | Flag file created while the menu is on screen. |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PIDAP_BUTTON_MAP` | `A:vol_up,B:vol_down,X:lock,Y:next_track` | Button mapping. |
| `PIDAP_VOLUME_CONTROL` | `Amp` | ALSA control name for volume. |
| `PIDAP_VOLUME_STEP` | `2` | Volume step percent. |
| `PIDAP_INITIAL_VOLUME` | `40` | Volume percent set at startup. |
| `PIDAP_LED_PATH` | (auto) | Path to the LED `brightness` file. |
| `PIDAP_LED_TRIGGER` | (auto) | Path to the LED `trigger` file. |
| `PIDAP_LOCK_HOLD_SEC` | `2.2` | Seconds to hold **X** to toggle lock. |
| `PIDAP_MENU_HOLD_SEC` | `1.5` | Seconds to hold **Y** to enter the menu via the long-press timer. |
| `PIDAP_LOG_FILE` | `/tmp/pidap_buttons.log` | Log file for the button handler. |
| `PIDAP_RUN_DIR` | script directory | Working directory for generated files. |
| `PIDAP_DEBUG` | (unset) | When set, `pidap` and `pidap_playlist` keep stdout/stderr unredirected. |
| `AUDIODEV` | — | SoX output device (e.g., `hw:0` or `pulse`). |

## Controls

Button and combo mappings are documented in `doc/PIDAP_Controls.md`.

## Typical Boot Flow

1. `pidap_playlist` runs, mounts USB drives, and either uses the existing playlist or builds a new one.
2. `pidap-menu` starts and creates the menu FIFOs.
3. `pidap` starts, opens `pidap.generated.menu_out`, and begins playback.
4. The button handler (`pidap_buttons.pl`) runs in the background and listens for button presses.

## Notes

- `pidap` is designed for gapless album playback.
- Multi-disc albums should be named `disc_1`, `disc_2`, etc. Only the first disc is recorded in the playlist; `pidap` plays all matching FLAC files in the album path anyway.
- Filtration options on `pidap_playlist` are useful for one-off sessions; the resulting filtered playlist is not written and can be passed to `pidap` manually if desired.
