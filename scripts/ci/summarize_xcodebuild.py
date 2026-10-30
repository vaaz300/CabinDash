#!/usr/bin/env python3
"""Turns a raw xcodebuild / swift test log into something readable.

  * prints GitHub error annotations, and warning annotations for our own files (they appear at the top of the run page and on the changed file),
  * appends a short report to the job summary,
  * writes <out>/<name>-errors.txt: a plain block to paste straight into Claude.

This script only REPORTS. It always exits 0; the build or test step itself is what fails the job.
It never counts or reports anything as passed.
"""
import argparse
import pathlib
import re
import sys

import ghactions

DIAGNOSTIC = re.compile(r"^(?P<file>/[^\n]*?|<unknown>):(?P<line>\d+)(?::(?P<col>\d+))?: (?P<kind>error|warning|note): (?P<msg>.+)$")
BARE_ERROR = re.compile(r"^(?:xcodebuild: )?(?:fatal )?error: (?P<msg>.+)$")
LINKER = re.compile(r"^(?:ld|clang): (?:error: )?(?P<msg>.+)$")
TESTING_ISSUE = re.compile(r"Test (?P<name>.+?) recorded an issue at (?P<file>[^:\n]+):(?P<line>\d+):(?P<col>\d+): (?P<msg>.+)$")
FAILED_TEST_CASE = re.compile(r"^Test Case '(?P<name>.+)' failed")
# A crash in a test process ("Swift/Array.swift:600: Fatal error: Index out of range"), and Swift Testing's per-test
# lines, used to name the tests that were still running when it stopped. A crash ends the run before any result is
# printed, so without these the only sign is "no tests were executed".
FATAL = re.compile(r"(?:^|\s)(?:(?P<file>[^\s:]+\.swift):(?P<line>\d+): )?Fatal error: (?P<msg>.*)$")
TEST_STARTED = re.compile(r"Test (?P<name>[^\s]+\(\)) started\.")
TEST_FINISHED = re.compile(r"Test (?P<name>[^\s]+\(\)) (?:passed|failed|skipped)")
MARKERS = ("** BUILD SUCCEEDED **", "** BUILD FAILED **", "** TEST SUCCEEDED **", "** TEST FAILED **")
MAX_ANNOTATIONS = 10   # GitHub shows at most 10 error annotations per step
MAX_WARNING_ANNOTATIONS = 10
MAX_LISTED = 30


def parse(text: str):
    errors, warnings, markers = [], [], []
    seen_errors, seen_warnings = set(), set()
    last_error = None
    running: list = []
    crashed = False
    for raw in text.splitlines():
        line = raw.strip()
        started = TEST_STARTED.search(line)
        if started:
            running.append(started["name"])
            continue
        finished = TEST_FINISHED.search(line)
        if finished and finished["name"] in running:
            running.remove(finished["name"])
        fatal = FATAL.search(line)
        if fatal:
            crashed = True
            place = f" ({fatal['file']}:{fatal['line']})" if fatal["file"] else ""
            msg = f"Crash: Fatal error: {fatal['msg'].strip()}{place}"
            if (None, None, msg) not in seen_errors:
                seen_errors.add((None, None, msg))
                errors.append({"file": None, "line": None, "col": None, "msg": msg, "notes": []})
            continue
        if line in MARKERS:
            markers.append(line)
            continue

        match = DIAGNOSTIC.match(line)
        if match:
            kind = match["kind"]
            item = {
                "file": ghactions.relative(match["file"]) if match["file"] != "<unknown>" else None,
                "line": int(match["line"]) or None,
                "col": int(match["col"]) if match["col"] else None,
                "msg": match["msg"].strip(),
                "notes": [],
            }
            key = (item["file"], item["line"], item["msg"])
            if kind == "error":
                last_error = None
                if key not in seen_errors:
                    seen_errors.add(key)
                    errors.append(item)
                    last_error = item
            elif kind == "warning":
                last_error = None
                if key not in seen_warnings:
                    seen_warnings.add(key)
                    warnings.append(item)
            elif last_error is not None and len(last_error["notes"]) < 3:
                last_error["notes"].append(item["msg"])
            continue

        issue = TESTING_ISSUE.search(line)
        if issue:
            item = {"file": ghactions.relative(issue["file"]), "line": int(issue["line"]), "col": int(issue["col"]),
                    "msg": f"Test {issue['name']}: {issue['msg'].strip()}", "notes": []}
            key = (item["file"], item["line"], item["msg"])
            if key not in seen_errors:
                seen_errors.add(key)
                errors.append(item)
            last_error = None
            continue

        bare = BARE_ERROR.match(line) or LINKER.match(line)
        if bare:
            item = {"file": None, "line": None, "col": None, "msg": bare["msg"].strip(), "notes": []}
            key = (None, None, item["msg"])
            if key not in seen_errors:
                seen_errors.add(key)
                errors.append(item)
            last_error = None
            continue

        failed = FAILED_TEST_CASE.match(line)
        if failed:
            item = {"file": None, "line": None, "col": None, "msg": f"Test case failed: {failed['name']}", "notes": []}
            key = (None, None, item["msg"])
            if key not in seen_errors:
                seen_errors.add(key)
                errors.append(item)
            last_error = None
    if crashed and running:
        names = ", ".join(dict.fromkeys(running))
        errors.insert(0, {"file": None, "line": None, "col": None,
                          "msg": f"Tests still running when it stopped: {names}", "notes": []})
    return errors, warnings, markers


