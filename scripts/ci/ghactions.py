"""Small helpers shared by the CI scripts: GitHub annotations, the job summary and GITHUB_ENV.

Outside GitHub Actions everything falls back to plain printing, so the scripts can be run by hand.
"""
import os
import sys


def _escape_data(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _escape_property(text: str) -> str:
    return _escape_data(text).replace(":", "%3A").replace(",", "%2C")


def annotate(level: str, message: str, *, file=None, line=None, col=None, title=None) -> None:
    """level is 'error', 'warning' or 'notice'."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        where = ""
        if file and line:
            where = f"{file}:{line}" + (f":{col}" if col else "") + ": "
        elif file:
            where = f"{file}: "
        print(f"{level.upper()}: {where}{message}")
        return
    props = []
    if file:
        props.append(f"file={_escape_property(str(file))}")
    if line:
        props.append(f"line={line}")
    if col:
        props.append(f"col={col}")
    if title:
        props.append(f"title={_escape_property(title)}")
    head = f"::{level}" + (" " + ",".join(props) if props else "")
    print(f"{head}::{_escape_data(message)}")


def error(message: str, **kwargs) -> None:
    annotate("error", message, **kwargs)


def warning(message: str, **kwargs) -> None:
    annotate("warning", message, **kwargs)


def notice(message: str, **kwargs) -> None:
    annotate("notice", message, **kwargs)


def summary(markdown: str) -> None:
    """Append to the run's summary page (or print when run by hand)."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(markdown.rstrip() + "\n\n")
    else:
        print(markdown)


def set_env(name: str, value: str) -> None:
    """Make NAME=value available to the later steps of the job."""
    path = os.environ.get("GITHUB_ENV")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


def workspace_root() -> str:
    return os.environ.get("GITHUB_WORKSPACE") or os.getcwd()


def relative(path: str) -> str:
    """Repo-relative form of an absolute path from a build log, so annotations land on the right file."""
    root = workspace_root().rstrip("/") + "/"
    return path[len(root):] if path.startswith(root) else path


if __name__ == "__main__":
    print("ghactions.py is a helper module; run one of the other scripts in this folder.", file=sys.stderr)
    sys.exit(2)
