#!/usr/bin/env python3
"""Picks an iPhone simulator that exists on this runner, instead of hard-coding a device name.

Runner images change which simulators they ship, so a fixed 'iPhone 16' breaks without warning.
Prints SIM_UDID, SIM_NAME and SIM_RUNTIME, and (inside GitHub Actions) exports them to the later steps.

  select_simulator.py                  reads `xcrun simctl list devices available -j`
  select_simulator.py --json FILE      reads that JSON from a file (used by the tests)
"""
import json
import re
import subprocess
import sys

import ghactions

PREFERRED = ["iPhone 17", "iPhone 17 Pro", "iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro"]
RUNTIME = re.compile(r"SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$")


def pick(data: dict):
    """Returns (udid, name, 'iOS x.y') for the best available iPhone, or None."""
    best = None
    for runtime, devices in data.get("devices", {}).items():
        match = RUNTIME.search(runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        for device in devices:
            name = device.get("name", "")
            if not name.startswith("iPhone") or device.get("isAvailable") is False:
                continue
            rank = PREFERRED.index(name) if name in PREFERRED else len(PREFERRED)
            key = (version, -rank, name)
            if best is None or key > best[0]:
                best = (key, device["udid"], name, f"iOS {version[0]}.{version[1]}")
    return None if best is None else best[1:]


def main(argv) -> int:
    if len(argv) == 3 and argv[1] == "--json":
        raw = open(argv[2], encoding="utf-8").read()
    else:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True
        )
        if result.returncode != 0:
            ghactions.error(f"simctl failed: {result.stderr.strip()}", title="Simulator selection")
            return 1
        raw = result.stdout
    chosen = pick(json.loads(raw))
    if chosen is None:
        ghactions.error(
            "No available iPhone simulator was found on this runner. Check the 'Simulators' list of the "
            "runner image and the Xcode version in .github/actions/setup-ios-toolchain/action.yml.",
            title="Simulator selection",
        )
        return 1
    udid, name, runtime = chosen
    print(f"Selected simulator: {name} ({runtime}) {udid}")
    ghactions.set_env("SIM_UDID", udid)
    ghactions.set_env("SIM_NAME", name)
    ghactions.set_env("SIM_RUNTIME", runtime)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
