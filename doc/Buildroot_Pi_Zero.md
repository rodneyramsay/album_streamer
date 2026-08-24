# Buildroot / Raspberry Pi Zero 1.4 Deployment Notes

These notes cover the extra packages, kernel configuration, and Perl module situation needed to run the `pidap` family on a minimal Buildroot image for the Raspberry Pi Zero 1.4 with the Pirate Audio board.

The user already has `perl`, `sox`, `flac`, and `alsa` selected. The lists below are the additional pieces needed to make the current code run.

---

## 1. Buildroot packages

### Required

| Buildroot symbol | Why it is needed |
|------------------|------------------|
| `BR2_PACKAGE_PERL=y` | Core interpreter. Already selected. |
| `BR2_PACKAGE_SOX=y` | Playback and `soxi` duration queries. Already selected. |
| `BR2_PACKAGE_FLAC=y` | FLAC support for SoX. Already selected. |
| `BR2_PACKAGE_ALSA_LIB=y` and `BR2_PACKAGE_ALSA_LIB_PCM=y` | SoX ALSA output. `amixer` needs `alsa-lib`. |
| `BR2_PACKAGE_ALSA_UTILS=y` | `amixer` (volume control) and `aplay`/`arecord`. |
| `BR2_PACKAGE_UTIL_LINUX=y` | `lsblk`, `blkid`, `mount` helpers for USB drive detection. |
| `BR2_PACKAGE_UTIL_LINUX_LSBLK=y` | `lsblk` is used by `pidap` and `pidap-playlist`. |
| `BR2_PACKAGE_UTIL_LINUX_LIBBLKID=y` | `blkid` library and command for filesystem type detection. |
| `BR2_PACKAGE_UTIL_LINUX_BLKID=y` | The `blkid` binary (if split out as a separate option). |
| `BR2_PACKAGE_UTIL_LINUX_MOUNT=y` | Full `mount` binary; busybox `mount` works for common cases but the util-linux one has better helper support for NTFS. |
| `BR2_PACKAGE_LIBGPIOD=y` | GPIO character device library. |
| `BR2_PACKAGE_LIBGPIOD_TOOLS=y` | `gpioget` and `gpiomon` for the button handler. |
| `BR2_PACKAGE_RPI_FIRMWARE=y` | RPi bootloader / firmware / DTBs. |
| `BR2_PACKAGE_RPI_FIRMWARE_INSTALL_DTB_OVERLAYS=y` | Device tree overlays for audio and (optionally) display. |

### Optional / hardware-specific

| Buildroot symbol | Why it is needed |
|------------------|------------------|
| `BR2_PACKAGE_RPI_UTILS` or `BR2_PACKAGE_RPI_PINCTRL` | `pinctrl` / `raspi-gpio` for the Pirate Audio TFT backlight (GPIO 13). `pidap-buttons` falls back gracefully if neither is available; the screen will simply not dim on lock. |
| `BR2_PACKAGE_BASH=y` | `pidap-ctl` uses bash arrays. Only needed if you want the convenience script as-is. |
| `BR2_PACKAGE_SYSTEMD=y` with `BR2_INIT_SYSTEMD=y` | Only needed if you want the `services/*.service` files to work. `pidap` can be started manually. |

---

## 2. Kernel configuration

### GPIO, LED, USB, sound

```
CONFIG_GPIOLIB=y
CONFIG_GPIO_CDEV=y          # libgpiod /dev/gpiochip0
CONFIG_LEDS_CLASS=y
CONFIG_LEDS_GPIO=y
CONFIG_LEDS_TRIGGERS=y
CONFIG_SND_SOC=y
CONFIG_SND_BCM2835_SOC_I2S=y
CONFIG_SND_SOC_PCM5102A=y   # or the Hifiberry DAC compatible driver
CONFIG_USB=y
CONFIG_USB_DWC2=y           # RPi Zero OTG/USB host
CONFIG_USB_STORAGE=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_DEVTMPFS=y
```

### Filesystem support for USB drives

```
CONFIG_FAT_FS=y
CONFIG_VFAT_FS=y
CONFIG_EXFAT_FS=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NTFS_FS=y            # read-only kernel NTFS; use ntfs-3g/FUSE for full r/w
CONFIG_EXT4_FS=y
```

### Display / framebuffer (Pirate Audio ST7789)

`pidap-menu` and `pidap` draw to `/dev/tty1` using ANSI escape codes. You need the ST7789 LCD as a framebuffer console.

```
CONFIG_FB=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FB_TFT=y
CONFIG_FB_TFT_ST7789V=y     # or the appropriate ST7789 variant
CONFIG_SPI_BCM2835=y
```

A custom device tree overlay is usually required. The exact DTBO depends on the kernel and board revision. Pimoroni's examples and the `panel_bin/pirate-audio-st7789-panel.txt` file in this repo are the best starting points. Add the overlay to `config.txt`:

```
dtoverlay=pidi
# or
dtoverlay=hifiberry-dac
```

