#!/bin/bash
#
# Create the pidap-data.ext4 image for the small metadata partition.
# Run by the PIDAP post-image.sh under fakeroot.
#
# Optional environment overrides:
#   PIDAP_DATA_SIZE_M - size in MiB (default: 1)
#

set -e

: "${BINARIES_DIR:?}"
: "${BUILD_DIR:?}"

PIDAP_DATA_SIZE_M="${PIDAP_DATA_SIZE_M:-1}"
META_IMG="${BINARIES_DIR}/pidap-data.ext4"
META_SIZE="${PIDAP_DATA_SIZE_M}M"

# Prefer buildroot's host mkfs.ext4, but allow PATH fallback
if [ -x "${HOST_DIR:-}/sbin/mkfs.ext4" ]; then
    MKFS_EXT4="${HOST_DIR}/sbin/mkfs.ext4"
else
    MKFS_EXT4="mkfs.ext4"
fi

# Create a sparse file and format it.  The journal is disabled to save
# space on a tiny partition; -N 64 keeps the inode table small.
rm -f "${META_IMG}"
echo "Creating pidap-data.ext4 of ${META_SIZE}"
truncate -s "${META_SIZE}" "${META_IMG}"
"${MKFS_EXT4}" -F -m 0 -O ^has_journal -N 64 -L pidap-data "${META_IMG}"

echo "Created ${META_IMG}"
