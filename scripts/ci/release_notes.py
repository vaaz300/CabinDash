#!/usr/bin/env python3
"""Writes the notes of the GitHub release that the "Unsigned IPA (manual)" workflow publishes for each IPA.

What changed is the "Next ..." section at the top of CHANGELOG.md: the changes made since the last IPA. After a run,
that section is renamed after the beta it became (for example "Beta 2.2 (run 22, ...)") and a new, empty "Next" section
starts above it.

    python3 scripts/ci/release_notes.py CHANGELOG.md LABEL BUILD COMMIT

LABEL is "Beta 2.2" or a release's number, BUILD the run number, COMMIT the commit it was built from. Standard library only.
"""
import pathlib
import sys


def next_section(changelog: str) -> str:
    """The text under the first heading that starts with "## Next", up to the next "## " heading. Empty when there is none."""
    lines = changelog.splitlines()
    for start, line in enumerate(lines):
        if line.startswith("## Next"):
            body = []
            for following in lines[start + 1:]:
                if following.startswith("## "):
                    break
                body.append(following)
            return "\n".join(body).strip()
    return ""


def notes(changelog: str, label: str, build: str, commit: str) -> str:
    changes = next_section(changelog) or "See CHANGELOG.md."
    return "\n".join([
        f"Cabin Dash {label} (build {build}), built from commit {commit[:7]}.",
        "",
        "## What changed",
        "",
        changes,
        "",
        "## Installing",
        "",
        "The .ipa below is unsigned. Sign and install it with iLoader (or Sideloadly or AltStore) and your Apple ID:",
        "docs/DEVICE-INSTALL.md, route B. Every beta and what changed in it: CHANGELOG.md.",
        "",
    ])


def main(argv) -> int:
    if len(argv) != 5:
        print("Usage: python3 scripts/ci/release_notes.py CHANGELOG.md LABEL BUILD COMMIT", file=sys.stderr)
        return 1
    try:
        changelog = pathlib.Path(argv[1]).read_text()
    except OSError as error:
        print(f"Could not read {argv[1]}: {error.strerror or error}.", file=sys.stderr)
        return 1
    sys.stdout.write(notes(changelog, argv[2], argv[3], argv[4]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