Important Pirate Audio pins:

- LCD: `dc=9`, `cs=8` or `24` depending on board, `backlight=13`
- Buttons A/B/X/Y: GPIO `5`, `6`, `16`, `24` (active low, already pulled up in code)

### Audio

The Pirate Audio headphone amp uses a PCM5102A I2S DAC. The usual RPi overlay is:

```
dtoverlay=hifiberry-dac
```

Test with `aplay -l` after boot. Override the SoX/ALSA sink if needed:

```
export AUDIODEV=hw:0
```

and the mixer name with:

```
export PIDAP_VOLUME_CONTROL=<control name from amixer scontrols>
```

---

## 3. Perl module audit

### What is actually used in the repo?

A scan of every `use` / `require` in the codebase shows the following:

#### Core Perl modules (no CPAN build needed)

All of these ship with a standard Buildroot `perl` build:

- `POSIX`
- `Getopt::Std`
- `FindBin`
- `Time::HiRes`
- `IO::Select`
- `Fcntl`
- `IPC::Open3`
- `IO::Handle`
- `Exporter`
- `strict`
- `warnings`
- `vars`
- `lib`
- `Cwd`
- `File::Basename`
- `File::Temp`

#### Local / bundled modules

- `PIDAPAlbum` — custom module in `lib/PIDAPAlbum.pm`. Already in the repo.
- `Proc::Killfam` — local stub in `lib/Proc/Killfam.pm`. Not a real CPAN module here.
- `Term::ReadKey` — local stub in `lib/Term/ReadKey.pm`. Not a real CPAN module here.

### What about the modules the user listed?

| Module | Is it needed? | Notes |
|--------|---------------|-------|
| `Proc::Killfam` from `Proc::ProcessTable` | **No** for `pidap` and the current `landap`. | `pidap-buttons` has its own `_killfam_fallback`. `landap` was rewritten to use Perl built-in `kill` and `setpgrp` instead. The `lib/Proc/Killfam.pm` stub is only present for the original `yass` script, which is not used by `pidap`. |
| `Term::ReadKey` | **No** for `pidap`. | `pidap` uses `gpiomon`. `landap` was rewritten to use `stty` + `sysread` for raw terminal input, so no `Term::ReadKey` is required. Only `yass` uses it, and it uses the local stub. |
| `Time::HiRes` | **Yes, but core**. | Already included in any modern Perl. No extra build step. |

---

## 4. Plan for Perl modules

Given the audit, the plan is:

1. **Do not build any CPAN modules for `pidap` / `landap`.** All required modules are either Perl core or bundled in `lib/`.
2. **Ship `lib/` with the scripts.** `lib/PIDAPAlbum.pm`, `lib/Proc/Killfam.pm`, and `lib/Term/ReadKey.pm` need to be copied to the target in the same directory as the executables. Each script already has:

   ```perl
   use lib "$FindBin::Bin/lib";
   ```

3. **If you want to keep `yass` working with real `Term::ReadKey` / `Proc::Killfam`** (not needed for `pidap`), then you would need `scanpan` / `cpanm` builds of those two XS modules. That is the only scenario where `scanpan` comes into play.

### If you do need to build real `Term::ReadKey` or `Proc::Killfam` later

- `Term::ReadKey` is an XS module. Cross-compiling it in Buildroot usually requires:
  - `BR2_PACKAGE_PERL` with `perl` headers in staging
  - `cpanminus` or a `.mk` recipe that sets `PERL_MM_OPT` and `PERL5LIB` to the staging/target sysroot
  - `CC`, `LD`, and `AR` pointing to the cross toolchain
- `Proc::ProcessTable` is also an XS module. Same build steps.
- Because this is fragile and unnecessary for `pidap`, the recommended plan is to **avoid them entirely**.

---

## 5. Runtime notes

- Default music root: `/usr/local/Music` (create this in the rootfs overlay or pass `-m /your/path`).
- USB mounts: `/media` is auto-created by `pidap-playlist`.
- `/tmp` must be writable for `pidap-buttons.log`.
- The `FindBin` setup means the `lib/` directory and scripts must live together on the target. Copy the entire `album_streamer` tree to, for example, `/usr/local/pidap`.

---

## 6. Quick manual start (no systemd)

```
perl /usr/local/pidap/pidap-playlist
perl /usr/local/pidap/pidap-menu &
perl /usr/local/pidap/pidap &
perl /usr/local/pidap/pidap-buttons &
```

---

## Summary

For a minimal RPi Zero 1.4 `pidap` image, the extras beyond `perl`/`sox`/`flac`/`alsa` are: `libgpiod` with tools, `alsa-utils`, `util-linux` with `lsblk`/`blkid`/`mount`, the right `fbtft`/`hifiberry-dac` overlays, and the kernel features above. **No CPAN Perl modules are required** — everything `pidap` and the current `landap` need is either Perl core or bundled in `lib/`.
