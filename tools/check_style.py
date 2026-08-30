#!/usr/bin/env python3
"""Style gate: no em dashes or en dashes anywhere in tracked text files.

Repo style rule: use commas, colons, or parentheses instead. Runs in CI.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BANNED = {"—": "em dash", "–": "en dash"}
BINARY_SUFFIXES = {".pcap", ".pcapng", ".png", ".jpg", ".gif"}


def tracked_files() -> list[pathlib.Path]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True,
                         text=True, check=True).stdout
    return [ROOT / line for line in out.splitlines() if line]


def main() -> int:
    problems = []
    for path in tracked_files():
        if path.suffix.lower() in BINARY_SUFFIXES or not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for char, label in BANNED.items():
                if char in line:
                    problems.append(f"{path.relative_to(ROOT)}:{lineno}: {label}")
    if problems:
        print("banned characters found:")
        print("\n".join(problems))
        return 1
    print("style check passed: no em or en dashes in tracked files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
