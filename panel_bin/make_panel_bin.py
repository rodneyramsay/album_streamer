#!/usr/bin/env python3
"""Convert a text MIPI DBI command list into a panel-mipi-dbi-spi .bin file.

Text format (one per line):
  command 0x01 0x70 ...
  delay 150

Lines starting with '#' or blank are ignored.
"""

import argparse
import re
import struct
import sys


MAGIC = b"MIPI DBI" + b"\x00" * 7
VERSION = 1


def parse_hex(token):
    token = token.strip()
    if token.startswith("0x") or token.startswith("0X"):
        return int(token, 16)
    if token.startswith("0b"):
        return int(token, 2)
    if token.startswith("0") and len(token) > 1:
        return int(token, 8)
    return int(token)


def build_bin(cmds, fmt=0):
    buf = bytearray()
    buf.extend(MAGIC)
    buf.append(VERSION)

    for line in cmds:
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if not parts:
            continue

        keyword = parts[0].lower()
        if keyword == "command":
            vals = [parse_hex(p) for p in parts[1:]]
            if not vals:
                raise ValueError(f"command needs at least a command byte: {line}")
            if any(not 0 <= v <= 255 for v in vals):
                raise ValueError(f"command values must be bytes: {line}")
            buf.append(vals[0])
            params = vals[1:]
            if len(params) > 255:
                raise ValueError(f"too many parameters: {line}")
            buf.append(len(params))
            buf.extend(params)
        elif keyword == "delay":
            if len(parts) != 2:
                raise ValueError(f"delay takes one argument: {line}")
            ms = parse_hex(parts[1])
            if not 0 <= ms <= 255:
                raise ValueError(f"delay must be a single byte (ms): {line}")
            # NOP (0x00) with one parameter = sleep
            buf.append(0x00)
            buf.append(1)
            buf.append(ms)
        else:
            raise ValueError(f"unknown keyword: {keyword}")

    return bytes(buf)


def main():
    parser = argparse.ArgumentParser(description="Build panel-mipi-dbi-spi firmware binary")
    parser.add_argument("input", help="text command file")
    parser.add_argument("output", help="output .bin file")
    args = parser.parse_args()

    with open(args.input, "r") as f:
        cmds = f.readlines()

    binary = build_bin(cmds)

    with open(args.output, "wb") as f:
        f.write(binary)

    print(f"Wrote {len(binary)} bytes to {args.output}")


if __name__ == "__main__":
    main()
