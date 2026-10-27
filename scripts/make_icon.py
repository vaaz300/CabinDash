#!/usr/bin/env python3
"""Builds the app icon from the artwork in design/icon-source.png.

The artwork is a glass tile on a black square. iOS rounds the corners of every app icon itself, so the black margin
around the tile would show as a second, smaller icon inside the first. This script finds the tile, centres it, and crops
the margin down so the tile fills the icon, then writes the 1024 x 1024 RGB PNG the asset catalogue needs.
iOS refuses icons with transparency, so the result has no alpha channel (scripts/ci/check_repo.py checks that on every build).

Usage:  python3 scripts/make_icon.py        (needs Pillow: pip install pillow)
"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "icon-source.png"
OUT = ROOT / "CabinDash" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

SIZE = 1024
# The tile's share of the icon's width. A little under 1 keeps its glass rim clear of the corners that iOS rounds off.
FILL = 0.94
# Brightness (0-255) above which a pixel counts as the tile's rim. The glow around the tile is dimmer than this.
RIM = 100


def main() -> int:
    source = Image.open(SOURCE).convert("RGB")
    box = source.convert("L").point(lambda value: 255 if value > RIM else 0).getbbox()
    if box is None:
        print(f"Could not find the tile in {SOURCE}.", file=sys.stderr)
        return 1
    left, top, right, bottom = box
    side = round(max(right - left, bottom - top) / FILL)
    x = round((left + right) / 2 - side / 2)
    y = round((top + bottom) / 2 - side / 2)

    # A square of `side` pixels centred on the tile. Black fills anything that falls outside the source.
    square = Image.new("RGB", (side, side), (0, 0, 0))
    square.paste(source, (-x, -y))
    icon = square.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, optimize=True)
    print(f"Tile found at {box}; cropped a {side} px square at ({x}, {y}); wrote {OUT.relative_to(ROOT)} ({SIZE} x {SIZE}, RGB).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
