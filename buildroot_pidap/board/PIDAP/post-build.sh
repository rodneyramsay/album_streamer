#!/bin/sh
#
# Post-build cleanup for the release (standalone) PIDAP image.
# Only trims network/cron bits; dev builds keep everything.
#

set -e

# Buildroot runs post-build scripts from the buildroot top directory,
# so .config is available here and TARGET_DIR is in the environment.
if grep -q '^# BR2_PACKAGE_OPENSSH is not set' .config 2>/dev/null; then
    rm -f "${TARGET_DIR}/etc/init.d/S39wait-eth0"
    rm -f "${TARGET_DIR}/etc/init.d/S41static-eth"
    rm -f "${TARGET_DIR}/etc/init.d/S50crond"
    rm -f "${TARGET_DIR}/etc/network/interfaces"
fi
