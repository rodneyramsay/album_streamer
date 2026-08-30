#!/bin/bash
#
# Copy music to the PIDAP Pi with sorted tar streaming over SSH.
# Uses chacha20-poly1305 (faster on Pi Zero) and no compression.
#
# Usage:
#   copy-music.sh <src-path> [<target-parent>]
#
# Examples:
#   copy-music.sh /mnt/wd_my_cloud/Music/Vinyl
#     -> copied to /usr/local/Music/Vinyl on the Pi
#
#   copy-music.sh /mnt/wd_my_cloud/Music /usr/local
#     -> copied to /usr/local/Music on the Pi (whole music tree)

set -e

HOST="${PIDAP_HOST:-root@192.168.0.31}"
DEFAULT_TARGET="/usr/local/Music"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <src-path> [<target-parent>]" >&2
    echo "Default target parent is ${DEFAULT_TARGET}" >&2
    exit 1
fi

SRC="$1"
TARGET_PARENT="${2:-$DEFAULT_TARGET}"

if [ ! -e "$SRC" ]; then
    echo "ERROR: source does not exist: $SRC" >&2
    exit 1
fi

SRC_DIR=$(cd "$(dirname "$SRC")" && pwd)
SRC_BASE=$(basename "$SRC")

SSH_OPTS="-o Ciphers=chacha20-poly1305@openssh.com -o Compression=no"

echo "Copying $SRC_DIR/$SRC_BASE to ${HOST}:${TARGET_PARENT}/$SRC_BASE ..."

tar --sort=name -C "$SRC_DIR" -chf - "$SRC_BASE" \
    | ssh $SSH_OPTS "$HOST" "tar -C '$TARGET_PARENT' -xf -"

echo "Done."
