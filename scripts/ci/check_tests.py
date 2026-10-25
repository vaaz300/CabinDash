#!/usr/bin/env python3
"""Decides whether the unit tests really ran and passed. A green exit code alone is not accepted.

Exit 0 only when ALL of these hold:
  * the log (or the .xcresult) reports no failed test,
  * at least one test was executed,
  * at least as many tests ran as are declared with @Test in the test sources.
That last rule stops a scheme that quietly contains no tests from looking like a pass.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

import ghactions

SWIFT_TESTING = re.compile(r"Test run with (\d+) tests?(?: in \d+ suites?)? (passed|failed)")
XCTEST = re.compile(r"Executed (\d+) tests?, with (\d+) failures?")


def declared_tests(tests_dir: pathlib.Path) -> int:
    total = 0
    for path in tests_dir.rglob("*.swift"):
        total += len(re.findall(r"^\s*@Test\b", path.read_text(errors="ignore"), re.M))
    return total


def from_log(text: str) -> dict:
    testing = SWIFT_TESTING.findall(text)
    xctest = XCTEST.findall(text)
    executed = max([int(n) for n, _ in testing] + [int(n) for n, _ in xctest] + [0])
    failed = any(result == "failed" for _, result in testing) or any(int(f) > 0 for _, f in xctest)
    return {"executed": executed, "failed": failed, "seen_summary": bool(testing or xctest)}


def from_xcresult(path: pathlib.Path):
    """Totals from the result bundle (Xcode 16 or newer). Returns None if it cannot be read."""
    if not path or not path.exists():
        return None
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(path), "--compact"],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode != 0:
            return None
        data = json.loads(result.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    total = data.get("totalTestCount")
    if total is None:
        return None
    return {"executed": int(total), "failed": int(data.get("failedTests", 0)) > 0 or data.get("result") == "Failed",
            "passed": int(data.get("passedTests", 0))}


def evaluate(declared: int, log_info: dict, xcresult_info) -> tuple:
    """Returns (ok, message)."""
    executed = max(log_info["executed"], (xcresult_info or {}).get("executed", 0))
    failed = log_info["failed"] or bool((xcresult_info or {}).get("failed"))
    if failed:
        return False, "At least one test failed. The errors above list which."
    if executed == 0:
        return False, ("No tests were executed. The scheme ran but found no tests, so nothing was proven. "
                       "Check that the package test target is part of the scheme.")
    if executed < declared:
        return False, f"Only {executed} of the {declared} tests declared in the sources ran."
    if not log_info["seen_summary"] and not xcresult_info:
        return False, "Could not find a test summary in the log or the result bundle."
    return True, f"{executed} test(s) ran and passed ({declared} declared in the sources)."


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tests-dir", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--xcresult")
    parser.add_argument("--label", required=True, help="e.g. 'iOS Simulator' or 'macOS host'")
    args = parser.parse_args(argv)

    log_path = pathlib.Path(args.log)
    if not log_path.exists():
        ghactions.error(f"No test log at {args.log}; the test step did not run.", title=args.label)
        return 1
    declared = declared_tests(pathlib.Path(args.tests_dir))
    log_info = from_log(log_path.read_text(errors="replace"))
    xc_info = from_xcresult(pathlib.Path(args.xcresult)) if args.xcresult else None
    ok, message = evaluate(declared, log_info, xc_info)

    executed = max(log_info["executed"], (xc_info or {}).get("executed", 0))
    ghactions.summary(
        f"### Unit tests: {args.label}\n\n"
        f"| Declared with @Test | Executed | Result |\n|---|---|---|\n"
        f"| {declared} | {executed} | {'passed' if ok else 'NOT PASSED'} |\n\n{message}"
    )
    if ok:
        print(f"[{args.label}] {message}")
        return 0
    ghactions.error(message, title=f"Unit tests: {args.label}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
