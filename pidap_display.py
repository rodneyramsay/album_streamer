#!/usr/bin/env python3
"""
pidap_display - Display two lines of text on the Pirate Audio ST7789 LCD.

Usage:
    python3 pidap_display.py "Album Name" "Track Name"
    python3 pidap_display.py               # defaults to "Hello" / "World"

The display settings match the Pirate Audio Headphone Amp board by default:
240x240 ST7789 over SPI, rotation 90, CS=1, DC=9, backlight=13.
"""

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as e:
    print(f"Error: PIL/Pillow image library not installed. {e}", file=sys.stderr)
    print("Install it with one of:", file=sys.stderr)
    print("  sudo apt install python3-pil", file=sys.stderr)
    print("  sudo pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

try:
    import ST7789
except ImportError as e:
    print(f"Error: ST7789 Python library not installed. {e}", file=sys.stderr)
    print("Install it with:  sudo pip3 install st7789", file=sys.stderr)
    sys.exit(1)


def get_font(size, prefer_ttf=True):
    """Try to load a TrueType font, fall back to PIL's default if not found."""
    ttf_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    if prefer_ttf:
        for path in ttf_paths:
            if os.path.exists(path):
                try:
                    return ImageFont.truetype(path, size)
                except OSError:
                    pass
    return ImageFont.load_default()


def text_size(draw, text, font):
    """Return the (width, height) of the given text using the current font."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def fit_text_to_width(text, max_width, font, draw):
    """Return (font, wrapped_lines) sized so each wrapped line fits max_width."""
    size = font.size if hasattr(font, "size") else 20
    while size >= 8:
        test_font = font.font_variant(size=size) if hasattr(font, "font_variant") else font
        words = text.split()
        lines = []
        line = ""
        for word in words:
            candidate = f"{line} {word}".strip()
            w, _ = text_size(draw, candidate, test_font)
            if w <= max_width:
                line = candidate
            else:
                if line:
                    lines.append(line)
                line = word
        if line:
            lines.append(line)
        # All lines must fit
        if all(text_size(draw, ln, test_font)[0] <= max_width for ln in lines):
            return test_font, lines
        size -= 1
    # Fallback: the text just won't fit, return last attempt
    return test_font, lines


def display_text(line1, line2):
    """Initialize the LCD and draw the two supplied strings."""
    disp = ST7789.ST7789(
        rotation=90,
        port=0,
        cs=1,
        dc=9,
        backlight=13,
        spi_speed_hz=80 * 1000 * 1000,
        width=240,
        height=240,
    )
    disp.begin()

    width = disp.width
    height = disp.height

    img = Image.new("RGB", (width, height), (0, 0, 0))
    draw = ImageDraw.Draw(img)

    font = get_font(26)

    # Leave a small margin on each side
    margin = 10
    max_width = width - 2 * margin

    font1, lines1 = fit_text_to_width(line1, max_width, font, draw)
    font2, lines2 = fit_text_to_width(line2, max_width, font, draw)

    all_lines = lines1 + lines2
    if not all_lines:
        all_lines = [" "]

    # Use the smaller of the two fonts to keep everything consistent
    final_size = min(font1.size if hasattr(font1, "size") else 26,
                     font2.size if hasattr(font2, "size") else 26)
    final_font = font1.font_variant(size=final_size) if hasattr(font1, "font_variant") else font1

    # Calculate total block height to center vertically
    line_heights = [text_size(draw, ln, final_font)[1] for ln in all_lines]
    total_height = sum(line_heights) + (len(all_lines) - 1) * 4  # 4px interline
    y = (height - total_height) // 2

    for i, line in enumerate(all_lines):
        w, h = text_size(draw, line, final_font)
        x = (width - w) // 2
        # Use a bright colour for the first line, slightly dimmer for the second
        colour = (255, 255, 255) if i < len(lines1) else (200, 200, 200)
        draw.text((x, y), line, font=final_font, fill=colour)
        y += h + 4

    disp.display(img)


def main():
    line1 = sys.argv[1] if len(sys.argv) > 1 else "Hello"
    line2 = sys.argv[2] if len(sys.argv) > 2 else "World"
    display_text(line1, line2)


if __name__ == "__main__":
    main()