def where(item) -> str:
    if not item["file"]:
        return ""
    return f"{item['file']}:{item['line']}" if item["line"] else item["file"]


def render_text(title, errors, warnings, markers) -> str:
    lines = [f"{title}: {len(errors)} error(s), {len(warnings)} warning(s)."]
    if markers:
        lines.append("Result line in the log: " + markers[-1])
    for item in errors[:MAX_LISTED]:
        prefix = f"{where(item)}: " if where(item) else ""
        lines.append(f"error: {prefix}{item['msg']}")
        for note in item["notes"]:
            lines.append(f"    note: {note}")
    if len(errors) > MAX_LISTED:
        lines.append(f"... and {len(errors) - MAX_LISTED} more (see the full log artifact).")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--title", required=True, help="heading used in the summary, e.g. 'Build'")
    parser.add_argument("--out", default="ci-artifacts", help="folder for the plain-text report")
    args = parser.parse_args(argv)

    path = pathlib.Path(args.log)
    if not path.exists():
        ghactions.summary(f"### {args.title}\n\nNo log was produced (an earlier step failed before this one ran).")
        return 0
    errors, warnings, markers = parse(path.read_text(errors="replace"))

    for item in errors[:MAX_ANNOTATIONS]:
        ghactions.error(item["msg"] + ("".join(f"\n{n}" for n in item["notes"])), file=item["file"],
                        line=item["line"], col=item["col"], title=args.title)

    # Warnings in our own files too. The job summary lists every warning, but only a signed-in user can open it,
    # and annotations can be read from GitHub's public API. Warnings from the SDK or packages (absolute paths) are left out.
    ours = [w for w in warnings if w["file"] and not w["file"].startswith("/")]
    for item in ours[:MAX_WARNING_ANNOTATIONS]:
        ghactions.warning(item["msg"], file=item["file"], line=item["line"], col=item["col"], title=args.title)

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", args.title.lower()).strip("-")
    text = render_text(args.title, errors, warnings, markers)
    (out / f"{slug}-errors.txt").write_text(text + "\n")

    md = [f"### {args.title}", ""]
    md.append(f"**{len(errors)} error(s), {len(warnings)} warning(s)**" + (f" · `{markers[-1]}`" if markers else ""))
    if errors:
        md += ["", "```text"] + text.splitlines()[1:] + ["```", "", "Copy the block above into Claude to get a fix."]
    if warnings:
        md += ["", f"<details><summary>{len(warnings)} warning(s)</summary>", "", "```text"]
        md += [f"{where(w) + ': ' if where(w) else ''}{w['msg']}" for w in warnings[:60]]
        md += ["```", "</details>"]
    ghactions.summary("\n".join(md))
    return 0


if __name__ == "__main__":
    sys.exit(main())
