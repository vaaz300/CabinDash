#!/usr/bin/env python3
"""Puts one of Spotify's own images into the app's asset catalogue.

Spotify's design guidelines ask for their own artwork wherever their content appears, and say not to redraw it. The files
come from Spotify's design page (https://developer.spotify.com/documentation/design). The asset names Cabin Dash uses:

    SpotifyIcon       the white icon, next to "Open Spotify" on the dark Music screen
    SpotifyIconGreen  the green icon, on the black Music button in the dock
    SpotifyLike       Spotify's "add to Liked Songs" icon
    SpotifyLiked      Spotify's "in Liked Songs" icon

    python3 scripts/add_spotify_icon.py path/to/Spotify_Primary_Logo_RGB_White.png            (SpotifyIcon)
    python3 scripts/add_spotify_icon.py path/to/Spotify_Primary_Logo_RGB_Green.png SpotifyIconGreen

The script only copies the file and writes the asset catalogue's Contents.json. It does not resize, recolour or redraw
anything. Without an asset Cabin Dash falls back to its own plain look (the word "Spotify", a heart, a music note).
Commit the new .imageset folder afterwards. Standard library only.
"""
import json
import pathlib
import shutil
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOGUE = pathlib.Path("CabinDash") / "Assets.xcassets"
NAMES = ("SpotifyIcon", "SpotifyIconGreen", "SpotifyLike", "SpotifyLiked")
# Spotify's guidelines give 21 px as the smallest the icon may be shown.
MINIMUM = 21
SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_size(data: bytes):
    """(width, height) from a PNG's header, or None when this is not a PNG."""
    if len(data) < 24 or data[:8] != SIGNATURE or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def install(source: pathlib.Path, root: pathlib.Path = ROOT, name: str = "SpotifyIcon") -> int:
    """Copies `source` into the catalogue under `root` as asset `name`. Returns 0, or 1 after saying what is wrong."""
    if name not in NAMES:
        return fail(f"{name} is not one of the asset names Cabin Dash uses: {', '.join(NAMES)}.")
    try:
        data = pathlib.Path(source).read_bytes()
    except OSError as error:
        return fail(f"Could not read {source}: {error.strerror or error}.")

    size = png_size(data)
    if size is None:
        return fail(f"{source} is not a PNG file. Download the PNG version of the icon.")
    width, height = size
    # Spotify's own 2024 icon files are 939 x 940 px, so one pixel either way still counts as square.
    if abs(width - height) > 1:
        return fail(f"The icon must be square, but {source} is {width} x {height} px. Use the file as Spotify provides it.")
    if width < MINIMUM:
        return fail(f"The icon must be at least {MINIMUM} px square, but {source} is {width} x {height} px.")

    imageset = CATALOGUE / f"{name}.imageset"
    filename = f"{name}.png"
    target = root / imageset
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target / filename)
    contents = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (target / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"Installed {width} x {height} px image as {imageset / filename}. Commit {imageset} to use it.")
    return 0


def main(argv) -> int:
    if len(argv) not in (2, 3):
        return fail(f"Usage: python3 scripts/add_spotify_icon.py path/to/image.png [{' | '.join(NAMES)}]")
    return install(pathlib.Path(argv[1]), name=argv[2] if len(argv) == 3 else "SpotifyIcon")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
