#!/usr/bin/env python3
"""Fails early, with a plain message, when the repository is not laid out the way the build expects.

Catches the mistakes most likely on a first upload from Windows:
  * the project folder was uploaded instead of its contents, so project.yml is one level too deep;
  * signing material (a .p8 key, a .p12 certificate, a provisioning profile) ended up in the repository;
  * the app icon is one iOS refuses: not 1024 x 1024, or with transparency.
"""
import pathlib
import re
import struct
import sys

import ghactions

ROOT = pathlib.Path(__file__).resolve().parents[2]

ICON = "CabinDash/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

REQUIRED = [
    "project.yml",
    "CabinCore/Package.swift",
    "CabinDash/CabinDashApp.swift",
    "CabinDash/PrivacyInfo.xcprivacy",
    ICON,
    "Config/Info.plist",
    "Config/Signing.xcconfig",
]

SECRET_SUFFIXES = {".p8", ".p12", ".cer", ".certsigningrequest", ".mobileprovision", ".provisionprofile"}
# A PEM header followed by a real-looking base64 body. Requiring the body avoids flagging documentation
# or tests that merely mention the header.
PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----\s*[A-Za-z0-9+/=]{40,}")
SKIP_DIRS = {".git", ".build", "build", "DerivedData", "ci-artifacts", "node_modules"}
# Values in project.yml would override Config/Signing.xcconfig and put personal signing data in the source.
FORBIDDEN_IN_PROJECT_YML = re.compile(
    r"^\s*(DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE\w*|CODE_SIGN_STYLE)\s*:", re.M
)


def icon_problem(path: pathlib.Path):
    """Why iOS would refuse this app icon, or None. It must be a 1024 x 1024 PNG in plain RGB, with no transparency."""
    try:
        data = path.read_bytes()
    except OSError:
        return "could not be read."
    if not data.startswith(PNG_SIGNATURE):
        return "is not a PNG file."
    width = height = color = None
    kinds = set()
    position = len(PNG_SIGNATURE)
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        kinds.add(kind)
        if kind == b"IHDR" and length >= 13:
            width, height, _depth, color = struct.unpack(">IIBB", data[position + 8:position + 18])
        position += 12 + length
    if width is None:
        return "is not a readable PNG (no header)."
    if (width, height) != (1024, 1024):
        return f"is {width} x {height} pixels; an app icon must be 1024 x 1024."
    if color in (4, 6) or b"tRNS" in kinds:
        return "has transparency, and iOS refuses app icons with transparency. Save it as RGB with no alpha channel."
    if color != 2:
        return f"must be a full-colour RGB PNG (colour type 2); this one is colour type {color}."
    return None


def walk(root: pathlib.Path):
    for path in root.rglob("*"):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if path.is_file():
            yield path


def main(root: pathlib.Path = ROOT) -> int:
    problems = []

    missing = [name for name in REQUIRED if not (root / name).exists()]
    if missing:
        nested = sorted(p.parent.name for p in root.glob("*/project.yml"))
        if "project.yml" in missing and nested:
            problems.append(
                f"project.yml is inside the folder '{nested[0]}' instead of at the top of the repository. "
                f"Upload the CONTENTS of '{nested[0]}' (open it, select everything inside, drag that), "
                "not the folder itself."
            )
        else:
            problems.append("Missing from the repository: " + ", ".join(missing))

    icon = root / ICON
    if icon.exists():
        problem = icon_problem(icon)
        if problem:
            problems.append(f"{ICON} {problem}")

    for path in walk(root):
        rel = path.relative_to(root).as_posix()
        if path.suffix.lower() in SECRET_SUFFIXES or path.name == ".env" or path.name.startswith(".env."):
            problems.append(
                f"{rel} looks like signing material or a secret. Delete it from the repository, and if it was "
                "ever pushed, revoke or rotate it in your Apple account. Secrets belong in GitHub "
                "Settings > Secrets, never in files."
            )
            continue
        if path.suffix.lower() in {".swift", ".yml", ".yaml", ".md", ".txt", ".plist", ".xcconfig", ".json", ".py", ".sh"}:
            try:
                if PRIVATE_KEY.search(path.read_text(errors="ignore")):
                    problems.append(f"{rel} contains a private key. Remove it and rotate the key.")
            except OSError:
                pass

    project = root / "project.yml"
    if project.exists() and FORBIDDEN_IN_PROJECT_YML.search(project.read_text()):
        problems.append(
            "project.yml sets a signing value (DEVELOPMENT_TEAM, CODE_SIGN_*, PROVISIONING_PROFILE). "
            "Put it in Config/Signing.local.xcconfig instead; it would override Config/Signing.xcconfig."
        )

    if problems:
        for problem in problems:
            ghactions.error(problem, title="Repository layout")
        return 1
    print(f"Repository layout OK ({len(REQUIRED)} required paths present, no signing material found).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
