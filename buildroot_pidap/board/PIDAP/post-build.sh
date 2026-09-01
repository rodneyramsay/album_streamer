#!/bin/sh
#
# Post-build cleanup for the release (standalone) PIDAP image.
# Only trims network/cron bits; dev builds keep everything.
#

set -e

# Strip release-image network/cron init scripts; openssh can still be
# installed but we don't need eth0 to be configured.
rm -f "${TARGET_DIR}/etc/init.d/S39wait-eth0"
rm -f "${TARGET_DIR}/etc/init.d/S40network"
rm -f "${TARGET_DIR}/etc/init.d/S41static-eth"
rm -f "${TARGET_DIR}/etc/init.d/S50crond"
rm -f "${TARGET_DIR}/etc/init.d/S50sshd"
rm -f "${TARGET_DIR}/etc/network/interfaces"
