#!/bin/bash
#
# Create the user-data.ext4 image for the /usr/local (music) partition.
# Run by the PIDAP post-image.sh under fakeroot.
#
# Optional environment overrides:
#   MUSIC_SOURCE       - top-level source directory (default: /mnt/wd_my_cloud/Music)
#   MUSIC_INCLUDE      - single relative path to include (default: Rock/Who/Tommy)
#   MUSIC_INCLUDE_FILE - file with one relative path per line; overrides MUSIC_INCLUDE
#   USERDATA_SIZE      - override the image size (e.g. 2G, 500M)
#

set -e

: "${BINARIES_DIR:?}"
: "${BUILD_DIR:?}"

MUSIC_SOURCE="${MUSIC_SOURCE:-/mnt/wd_my_cloud/Music}"
MUSIC_INCLUDE="${MUSIC_INCLUDE:-Rock/Who/Tommy}"
MUSIC_INCLUDE_FILE="${MUSIC_INCLUDE_FILE:-}"
# Leave USERDATA_SIZE unset to size to the selected music + 20%.
USERDATA_SIZE="${USERDATA_SIZE:-}"
DATA_IMG="${BINARIES_DIR}/user-data.ext4"
STAGING="${BUILD_DIR}/user-data-staging"

# Clean staging tree. The user-data image is mounted at /usr/local/Music,
# so the staging root becomes the music root on the Pi.
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
chmod 0755 "${STAGING}"

# Build the list of includes.  A file takes priority over a single path.
INCLUDES=()
if [ -n "${MUSIC_INCLUDE_FILE}" ] && [ -f "${MUSIC_INCLUDE_FILE}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$line" ] && continue
        INCLUDES+=("$line")
    done < "${MUSIC_INCLUDE_FILE}"
    echo "Using include list: ${MUSIC_INCLUDE_FILE}"
elif [ -n "${MUSIC_INCLUDE}" ]; then
    INCLUDES=("${MUSIC_INCLUDE}")
fi

# Decide the image size and copy the music into the staging tree.
if [ -n "${USERDATA_SIZE}" ]; then
    IMAGE_SIZE="${USERDATA_SIZE}"
fi

if [ ${#INCLUDES[@]} -gt 0 ]; then
    DATA_BYTES=0
    for inc in "${INCLUDES[@]}"; do
        if [ -d "${MUSIC_SOURCE}/${inc}" ]; then
            DATA_BYTES=$(( DATA_BYTES + $(du -sb "${MUSIC_SOURCE}/${inc}" | awk '{print $1}') ))
            echo "Including ${MUSIC_SOURCE}/${inc}"
            DEST_DIR="${STAGING}"
            tar --sort=name -C "${MUSIC_SOURCE}" -ch "${inc}" \
                | tar -C "${DEST_DIR}" -xv
        else
            echo "Warning: ${MUSIC_SOURCE}/${inc} not found, skipping"
        fi
    done

    if [ -z "${USERDATA_SIZE}" ]; then
        if [ "${DATA_BYTES}" -gt 0 ]; then
            # data + 20% headroom, round up to 64 MiB, minimum 128 MiB
            WANTED=$(( DATA_BYTES + DATA_BYTES / 5 ))
            WANTED=$(( (WANTED + 67108863) / 67108864 * 67108864 ))
            MIN=$(( 128 * 1024 * 1024 ))
            [ "${WANTED}" -lt "${MIN}" ] && WANTED=${MIN}
            IMAGE_SIZE="${WANTED}"
        else
            IMAGE_SIZE="134217728"  # 128 MiB
        fi
    fi
else
    if [ -z "${USERDATA_SIZE}" ]; then
        IMAGE_SIZE="134217728"  # 128 MiB
    fi
    echo "No music includes specified, creating empty user-data partition"
fi

# Copy license/source info into the user-data image.
LIC_FILE="$(dirname "$0")/../../license/GPLv2_License.txt"
LEGAL_INFO_DIR="${BINARIES_DIR%/*}/legal-info"
if [ -f "${LIC_FILE}" ]; then
    mkdir -p "${STAGING}/legal-info/licenses"
    cp -f "${LIC_FILE}" "${STAGING}/legal-info/licenses/GPL-2.0"
fi
if [ -d "${LEGAL_INFO_DIR}" ]; then
    echo "Including BusyBox source, all license files, and build metadata"
    mkdir -p "${STAGING}/legal-info/sources" "${STAGING}/legal-info/licenses"
    for src in "${LEGAL_INFO_DIR}/sources/busybox-"*; do
        if [ -d "${src}" ]; then
            cp -a "${src}" "${STAGING}/legal-info/sources/"
            echo "Source: ${src}"
        fi
    done
    if [ -d "${LEGAL_INFO_DIR}/licenses" ]; then
        cp -a "${LEGAL_INFO_DIR}/licenses/." "${STAGING}/legal-info/licenses/"
    fi
    for f in manifest.csv buildroot.config legal-info.sha256 README; do
        if [ -f "${LEGAL_INFO_DIR}/${f}" ]; then
            cp -a "${LEGAL_INFO_DIR}/${f}" "${STAGING}/legal-info/"
            echo "Build file: ${f}"
        fi
    done
fi
mkdir -p "${STAGING}/legal-info"
cat > "${STAGING}/legal-info/SOURCE" <<'EOF'
PIDAP source and build files:
https://github.com/rodneyramsay/album_streamer

BusyBox source is included on this card in legal-info/sources/busybox-*
EOF
cat > "${STAGING}/legal-info/README.thirdparty" <<'EOF'
Third-party components used in this build:

Raspberry Pi firmware:
  https://github.com/raspberrypi/firmware
  License files in legal-info/licenses/rpi-firmware-*/

Bootlin external toolchain:
  https://toolchains.bootlin.com/
  License files in legal-info/licenses/toolchain-external-*/

Linux kernel (source available on request):
  https://github.com/raspberrypi/linux
  License files in legal-info/licenses/linux-custom/

Splash image:
  NASA C-1990-7066
  https://archive.org/details/C-1990-7066
EOF

# Recompute image size if not overridden to include legal info.
if [ -z "${USERDATA_SIZE}" ]; then
    DATA_BYTES=$(du -sb "${STAGING}" | awk '{print $1}')
    if [ "${DATA_BYTES}" -gt 0 ]; then
        WANTED=$(( DATA_BYTES + DATA_BYTES / 5 ))
        WANTED=$(( (WANTED + 67108863) / 67108864 * 67108864 ))
        MIN=$(( 128 * 1024 * 1024 ))
        [ "${WANTED}" -lt "${MIN}" ] && WANTED=${MIN}
        IMAGE_SIZE="${WANTED}"
    fi
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
