# Linux Reduction for PIDAP

This is the plan for trimming the Raspberry Pi OS/systemd services and logging so the player boots faster, uses less CPU, and writes less to the SD card.

## Goals

- Reduce userspace boot time.
- Reduce background CPU and SD-card writes.
- Keep Ethernet and SSH for development.
- Make the system safe to later remove `sshd` and `NetworkManager` once no longer needed.

## Why the boot log is slow

From `boot_log.txt`:

```
Startup finished in 10.680s (kernel) + 48.269s (userspace) = 58.950s
cloud-init-main.service: Consumed 7.301s CPU time
```

`cloud-init` and `NetworkManager-wait-online` are the biggest userspace delays.  Persistent journal writes are the main SD/CPU drag at runtime.

## 1. Safe to remove now (keep SSH + Ethernet)

These can be run while still keeping remote access:

```bash
# cloud-init is the largest boot-time consumer
systemctl disable --now cloud-init-main cloud-init-local cloud-init-network cloud-init cloud-final

# Do not block the boot sequence waiting for "online"
systemctl mask NetworkManager-wait-online.service

# Wi-Fi is not in use (rfkill already disables it)
systemctl disable --now wpa_supplicant

# mDNS/DNS-SD not needed if you connect by IP
systemctl disable --now avahi-daemon

# NFS/RPC
systemctl disable --now rpcbind nfs-blkmap rpc-statd-notify rpc-gssd

# Periodic maintenance not needed on a dedicated player
systemctl disable --now cron rpi-eeprom-update

# Maintenance timers
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
systemctl disable --now dpkg-db-backup.timer
systemctl disable --now e2scrub_all.timer
systemctl disable --now fstrim.timer
systemctl disable --now logrotate.timer
systemctl disable --now man-db.timer
```

## 2. Stop journal from hitting the SD card

Create a journald drop-in that keeps journal processing in RAM only:

```bash
mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/no-storage.conf
[Journal]
Storage=none
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no
EOF
systemctl restart systemd-journald
```

This will drop `systemd-journal` CPU and stop `/var/log/journal` writes.

## 3. Verify

After reboot, check the new boot time and remaining activity:

```bash
systemd-analyze
systemd-analyze blame
top
```

The LED should no longer flicker and the players should sit near idle again.

## 4. Later removal (once development is done)

When you no longer need remote access, run these too:

```bash
systemctl disable --now ssh
systemctl disable --now sshd
systemctl disable --now systemd-logind
# Replace NetworkManager with a tiny systemd-networkd config or remove networking
```

If `NetworkManager` is removed, create a static network unit, e.g.
`/etc/systemd/network/10-eth0.network`:

```ini
[Match]
Name=eth0

[Network]
DHCP=yes
```

Then:

```bash
systemctl disable --now NetworkManager
touch /etc/systemd/network/10-eth0.network  # after populating above
systemctl enable systemd-networkd
```

This gets the system very close to a headless, minimal audio appliance.
