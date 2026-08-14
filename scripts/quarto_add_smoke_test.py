#!/usr/bin/env python3
"""Proves `quarto add jprybylski/quartifyr` (README's standalone,
no-R-package-needed install path -- see the repo-root `_extensions/
quartifyr/` note in CLAUDE.md, issue #16) actually works, without
waiting for a push to GitHub to find out.

`quarto add <gh-org>/<gh-repo>` downloads a zip of the repo and scans it
for a valid extension (either a root `_extension.yml`, or `_extensions/
*/_extension.yml`). This script reproduces exactly that against a zip of
the current commit (`git archive HEAD`) instead of GitHub, the same
"test the PR's own tree, not whatever's already on the default branch"
reasoning CLAUDE.md gives for CI installing the R package via
`local::...` rather than from GitHub.

Deliberately stdlib + git only (no R, no Python venv), so this can run
right alongside scripts/quarto_only_smoke_test.py, before any R/uv setup.

Run from anywhere:

    python3 scripts/quarto_add_smoke_test.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    if shutil.which("quarto") is None:
        print("SKIP: quarto not found on PATH", file=sys.stderr)
        return 0
    if shutil.which("git") is None:
        print("SKIP: git not found on PATH", file=sys.stderr)
        return 0

    with tempfile.TemporaryDirectory(prefix="quartifyr-quarto-add-") as tmp:
        tmp_dir = Path(tmp)
        archive = tmp_dir / "quartifyr-head.zip"
        install_dir = tmp_dir / "install"
        install_dir.mkdir()

        archive_result = subprocess.run(
            ["git", "archive", "--format=zip", "-o", str(archive), "HEAD"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        if archive_result.returncode != 0:
            print("FAIL: git archive HEAD failed", file=sys.stderr)
            print(archive_result.stderr, file=sys.stderr)
            return 1

        add_result = subprocess.run(
            ["quarto", "add", str(archive), "--no-prompt"],
            cwd=install_dir,
            capture_output=True,
            text=True,
        )
        installed = install_dir / "_extensions" / "quartifyr" / "_extension.yml"

        checks = [
            ("`quarto add` (zip of HEAD) exits 0", add_result.returncode == 0),
            ("_extensions/quartifyr/_extension.yml installed", installed.exists()),
        ]

        for name, ok in checks:
            print(f"{'PASS' if ok else 'FAIL'}: {name}")

        if any(not ok for _, ok in checks):
            print(add_result.stdout, file=sys.stderr)
            print(add_result.stderr, file=sys.stderr)
            print(
                "\nLikely cause: the repo-root _extensions/quartifyr/ copy is "
                "missing or has drifted -- run "
                "`python3 scripts/sync_demo_extension.py` and commit the result.",
                file=sys.stderr,
            )
            return 1

    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
