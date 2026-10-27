#!/usr/bin/env python3
"""Puts Spotify's icon into the app's asset catalogue, so Cabin Dash can show it next to "Open Spotify".

Spotify's design guidelines ask for their own icon or logo wherever their content appears, and say not to redraw it.
The artwork can only be taken from Spotify's guidelines page, and this project's build environment cannot download it,
so it is not bundled. Download the icon (a PNG, at least 21 px square) from
https://developer.spotify.com/documentation/design and run:

    python3 scripts/add_spotify_icon.py path/to/Spotify_Primary_Logo_RGB_Green.png

The script only copies the file and writes the asset catalogue's Contents.json. It does not resize, recolour or redraw
anything. Until it has been run, Cabin Dash shows the plain word "Spotify" instead of a look-alike mark.
Commit CabinDash/Assets.xcassets/SpotifyIcon.imageset afterwards. Standard library only.
"""
import json
import pathlib
import shutil
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGESET = pathlib.Path("CabinDash") / "Assets.xcassets" / "SpotifyIcon.imageset"
FILENAME = "SpotifyIcon.png"
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


def install(source: pathlib.Path, root: pathlib.Path = ROOT) -> int:
    """Copies `source` into the catalogue under `root`. Returns 0, or 1 after saying what is wrong."""
    try:
        data = pathlib.Path(source).read_bytes()
    except OSError as error:
        return fail(f"Could not read {source}: {error.strerror or error}.")

    size = png_size(data)
    if size is None:
        return fail(f"{source} is not a PNG file. Download the PNG version of the icon.")
    width, height = size
    if width != height:
        return fail(f"The icon must be square, but {source} is {width} x {height} px. Use the file as Spotify provides it.")
    if width < MINIMUM:
        return fail(f"The icon must be at least {MINIMUM} px square, but {source} is {width} x {height} px.")

    target = root / IMAGESET
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target / FILENAME)
    contents = {
        "images": [{"filename": FILENAME, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (target / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"Installed {width} x {height} px icon as {IMAGESET / FILENAME}. Commit {IMAGESET} to use it.")
    return 0


def main(argv) -> int:
    if len(argv) != 2:
        return fail("Usage: python3 scripts/add_spotify_icon.py path/to/spotify-icon.png")
    return install(pathlib.Path(argv[1]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
