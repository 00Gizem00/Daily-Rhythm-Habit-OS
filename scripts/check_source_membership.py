#!/usr/bin/env python3
"""Reject an Xcode build graph that predates added, removed or renamed Swift files."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_DIRECTORIES = {
    "app": ("DailyRhythm/App", "DailyRhythm/Shared"),
    "widget": ("DailyRhythmWidgets", "DailyRhythm/Shared"),
    "schema-tests": ("DailyRhythmSchemaTests",),
}


def source_paths(root: Path, target: str) -> list[Path]:
    return sorted(path for folder in SOURCE_DIRECTORIES[target]
                  for path in (root / folder).rglob("*.swift") if path.is_file())


def source_fingerprint(root: Path, paths: list[Path]) -> str:
    names = sorted(path.relative_to(root).as_posix() for path in paths)
    return hashlib.sha256("\n".join(names).encode()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--target", choices=SOURCE_DIRECTORIES, required=True)
    parser.add_argument("--expected", required=True)
    args = parser.parse_args()
    actual = source_fingerprint(args.root, source_paths(args.root, args.target))
    if actual != args.expected:
        print("error: Daily Rhythm's loaded Xcode source list is stale "
              f"({args.target}). Run python3 scripts/generate_project.py, then "
              "File > Close Project and reopen DailyRhythm.xcodeproj. "
              "Keep the current run destination. Cleaning build products alone "
              "does not reload the project.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
