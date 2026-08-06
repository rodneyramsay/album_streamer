#!/home/rodney/venv/bin/python3
"""
pidap_display - show artist/album/track on the console TFT.

Usage:
    /home/rodney/venv/bin/python3 pidap_display.py -a "Artist" -l "Album" -t "Track"
    ./pidap_display -a "Artist" -l "Album" -t "Track"

This writes to the framebuffer console, so it needs no SPI/st7789.
"""

import argparse
import os
import sys

DEFAULT_TTY = "/dev/tty1"
BOLD_GREEN = "\033[1;32m"
RESET = "\033[0m"


def display_text(artist, album, track, tty=DEFAULT_TTY):
    """Print three bright-green lines at the bottom of the console, overwriting the previous display."""
    try:
        with open(tty, "w") as fh:
            try:
                size = os.get_terminal_size(fh.fileno())
            except OSError:
                size = os.terminal_size((30, 30))

            # Use a fixed 3-line block at the bottom of the console.
            rows = max(3, size.lines)
            cols = size.columns
            start_row = rows - 2  # 1-based, so lines 28-30 for a 30-line screen

            # Hide cursor, move to start row, and clear from there to the end.
            fh.write(f"\033[?25l\033[{start_row};1H\033[0J")

            for i, line in enumerate((artist, album, track)):
                # Truncate to one screen line to avoid wrapping off the bottom.
                text = str(line)[:cols] if line else ""
                fh.write(f"{BOLD_GREEN}{text}{RESET}")
                if i < 2:
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
