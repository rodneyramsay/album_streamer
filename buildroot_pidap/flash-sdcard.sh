#!/bin/bash
#
# Fast SD card flash for PIDAP.
# Partitions the card, writes boot/rootfs/pidap-data, then formats the user-data
# partition in place and copies the Music/ tree from the generated
# user-data.ext4 image.
#
# Usage:
#   ./flash-sdcard.sh all    # repartition everything, write boot+rootfs+pidap-data+user-data
#   ./flash-sdcard.sh data   # only reflash the user-data partition
#
# Set CARD to override the default /dev/sdc.

set -e

BUILDROOT_DIR="${BUILDROOT_DIR:-/home/rodney/buildroot}"
IMAGES_DIR="${BUILDROOT_DIR}/output/images"
CARD="${CARD:-/dev/sdc}"
PIDAP_DATA_SIZE_M="${PIDAP_DATA_SIZE_M:-1}"
PART3="${CARD}3"
PART4="${CARD}4"

case "$1" in
    all)
        ;;
    data)
        ;;
    *)
        echo "Usage: $0 {all|data}"
        exit 1
        ;;
esac

for img in boot.vfat rootfs.ext2 user-data.ext4 pidap-data.ext4; do
    if [ ! -f "${IMAGES_DIR}/${img}" ]; then
        echo "ERROR: ${IMAGES_DIR}/${img} not found. Run 'make -C ${BUILDROOT_DIR}' first."
        exit 1
    fi
done

# Size the rootfs partition to fit the image, plus a 10 MiB safety margin.
# The small pidap-data partition is sliced from that margin.
ROOTFS_BYTES=$(wc -c < "${IMAGES_DIR}/rootfs.ext2")
ROOTFS_M=$(( (ROOTFS_BYTES + 1048575) / 1048576 + 10 ))
ROOTFS_PART_M=$(( ROOTFS_M - PIDAP_DATA_SIZE_M ))

# Optional user-data partition cap in GiB (0 = use the rest of the card).
MAX_USERDATA_G="${MAX_USERDATA_G:-0}"
USERDATA_IMG_BYTES=$(wc -c < "${IMAGES_DIR}/user-data.ext4")
USERDATA_IMG_M=$(( (USERDATA_IMG_BYTES + 1048575) / 1048576 ))
# Minimum partition size: image plus a small margin for VFAT filesystem overhead.
USERDATA_MIN_M=$(( USERDATA_IMG_M + 64 ))
USERDATA_PART_M=${USERDATA_MIN_M}
if [ "${MAX_USERDATA_G}" -gt 0 ] 2>/dev/null; then
    CAP_M=$(( MAX_USERDATA_G * 1024 ))
    if [ "${USERDATA_MIN_M}" -gt "${CAP_M}" ]; then
        echo "Warning: user-data image needs ${USERDATA_MIN_M}M but cap is ${CAP_M}M; using ${USERDATA_MIN_M}M"
    else
        echo "User-data partition cap is ${CAP_M}M; image fits in ${USERDATA_MIN_M}M"
        USERDATA_PART_M=${CAP_M}
    fi
    SFDISK_USERDATA_LINE=", ${USERDATA_PART_M}M, 83,"
else
    echo "User-data image is ${USERDATA_IMG_M}M; user-data partition will use rest of card"
    # An empty size field in the last sfdisk line means "use the rest of the disk".
    SFDISK_USERDATA_LINE=",,83,"
fi

echo "Flashing ${CARD}..."

# Unmount anything on the target card
for p in 1 2 3 4; do
    umount "${CARD}${p}" 2>/dev/null || true
done

if [ "$1" = "all" ]; then
    echo "Creating partition table..."
    # 128 MiB boot (FAT32, bootable), rootfs, small pidap-data, then user-data.
    # Everything after boot will end up with 1 MiB alignment.
    sfdisk --quiet --wipe always "${CARD}" <<EOF
, 128M, c, *
, ${ROOTFS_PART_M}M, 83,
, ${PIDAP_DATA_SIZE_M}M, 83,
${SFDISK_USERDATA_LINE}
EOF
    partprobe "${CARD}" 2>/dev/null || true
    sleep 1

    echo "Writing boot.vfat..."
    dd if="${IMAGES_DIR}/boot.vfat" of="${CARD}1" bs=4M status=progress conv=fsync

    echo "Writing rootfs.ext2..."
    dd if="${IMAGES_DIR}/rootfs.ext2" of="${CARD}2" bs=4M status=progress conv=fsync

    echo "Writing pidap-data.ext4..."
    dd if="${IMAGES_DIR}/pidap-data.ext4" of="${PART3}" bs=4M status=progress conv=fsync
fi

# In data-only mode the user-data partition must already exist.
if [ "$1" = "data" ] && [ ! -b "${PART4}" ]; then
    echo "ERROR: ${PART4} does not exist; run '$0 all' first to create the partition table"
    exit 1
fi

echo "Formatting user-data partition..."
mkfs.vfat -F 32 -n user-data "${PART4}" || mkfs.vfat -n user-data "${PART4}"

MNT_DATA=$(mktemp -d)
MNT_SRC=$(mktemp -d)

cleanup() {
    umount "${MNT_SRC}" 2>/dev/null || true
    umount "${MNT_DATA}" 2>/dev/null || true
    rmdir "${MNT_SRC}" 2>/dev/null || true
    rmdir "${MNT_DATA}" 2>/dev/null || true
}
trap cleanup EXIT

mount -o loop "${IMAGES_DIR}/user-data.ext4" "${MNT_SRC}"
mount "${PART4}" "${MNT_DATA}"

if [ -d "${MNT_SRC}/Music" ]; then
    echo "Copying Music/..."
    cp -rL "${MNT_SRC}/Music/." "${MNT_DATA}/" 2>/dev/null || true
else
    echo "Copying music to user-data root..."
    cp -rL "${MNT_SRC}/." "${MNT_DATA}/" 2>/dev/null || true
fi

sync

echo "Done. ${CARD} is ready."
