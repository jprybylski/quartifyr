#!/usr/bin/env python3
"""Keep every physical copy of the extension in sync with the canonical
inst/extensions/quartifyr/ (the R package's bundled copy, installed via
install_quartifyr_extension() -- see R/install-extension.R): both
bundled examples' _extensions/quartifyr/, and the repo-root
_extensions/quartifyr/ that makes `quarto add jprybylski/quartifyr`
work (see scripts/quarto_add_smoke_test.py and CLAUDE.md's "Quarto
extension host" note -- issue #16).

Also keeps both examples' _extensions/A2-ai/quarto-plus/ in sync with the
bundled inst/extensions/quarto-plus/ (installed offline via
install_quarto_extensions(); see inst/extensions/README.md for its
provenance and MIT licence).

Quarto's extension loader doesn't follow symlinks (confirmed: `quarto
render` fails outright with a symlinked _extensions/quartifyr/), so each
of these has to carry a real, physical copy rather than a link that
would guarantee sync by construction. This script is the alternative:
run with --check (used by each example's smoke_test.py, and safe to wire
into CI) to fail loudly on drift, or with no args to re-copy and fix it.

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
SOURCE = REPO_ROOT / "inst" / "extensions" / "quartifyr"
DESTS = [
    REPO_ROOT / "examples" / "demo-report" / "_extensions" / "quartifyr",
    REPO_ROOT / "examples" / "memo-example" / "_extensions" / "quartifyr",
    # Not shipped in the R package (see .Rbuildignore's `^_extensions$`)
    # -- exists solely so `quarto add jprybylski/quartifyr` finds a valid
    # extension at the repo root, the way GitHub-hosted extensions work.
    REPO_ROOT / "_extensions" / "quartifyr",
]
QUARTO_PLUS_SOURCE = REPO_ROOT / "inst" / "extensions" / "quarto-plus"
QUARTO_PLUS_DESTS = [
    REPO_ROOT / "examples" / "demo-report" / "_extensions" / "A2-ai" / "quarto-plus",
    REPO_ROOT / "examples" / "memo-example" / "_extensions" / "A2-ai" / "quarto-plus",
]
# (source, destinations) pairs, checked and synced independently.
SYNC_GROUPS = [(SOURCE, DESTS), (QUARTO_PLUS_SOURCE, QUARTO_PLUS_DESTS)]


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

    all_problems: dict[Path, tuple[Path, list[str]]] = {}
    for source, dests in SYNC_GROUPS:
        for dest in dests:
            problems = _diff_files(source, dest)
            if problems:
                all_problems[dest] = (source, problems)
            elif not check_only:
                print(f"{dest} is in sync with {source}")

    if not all_problems:
        if check_only:
            print(
                "All extension copies (quartifyr, quarto-plus) are in sync with "
                "their inst/extensions/ sources"
            )
        return 0

    if check_only:
        for dest, (source, problems) in all_problems.items():
            print(f"error: {dest} has drifted from {source}:", file=sys.stderr)
            for p in problems:
                print(f"  - {p}", file=sys.stderr)
        print(
            "\nRun `python3 scripts/sync_demo_extension.py` (no --check) to fix.",
            file=sys.stderr,
        )
        return 1

    for dest, (source, _) in all_problems.items():
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(source, dest)
        print(f"Synced {source} -> {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
