#!/usr/bin/env python3
"""Works out the version written into an IPA built by the "Unsigned IPA (manual)" workflow.

Every IPA build is a beta, numbered from the workflow's run number: run 1 is beta 0.1, run 21 is beta 2.1, run 30 is
beta 3.0. The build number is the run number itself. A full release is made by typing its version (for example 1.0)
into the workflow's "release_version" box; it keeps the run number as its build number.

    python3 scripts/ci/app_version.py RUN_NUMBER [RELEASE_VERSION]

prints key=value lines for $GITHUB_OUTPUT: version, build, channel (Beta or Release), label (as people read it), slug
(for file names), tag (the GitHub release's tag: beta-2.1, or v1.0 for a full release) and prerelease (true for a beta).
Standard library only. See CHANGELOG.md and README.md ("Versions").
"""
import re
import sys

RELEASE = re.compile(r"^\d+(\.\d+)*$")


def work_out(run_number: int, release: str = "") -> dict:
    """The version for IPA build `run_number`; a full release when `release` is given. Raises ValueError when invalid."""
    if run_number < 1:
        raise ValueError(f"The run number must be 1 or more, not {run_number}.")
    build = str(run_number)
    release = release.strip()
    if release:
        if not RELEASE.match(release):
            raise ValueError(f"A release version is numbers separated by dots, such as 1.0; \"{release}\" is not.")
        return {
            "version": release, "build": build, "channel": "Release", "label": release, "slug": release,
            "tag": f"v{release}", "prerelease": "false",
        }
    version = f"{run_number // 10}.{run_number % 10}"
    return {
        "version": version, "build": build, "channel": "Beta", "label": f"Beta {version}", "slug": f"beta-{version}",
        "tag": f"beta-{version}", "prerelease": "true",
    }


def main(argv) -> int:
    if len(argv) not in (2, 3):
        print("Usage: python3 scripts/ci/app_version.py RUN_NUMBER [RELEASE_VERSION]", file=sys.stderr)
        return 1
    try:
        info = work_out(int(argv[1]), argv[2] if len(argv) == 3 else "")
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    for key in ("version", "build", "channel", "label", "slug", "tag", "prerelease"):
        print(f"{key}={info[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
