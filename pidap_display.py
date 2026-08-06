#!/home/rodney/venv/bin/python3
"""
pidap_display - show artist/album/track on the console TFT.

Usage:
    /home/rodney/venv/bin/python3 pidap_display.py -a "Artist" -l "Album" -t "Track"
    ./pidap_display -a "Artist" -l "Album" -t "Track"

This writes to the framebuffer console, so it needs no SPI/st7789.
"""

import argparse
import sys

DEFAULT_TTY = "/dev/tty1"
GREEN = "\033[32m"
RESET = "\033[0m"


def display_text(artist, album, track, tty=DEFAULT_TTY):
    """Print three green lines to the console."""
    try:
        with open(tty, "w") as fh:
            for line in (artist, album, track):
                fh.write(f"{GREEN}{line}{RESET}\n")
            fh.write("\n")
    except OSError as e:
        print(f"Error writing to {tty}: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Display artist, album and track on the console TFT."
    )
    parser.add_argument("-a", "--artist", default="Artist", help="Artist name")
    parser.add_argument("-l", "--album", default="Album", help="Album name")
    parser.add_argument("-t", "--track", default="Track", help="Track name")
    parser.add_argument("--tty", default=DEFAULT_TTY, help="Console TTY device")
    args = parser.parse_args()

    display_text(args.artist, args.album, args.track, tty=args.tty)


if __name__ == "__main__":
    main()
