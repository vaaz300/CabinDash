#!/usr/bin/env python3
"""Draws the 1024x1024 app icon (a speed dial on a dusk wallpaper) into the asset catalog.

Needs Pillow. Run from the project folder:  python3 scripts/make_icon.py
"""
import colorsys
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2  # draw at 2x and shrink for smooth edges
S = SIZE * SCALE
OUT = pathlib.Path(__file__).resolve().parent.parent / "CabinDash/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def hsv(h, s, v, a=255):
    r, g, b = colorsys.hsv_to_rgb(h / 360, s, v)
    return (int(r * 255), int(g * 255), int(b * 255), a)


def trail(color, cx, cy, length, thickness, angle, blur):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        (cx - length / 2, cy - thickness / 2, cx + length / 2, cy + thickness / 2),
        radius=thickness / 2,
        fill=color,
    )
    layer = layer.rotate(angle, center=(cx, cy), resample=Image.BICUBIC)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def point(cx, cy, r, degrees):
    a = math.radians(degrees)
    return cx + math.cos(a) * r, cy + math.sin(a) * r


def main():
    img = Image.new("RGBA", (S, S), (5, 6, 11, 255))

    # Wallpaper: three soft trails of light (the "dusk" hues of the app).
    for hue, (cx, cy, length, thick) in zip(
        (285, 28, 215),
        ((0.30, 0.15, 1.5, 0.26), (0.85, 0.55, 1.4, 0.2), (0.22, 0.95, 1.5, 0.24)),
    ):
        layer = trail(hsv(hue, 0.82, 0.95, 170), cx * S, cy * S, length * S, thick * S, 32, S * 0.065)
        img = Image.alpha_composite(img, layer)

    c = S / 2
    cy = c + S * 0.07  # a 240 degree dial sits high in its box, so move it down to centre it visually
    radius = S * 0.31
    width = S * 0.075
    box = (c - radius, cy - radius, c + radius, cy + radius)
    start, sweep = 150, 240
    white = (255, 255, 255)

    # Translucent parts go on their own layer, then are blended onto the wallpaper.
    soft = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(soft)
    sd.arc(box, start, start + sweep, fill=white + (52,), width=int(width))
    for deg in (start, start + sweep):
        x, y = point(c, cy, radius, deg)
        sd.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=white + (52,))
    img = Image.alpha_composite(img, soft)

    ticks = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(ticks)
    for i in range(41):
        deg = start + i * 6
        major = i % 5 == 0
        r_out = radius - width / 2 - S * 0.022
        r_in = r_out - (S * 0.038 if major else S * 0.02)
        td.line(
            [point(c, cy, r_in, deg), point(c, cy, r_out, deg)],
            fill=white + (170 if major else 90,),
            width=int(S * (0.006 if major else 0.003)),
        )
    img = Image.alpha_composite(img, ticks)

    d = ImageDraw.Draw(img)

    # Fill, with round ends
    fraction = 0.64
    orange = (255, 159, 10, 255)
    d.arc(box, start, start + sweep * fraction, fill=orange, width=int(width))
    for deg in (start, start + sweep * fraction):
        x, y = point(c, cy, radius, deg)
        d.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=orange)

    # Needle and hub
    tip = point(c, cy, radius - width * 1.9, start + sweep * fraction)
    d.line([(c, cy), tip], fill=white + (255,), width=int(S * 0.028))
    d.ellipse((tip[0] - S * 0.014, tip[1] - S * 0.014, tip[0] + S * 0.014, tip[1] + S * 0.014), fill=white + (255,))
    hub = S * 0.052
    d.ellipse((c - hub, cy - hub, c + hub, cy + hub), fill=white + (255,))
    d.ellipse((c - hub * 0.45, cy - hub * 0.45, c + hub * 0.45, cy + hub * 0.45), fill=(5, 6, 11, 255))

    out = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)  # no alpha: the App Store rejects transparent icons
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, "PNG", optimize=True)
    print("wrote", OUT, out.size, out.mode)


if __name__ == "__main__":
    main()
