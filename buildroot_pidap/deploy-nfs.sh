#!/bin/bash
#
# Update the host NFS export after buildroot has generated a new rootfs image.
# Run this after `make` (it needs root for mount/exportfs).
#
# Usage: sudo ./deploy-nfs.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BUILDROOT="${BUILDROOT:-/home/rodney/buildroot}"
IMAGES_DIR="${BUILDROOT}/output/images"
EXPORT_DIR="/srv/nfs/pidap"
ROOTFS="${IMAGES_DIR}/rootfs.ext2"

# Pick the client IP from the PIDAP cmdline.txt
CLIENT_IP=$(grep -oE 'ip=[0-9.]+' "${SCRIPT_DIR}/board/PIDAP/cmdline.txt" | head -1 | cut -d'=' -f2)
if [ -z "${CLIENT_IP}" ]; then
    echo "ERROR: could not parse client IP from board/PIDAP/cmdline.txt" >&2
    exit 1
fi

# Use sudo if not already root
SUDO=""
if [ "${EUID}" -ne 0 ]; then
    SUDO="sudo"
fi

# Ensure the export directory exists
${SUDO} mkdir -p "${EXPORT_DIR}"

# Replace the export line in /etc/exports so it is always correct
# (insecure is needed for the Pi NFS client, which uses high source ports)
echo "Updating /etc/exports for ${CLIENT_IP}"
${SUDO} sed -i "\|^${EXPORT_DIR}|d" /etc/exports
${SUDO} sh -c "echo '${EXPORT_DIR} ${CLIENT_IP}(rw,no_root_squash,no_subtree_check,insecure,async)' >> /etc/exports"

# Unmount the old rootfs if already mounted
if mountpoint -q "${EXPORT_DIR}"; then
    ${SUDO} umount "${EXPORT_DIR}"
fi

# Mount the new rootfs image over the export directory
if [ ! -f "${ROOTFS}" ]; then
    echo "ERROR: ${ROOTFS} not found. Run 'make' first." >&2
    exit 1
fi

echo "Mounting ${ROOTFS} on ${EXPORT_DIR}"
${SUDO} mount -o loop,rw "${ROOTFS}" "${EXPORT_DIR}"

# Refresh the NFS export
${SUDO} exportfs -r

echo "NFS export updated for ${CLIENT_IP}: ${EXPORT_DIR}"
