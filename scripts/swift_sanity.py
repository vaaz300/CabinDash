#!/usr/bin/env python3
"""A crude Swift check for machines without a Swift compiler: balanced (), [], {} outside strings and comments.

It cannot find type errors. It only catches missing or extra brackets. The real check is building in Xcode.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAIRS = {")": "(", "]": "[", "}": "{"}


def check(path):
    src = path.read_text()
    stack = []
    i, line, n = 0, 1, len(src)
    errors = []
    while i < n:
        ch = src[i]
        two = src[i:i + 2]
        if ch == "\n":
            line += 1
        if two == "//":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if two == "/*":
            depth = 1
            i += 2
            while i < n and depth:
                if src[i:i + 2] == "/*":
                    depth += 1
                    i += 2
                elif src[i:i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    line += src[i] == "\n"
                    i += 1
            continue
        if ch == '"' or (ch == "#" and src[i:].lstrip("#").startswith('"')):
            hashes = 0
            while src[i] == "#":
                hashes += 1
                i += 1
            multiline = src[i:i + 3] == '"""'
            i += 3 if multiline else 1
            closer = ('"""' if multiline else '"') + "#" * hashes
            escape = "\\" + "#" * hashes
            interp = []  # brace depth of "\(" interpolations, handled by recursion-free scan below
            while i < n:
                if src.startswith(escape + "(", i):
                    # skip the interpolation, tracking nested parentheses (strings inside are rare enough here)
                    depth = 1
                    i += len(escape) + 1
                    while i < n and depth:
                        if src[i] == "(":
                            depth += 1
                        elif src[i] == ")":
                            depth -= 1
                        elif src[i] == '"':
                            i += 1
                            while i < n and src[i] != '"':
                                i += 2 if src[i] == "\\" else 1
                        i += 1
                    continue
                if src.startswith(escape, i):
                    i += len(escape) + 1
                    continue
                if src.startswith(closer, i):
                    i += len(closer)
                    break
                line += src[i] == "\n"
                i += 1
            continue
        if ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack or stack[-1][0] != PAIRS[ch]:
                errors.append(f"{path.relative_to(ROOT)}:{line}: unexpected '{ch}'")
                return errors
            stack.pop()
        i += 1
    for ch, ln in stack:
        errors.append(f"{path.relative_to(ROOT)}:{ln}: '{ch}' is never closed")
    return errors


def main():
    files = sorted(p for p in ROOT.rglob("*.swift") if ".build" not in p.parts)
    bad = []
    for f in files:
        bad += check(f)
    print(f"Checked {len(files)} Swift files")
    for b in bad:
        print(" -", b)
    print("OK: brackets balance in every file." if not bad else f"{len(bad)} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
