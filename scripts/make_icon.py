#!/usr/bin/env python3
"""Draws the app icon: the Cabin Dash mark (the two halves of the "CD" ring and the arrow) flat on black.

The mark is drawn as shapes, measured from the original glass artwork in design/icon-source.png, so it stays sharp
at every size: no glass tile, glow or reflections, one solid silver. It is drawn four times larger than needed and
scaled down for smooth edges, then written as the 1024 x 1024 RGB PNG the asset catalogue needs. iOS refuses icons with
transparency, so the result has no alpha channel (scripts/ci/check_repo.py checks that on every build).

Usage:  python3 scripts/make_icon.py        (needs Pillow: pip install pillow)
"""
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "CabinDash" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

SIZE = 1024
SCALE = 4                      # drawn at 4096 px, then scaled down
SILVER = (214, 217, 222)
BLACK = (0, 0, 0)

# Measured on the original 1024 px icon. The ring is a horizontal stadium cut through the middle; the arrow sits a little
# left of and below the ring's centre, as in the original.
RING_OUTER = (178, 285, 853, 739)   # left, top, right, bottom
RING_STROKE = 86
GAP = (496, 541)                    # the cut between the two halves
ARROW = [(400, 509), (599, 425), (539, 621), (495, 537)]
SHIFT_X = 512 - (178 + 853) / 2     # centres the ring horizontally


def scaled(x, y):
    return ((x + SHIFT_X) * SCALE, y * SCALE)


def smooth(mask, radius):
    """Rounds the corners a little, as on the original."""
    return mask.filter(ImageFilter.GaussianBlur(radius * SCALE)).point(lambda value: 255 if value > 127 else 0)


def mark():
    side = SIZE * SCALE
    ring = Image.new("L", (side, side), 0)
    draw = ImageDraw.Draw(ring)
    left, top, right, bottom = RING_OUTER
    (x0, y0), (x1, y1) = scaled(left, top), scaled(right, bottom)
    stroke = RING_STROKE * SCALE
    draw.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) / 2, fill=255)
    draw.rounded_rectangle([x0 + stroke, y0 + stroke, x1 - stroke, y1 - stroke], radius=(y1 - y0) / 2 - stroke, fill=0)
    gap_left, _ = scaled(GAP[0], 0)
    gap_right, _ = scaled(GAP[1], 0)
    draw.rectangle([gap_left, 0, gap_right, side], fill=0)

    arrow = Image.new("L", (side, side), 0)
    ImageDraw.Draw(arrow).polygon([scaled(x, y) for x, y in ARROW], fill=255)
    return ImageChops.lighter(smooth(ring, 2.5), smooth(arrow, 3.5))


def main() -> int:
    side = SIZE * SCALE
    icon = Image.new("RGB", (side, side), BLACK)
    icon.paste(Image.new("RGB", (side, side), SILVER), (0, 0), mark())
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, optimize=True)
    print(f"Wrote {OUT.relative_to(ROOT)} ({SIZE} x {SIZE}, RGB).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
