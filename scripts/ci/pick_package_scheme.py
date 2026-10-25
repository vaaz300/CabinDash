#!/usr/bin/env python3
"""Reads the output of `xcodebuild -list -json` (run inside CabinCore/) and prints the scheme to test.

Swift Package Manager creates the schemes. When a package has several products it also creates
'<Name>-Package', which covers every target, tests included; with a single library only '<Name>' exists.
Xcode sometimes prints a few lines before the JSON, so the JSON object is located first.
"""
import json
import sys

NAME = "CabinCore"


def choose(schemes):
    for wanted in (f"{NAME}-Package", NAME):
        if wanted in schemes:
            return wanted
    return schemes[0] if schemes else ""


def schemes_from(text: str):
    start = text.find("{")
    if start < 0:
        return []
    data, _ = json.JSONDecoder().raw_decode(text[start:])
    container = data.get("workspace") or data.get("project") or {}
    return list(container.get("schemes", []))


if __name__ == "__main__":
    chosen = choose(schemes_from(sys.stdin.read()))
    if not chosen:
        print("No schemes were listed for the CabinCore package.", file=sys.stderr)
        sys.exit(1)
    print(chosen)
