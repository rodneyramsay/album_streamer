# PIDAP Buildroot

This directory is the Buildroot external tree for the PIDAP album player.
It builds a Raspberry Pi Zero W root filesystem that boots over NFS for
development, with a writable `/usr/local` partition on the SD card for music.

## Quick build

```sh
cd /home/rodney/buildroot
make pidap_defconfig
make
```

The results are in `/home/rodney/buildroot/output/images/`:

- `sdcard.img`        -- full SD card image (boot + rootfs + user-data)
- `boot.vfat`         -- generated first partition image
- `rootfs.ext2`       -- the root filesystem (also exported for NFS)
- `user-data.ext4`    -- writable music partition

## NFS boot

The target boots most of the OS over NFS so the SD card only needs to be
flashed when the kernel or boot firmware changes.

### 1. Host NFS server

The helper script `deploy-nfs.sh` (symlinked into the buildroot root) mounts
`output/images/rootfs.ext2` on `/srv/nfs/pidap` and refreshes the export.

```sh
cd /home/rodney/buildroot
sudo ./deploy-nfs.sh
```

It expects the build host to be reachable at the address in `cmdline.txt`.
The default is `192.168.0.69`; the Pi is `192.168.0.31`.

`/etc/exports` should contain something like:

```
/srv/nfs/pidap 192.168.0.31(rw,no_root_squash,no_subtree_check,insecure,async)
```

`insecure` is required because the kernel NFS client uses high source ports.

### 2. Flash the SD card

The card only needs the boot partition for NFS; `sdcard.img` also includes a
user-data partition.

```sh
sudo dd if=/home/rodney/buildroot/output/images/sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with the actual card device.

### 3. Reboot the Pi

If the host export is live and the network cables/switch are ready, the Pi
will load the kernel from the SD, bring up `eth0` at `192.168.0.31/16`, and
mount `/` from `192.168.0.69:/srv/nfs/pidap`.

## SD-only boot

Remove `root=/dev/nfs ...` from `cmdline.txt` and the kernel will use the
rootfs partition on the SD card instead. The generated `sdcard.img` already
contains a complete rootfs for this.

## Key files

- `board/PIDAP/cmdline.txt` -- kernel command line (NFS, rootdelay, console)
- `board/PIDAP/config.txt`  -- Pi boot config (`dtoverlay`, `dtparam`)
- `board/PIDAP/linux.config` -- kernel config (must include USB/ethernet built-in for NFS)
- `board/PIDAP/post-image.sh` -- generates `user-data.ext4` and runs `genimage`
- `deploy-nfs.sh` -- host-side NFS export refresh
- `rootfs-overlay/` -- extra files layered on top of the Buildroot rootfs

## Music

The `user-data` partition on the SD is mounted at `/usr/local` by `/etc/fstab`.
`mkuserimg.sh` can copy a subset of music from `/mnt/wd_my_cloud/FLAC32G_A`
into the image at build time, or you can copy music onto the card later.

## Checking the target

`/usr/bin/pidap-env-check` (installed by the rootfs overlay) reports what is
present and what is missing. Run it after boot to verify the environment.
