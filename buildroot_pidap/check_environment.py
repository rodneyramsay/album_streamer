#!/usr/bin/env python3
"""
Sanity-check that Buildroot is actually using the PIDAP br2-external tree.
Run from anywhere, e.g.:

    python3 /home/rodney/album_streamer/buildroot_pidap/check_environment.py

or with a non-default buildroot tree:

    BUILDROOT=/path/to/buildroot python3 /home/rodney/album_streamer/buildroot_pidap/check_environment.py
"""

import os
import re
import sys

EXTERNAL_DIR = os.path.dirname(os.path.abspath(__file__))


def load_config(path):
    """Parse a Buildroot .config or similar key=value file."""
    cfg = {}
    if not os.path.exists(path):
        return cfg
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("#") or not line.strip():
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                value = value.strip("\"")
                if value == "y":
                    value = True
                elif value == "n" or value.startswith("#"):
                    value = False
                cfg[key] = value
    return cfg


def expand(value, external_path):
    if not isinstance(value, str):
        return value
    return value.replace("$(BR2_EXTERNAL_PIDAP_PATH)", external_path)


def main():
    buildroot = os.environ.get("BUILDROOT")
    if not buildroot:
        buildroot = next(iter(sys.argv[1:]), None)
    if not buildroot:
        buildroot = "/home/rodney/buildroot"

    config_path = os.path.join(buildroot, ".config")
    if not os.path.exists(config_path):
        print(f"FAIL: .config not found at {config_path}")
        print("       Set BUILDROOT or pass the buildroot directory as an argument.")
        return 1

    cfg = load_config(config_path)
    errors = []
    warnings = []

    external_path = cfg.get("BR2_EXTERNAL_PIDAP_PATH")
    if not external_path:
        errors.append("BR2_EXTERNAL_PIDAP_PATH is not set (external tree not loaded?)")
    elif not os.path.isdir(external_path):
        errors.append(f"BR2_EXTERNAL_PIDAP_PATH does not exist: {external_path}")
    else:
        # Verify .config matches this exact br2-external tree
        if os.path.realpath(external_path) != os.path.realpath(EXTERNAL_DIR):
            errors.append(
                f"BR2_EXTERNAL_PIDAP_PATH ({external_path}) does not match "
                f"this tree ({EXTERNAL_DIR})"
            )

    # --- Rootfs overlay check ---
    overlay = cfg.get("BR2_ROOTFS_OVERLAY", "")
    if not overlay:
        errors.append("BR2_ROOTFS_OVERLAY is empty; the overlay will not be copied")
    else:
        expected = os.path.join("$(BR2_EXTERNAL_PIDAP_PATH)", "board/PIDAP/rootfs-overlay")
        if expected not in overlay:
            warnings.append(
                f"BR2_ROOTFS_OVERLAY ({overlay}) does not include the PIDAP overlay ({expected})"
            )

        for entry in overlay.split():
            expanded = expand(entry, external_path or EXTERNAL_DIR)
            if not os.path.isdir(expanded):
                errors.append(f"overlay directory missing: {expanded}")
            elif not os.listdir(expanded):
                warnings.append(f"overlay directory is empty: {expanded}")

    # --- Other board-specific files that should normally come from the external tree ---
    expected_post_image = f"$(BR2_EXTERNAL_PIDAP_PATH)/board/PIDAP/post-image.sh"
    if cfg.get("BR2_ROOTFS_POST_IMAGE_SCRIPT") != expected_post_image:
        warnings.append(
            f"BR2_ROOTFS_POST_IMAGE_SCRIPT is {cfg.get('BR2_ROOTFS_POST_IMAGE_SCRIPT')!r}, "
            f"expected {expected_post_image!r}"
        )

    expected_device_table = f"$(BR2_EXTERNAL_PIDAP_PATH)/board/PIDAP/device_table.txt"
    if cfg.get("BR2_ROOTFS_DEVICE_TABLE") != expected_device_table:
        warnings.append(
            f"BR2_ROOTFS_DEVICE_TABLE is {cfg.get('BR2_ROOTFS_DEVICE_TABLE')!r}, "
            f"expected {expected_device_table!r}"
        )

    expected_fw_config = f"$(BR2_EXTERNAL_PIDAP_PATH)/board/PIDAP/rootfs-overlay/boot/config.txt"
    if cfg.get("BR2_PACKAGE_RPI_FIRMWARE_CONFIG_FILE") != expected_fw_config:
        warnings.append(
            f"BR2_PACKAGE_RPI_FIRMWARE_CONFIG_FILE is {cfg.get('BR2_PACKAGE_RPI_FIRMWARE_CONFIG_FILE')!r}, "
            f"expected {expected_fw_config!r}"
        )

    # --- Print report ---
    print(f"Buildroot:     {buildroot}")
    print(f"External tree: {external_path or EXTERNAL_DIR}")
    print(f"Overlay:       {overlay!r}")
    print()

    if warnings:
        print("Warnings:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if errors:
        print("Errors:")
        for e in errors:
            print(f"  - {e}")
        print()
        print("Environment NOT OK")
        return 1

    if not warnings:
        print("Environment OK")
    else:
        print("Environment OK-ish (warnings above)")
    return 0 if not warnings else 0


if __name__ == "__main__":
    sys.exit(main())
