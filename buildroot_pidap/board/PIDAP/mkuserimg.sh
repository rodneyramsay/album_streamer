#!/bin/bash
#
# Create the user-data.ext4 image for the /usr/local (music) partition.
# Run by the PIDAP post-image.sh under fakeroot.
#
# Optional environment overrides:
#   MUSIC_SOURCE    - top-level source directory (default: /mnt/wd_my_cloud/FLAC32G_A)
#   MUSIC_INCLUDE   - relative path to include under /usr/local/Music
#                     (default: Rock/Who/Tommy)
#   USERDATA_SIZE   - override the image size (e.g. 2G, 500M)
#

set -e

: "${BINARIES_DIR:?}"
: "${BUILD_DIR:?}"

MUSIC_SOURCE="${MUSIC_SOURCE:-/mnt/wd_my_cloud/FLAC32G_A}"
MUSIC_INCLUDE="${MUSIC_INCLUDE:-Rock/Who/Tommy}"
DATA_IMG="${BINARIES_DIR}/user-data.ext4"
STAGING="${BUILD_DIR}/user-data-staging"

# Clean staging tree and create Music at the user-data image root.
# The user-data image is mounted at /usr/local, so Music/ here becomes /usr/local/Music.
rm -rf "${STAGING}"
mkdir -p "${STAGING}/Music"
chmod 0755 "${STAGING}" "${STAGING}/Music"

# Decide the image size.  If an include path exists, size to the data plus
# ~20% headroom, otherwise make a small empty 1G partition.
if [ -n "${USERDATA_SIZE}" ]; then
    IMAGE_SIZE="${USERDATA_SIZE}"
elif [ -d "${MUSIC_SOURCE}/${MUSIC_INCLUDE}" ]; then
    DATA_BYTES=$(du -sb "${MUSIC_SOURCE}/${MUSIC_INCLUDE}" | awk '{print $1}')
    # data + 20% headroom, round up to 64 MiB, minimum 1 GiB
    WANTED=$(( DATA_BYTES + DATA_BYTES / 5 ))
    WANTED=$(( (WANTED + 67108863) / 67108864 * 67108864 ))
    MIN=$(( 1 * 1024 * 1024 * 1024 ))
    [ "${WANTED}" -lt "${MIN}" ] && WANTED=${MIN}
    IMAGE_SIZE="${WANTED}"
else
    IMAGE_SIZE="1073741824"  # 1 GiB
fi

# If an include path was found, copy it into the staging Music tree
if [ -d "${MUSIC_SOURCE}/${MUSIC_INCLUDE}" ]; then
    echo "Including ${MUSIC_SOURCE}/${MUSIC_INCLUDE} -> /usr/local/Music/${MUSIC_INCLUDE}"
    DEST_DIR="${STAGING}/Music"
    mkdir -p "${DEST_DIR}"
    tar --sort=name -C "${MUSIC_SOURCE}" -ch "${MUSIC_INCLUDE}" \
        | tar -C "${DEST_DIR}" -xv
else
    echo "Warning: ${MUSIC_SOURCE}/${MUSIC_INCLUDE} not found, creating empty user-data partition"
fi

# Prefer buildroot's host mkfs.ext4, but allow PATH fallback
if [ -x "${HOST_DIR:-}/sbin/mkfs.ext4" ]; then
    MKFS_EXT4="${HOST_DIR}/sbin/mkfs.ext4"
else
    MKFS_EXT4="mkfs.ext4"
fi

# Create a sparse file and format it with the /usr/local/Music directory
rm -f "${DATA_IMG}"
echo "Creating user-data.ext4 of ${IMAGE_SIZE} bytes"
truncate -s "${IMAGE_SIZE}" "${DATA_IMG}"
"${MKFS_EXT4}" -F -m 0 -L user-data -d "${STAGING}" "${DATA_IMG}"

echo "Created ${DATA_IMG}"
