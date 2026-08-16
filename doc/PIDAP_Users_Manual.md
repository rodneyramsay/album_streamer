# PIDAP User's Manual

PIDAP (Pi Digital Audio Player) is an album-centric FLAC player designed for the Raspberry Pi with the Pirate Audio board. It plays music from local or USB storage in album order, randomizing the album sequence while keeping each album's internal track order.

## Architecture

PIDAP is split into two programs:

- `pidap_playlist` — runs first at boot to mount USB music partitions and build or preserve `pidap.generated.playlist`.
- `pidap` — the player. It reads the generated playlist and plays the albums.

`pidap_playlist` should always run before `pidap` because it is the only part that mounts USB drives. If the playlist already exists and no boot button is held, `pidap_playlist` simply ensures the mounts are in place and exits.

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

## Persistence Files

PIDAP keeps several small generated files in its working directory. Do not edit them manually unless you understand their purpose.

| File | Purpose |
|------|---------|
| `pidap.generated.playlist` | Album play order, written by `pidap_playlist` and read by `pidap`. |
| `pidap.generated.place` | Current album index while playing. Deleted when the playlist finishes. |
| `pidap.generated.resume` | Paused album and track offset, used to resume after an unclean shutdown. |
| `pidap.generated.current_album` | Track list and durations for the active album, used by the button handler. |
| `pidap.generated.usb_mounts` | List of currently mounted USB directories, maintained by `pidap_playlist`. |
| `pidap.generated.play_pid` | PID of the active playback process. |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PIDAP_BUTTON_MAP` | `A:vol_up,B:vol_down,X:lock,Y:next_track` | Button mapping. |
| `PIDAP_VOLUME_CONTROL` | `Amp` | ALSA control name for volume. |
| `PIDAP_VOLUME_STEP` | `2` | Volume step percent. |
| `PIDAP_INITIAL_VOLUME` | `40` | Volume percent set at startup. |
| `PIDAP_LED_PATH` | (auto) | Path to the LED `brightness` file. |
| `PIDAP_LED_TRIGGER` | (auto) | Path to the LED `trigger` file. |
| `AUDIODEV` | — | SoX output device (e.g., `hw:0` or `pulse`). |

## Controls

Button and combo mappings are documented in `doc/PIDAP_Controls.md`.

## Typical Boot Flow

1. `pidap_playlist` runs, mounts USB drives, and either uses the existing playlist or builds a new one.
2. `pidap` starts and begins playing from the saved place, or resumes from `pidap.generated.resume` if one exists.
3. The button handler (`pidap_buttons.pl`) runs in the background and listens for button presses.

## Notes

- `pidap` is designed for gapless album playback.
- Multi-disc albums should be named `disc_1`, `disc_2`, etc. Only the first disc is recorded in the playlist; `pidap` plays all matching FLAC files in the album path anyway.
- Filtration options on `pidap_playlist` are useful for one-off sessions; the resulting filtered playlist is not written and can be passed to `pidap` manually if desired.
