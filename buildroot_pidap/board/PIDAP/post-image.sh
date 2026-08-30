#!/bin/bash

set -e

BOARD_DIR="$(dirname $0)"
BOARD_NAME="$(basename ${BOARD_DIR})"
GENIMAGE_CFG="${BOARD_DIR}/genimage-${BOARD_NAME}.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Compile the Pirate Audio TFT overlay (if dtc is available).
# This must happen before genimage.cfg is generated, so the overlay gets
# included in the boot (vfat) image.
DTC="${HOST_DIR:-}/bin/dtc"
if [ -x "${DTC}" ] && [ -f "${BOARD_DIR}/pirate-tft.dts" ]; then
    echo "Compiling Pirate Audio TFT overlay..."
    mkdir -p "${BINARIES_DIR}/rpi-firmware/overlays"
    "${DTC}" -@ -I dts -O dtb -o "${BINARIES_DIR}/rpi-firmware/overlays/pirate-tft.dtbo" "${BOARD_DIR}/pirate-tft.dts"
fi

# Use the project's custom cmdline.txt on the boot partition
cp -f "${BOARD_DIR}/cmdline.txt" "${BINARIES_DIR}/rpi-firmware/cmdline.txt"

# generate genimage from template if a board specific variant doesn't exists
if [ ! -e "${GENIMAGE_CFG}" ]; then
	GENIMAGE_CFG="${BINARIES_DIR}/genimage.cfg"
	FILES=()

	for i in "${BINARIES_DIR}"/*.dtb "${BINARIES_DIR}"/rpi-firmware/*; do
		# only regular files -- skip the overlays/ subdir (handled below)
		[ -f "$i" ] || continue
		FILES+=( "${i#${BINARIES_DIR}/}" )
	done

	for i in "${BINARIES_DIR}"/rpi-firmware/overlays/*; do
		[ -f "$i" ] || continue
		FILES+=( "${i#${BINARIES_DIR}/}" )
	done

	KERNEL=$(sed -n 's/^kernel=//p' "${BINARIES_DIR}/rpi-firmware/config.txt")
	FILES+=( "${KERNEL}" )

	BOOT_FILES=""
	for f in "${FILES[@]}"; do
		dest="${f#rpi-firmware/}"
		BOOT_FILES="${BOOT_FILES}$(printf '\\tfile %s {\\n\\t\\timage = "%s"\\n\\t}\\n' "${dest}" "${f}")"
	done

	sed "s|#BOOT_FILES#|${BOOT_FILES}|" "${BOARD_DIR}/genimage.cfg.in" \
		> "${GENIMAGE_CFG}"
fi

# Pass an empty rootpath. genimage makes a full copy of the given rootpath to
# ${GENIMAGE_TMP}/root so passing TARGET_DIR would be a waste of time and disk
# space. We don't rely on genimage to build the rootfs image, just to insert a
# pre-built one in the disk image.

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

# Create the writable /usr/local music partition image
FAKEROOT="${HOST_DIR:-}/bin/fakeroot"
[ -x "${FAKEROOT}" ] || FAKEROOT="fakeroot"
"${FAKEROOT}" -- "${BOARD_DIR}/mkuserimg.sh"

rm -rf "${GENIMAGE_TMP}"

genimage \
	--rootpath "${ROOTPATH_TMP}"   \
	--tmppath "${GENIMAGE_TMP}"    \
	--inputpath "${BINARIES_DIR}"  \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"

exit $?
