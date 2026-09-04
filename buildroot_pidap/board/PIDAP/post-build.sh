#!/bin/sh
#
# Post-build cleanup for the release (standalone) PIDAP image.
# Only trims network/cron bits; dev builds keep everything.
#

set -e

# Release build has no openssh => remove the sshd init script.
if [ ! -f "${TARGET_DIR}/usr/sbin/sshd" ]; then
    rm -f "${TARGET_DIR}/etc/init.d/S50sshd"
fi

# Release build has no ifupdown => remove the network init scripts.
if [ ! -x "${TARGET_DIR}/usr/sbin/ifup" ]; then
    rm -f "${TARGET_DIR}/etc/init.d/S39wait-eth0"
    rm -f "${TARGET_DIR}/etc/init.d/S40network"
    rm -f "${TARGET_DIR}/etc/init.d/S41static-eth"
    rm -f "${TARGET_DIR}/etc/network/interfaces"
fi

# Remove cron in all builds (not used).
rm -f "${TARGET_DIR}/etc/init.d/S50crond"
