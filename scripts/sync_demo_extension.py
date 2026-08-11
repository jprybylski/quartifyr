#!/usr/bin/env python3
"""Keep examples/demo-report/_extensions/quartifyr/ in sync with the
canonical _extensions/quartifyr/ at the repo root.

Quarto's extension loader doesn't follow symlinks (confirmed: `quarto
render` fails outright with a symlinked _extensions/quartifyr/), so the
demo project has to carry a real, physical copy rather than a link that
would guarantee sync by construction. This script is the alternative:
run with --check (used by smoke_test.py, and safe to wire into CI) to
fail loudly on drift, or with no args to re-copy and fix it.

Usage:
    python3 scripts/sync_demo_extension.py          # re-sync (fixes drift)
    python3 scripts/sync_demo_extension.py --check   # exit 1 if out of sync, no changes
"""

from __future__ import annotations

import filecmp
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "_extensions" / "quartifyr"
DEST = REPO_ROOT / "examples" / "demo-report" / "_extensions" / "quartifyr"


def _diff_files(source: Path, dest: Path) -> list[str]:
    if not dest.exists():
        return [f"missing entirely: {dest}"]
    comparison = filecmp.dircmp(source, dest)
    problems = []
    if comparison.left_only:
        problems.append(f"only in {source}: {sorted(comparison.left_only)}")
    if comparison.right_only:
        problems.append(f"only in {dest}: {sorted(comparison.right_only)}")
    if comparison.diff_files:
        problems.append(f"content differs: {sorted(comparison.diff_files)}")
    return problems


def main() -> int:
    check_only = "--check" in sys.argv

    problems = _diff_files(SOURCE, DEST)

    if not problems:
        print(f"{DEST} is in sync with {SOURCE}")
        return 0

    if check_only:
        print(f"error: {DEST} has drifted from {SOURCE}:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        print(
            "\nRun `python3 scripts/sync_demo_extension.py` (no --check) to fix.",
            file=sys.stderr,
        )
        return 1

    if DEST.exists():
        shutil.rmtree(DEST)
    shutil.copytree(SOURCE, DEST)
    print(f"Synced {SOURCE} -> {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
