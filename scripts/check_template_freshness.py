#!/usr/bin/env python3
"""Keep the committed templates/org-reference.docx in sync with
styling/styles/default.yaml.

templates/org-reference.docx is checked into the repo (not just a build
artifact) so the two bundled examples -- and anyone trying quartifyr for
the first time -- have a working docx reference-template without needing
the styling/ Python venv set up first; see examples/demo-report/README.md
and the repo-root README's "Style YAML and reference-doc" section.

That convenience creates the same drift risk scripts/sync_demo_extension.py
already guards against for the Lua extension: nothing stops
styling/styles/default.yaml or build_template.py from changing without
the committed docx being regenerated to match. This script is that guard,
run with --check (used by each example's smoke_test.py, safe to wire into
CI) to fail loudly on drift, or with no args to rebuild and fix it.

`quartifyr-styling build`'s docx output isn't byte-reproducible across
runs (zipfile embeds a per-run timestamp in each entry's local header),
confirmed by running it twice back to back and diffing -- but every
entry's *content* is deterministic. So comparison unzips both docx files
and compares each member's bytes, not the raw files.

Usage:
    python3 scripts/check_template_freshness.py          # rebuild (fixes drift)
    python3 scripts/check_template_freshness.py --check   # exit 1 if out of sync, no changes
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
STYLE_YAML = REPO_ROOT / "styling" / "styles" / "default.yaml"
COMMITTED_DOCX = REPO_ROOT / "templates" / "org-reference.docx"
QUARTIFYR_STYLING_BIN = REPO_ROOT / ".venv" / "bin" / "quartifyr-styling"


def _docx_contents(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as z:
        return {name: z.read(name) for name in z.namelist()}


def _diff(built: Path, committed: Path) -> list[str]:
    if not committed.exists():
        return [f"missing entirely: {committed}"]
    built_contents = _docx_contents(built)
    committed_contents = _docx_contents(committed)
    problems = []
    only_built = built_contents.keys() - committed_contents.keys()
    only_committed = committed_contents.keys() - built_contents.keys()
    if only_built:
        problems.append(f"only in a fresh build: {sorted(only_built)}")
    if only_committed:
        problems.append(f"only in committed docx: {sorted(only_committed)}")
    changed = sorted(
        name
        for name in built_contents.keys() & committed_contents.keys()
        if built_contents[name] != committed_contents[name]
    )
    if changed:
        problems.append(f"content differs: {changed}")
    return problems


def main() -> int:
    check_only = "--check" in sys.argv

    if not QUARTIFYR_STYLING_BIN.exists():
        print(
            f"error: {QUARTIFYR_STYLING_BIN} not found -- set up the styling/ venv first: "
            'uv venv .venv --python 3.12 && uv pip install -e "./styling[dev]"',
            file=sys.stderr,
        )
        return 1

    with tempfile.TemporaryDirectory(prefix="quartifyr-template-freshness-") as tmp:
        built_docx = Path(tmp) / "org-reference.docx"
        result = subprocess.run(
            [
                str(QUARTIFYR_STYLING_BIN), "build",
                "--style", str(STYLE_YAML),
                "--out", str(built_docx),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print("error: quartifyr-styling build failed", file=sys.stderr)
            print(result.stdout, file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            return 1

        problems = _diff(built_docx, COMMITTED_DOCX)

        if not problems:
            if check_only:
                print(f"{COMMITTED_DOCX} is in sync with {STYLE_YAML}")
            return 0

        if check_only:
            print(f"error: {COMMITTED_DOCX} has drifted from {STYLE_YAML}:", file=sys.stderr)
            for p in problems:
                print(f"  - {p}", file=sys.stderr)
            print(
                "\nRun `python3 scripts/check_template_freshness.py` (no --check) to fix.",
                file=sys.stderr,
            )
            return 1

        COMMITTED_DOCX.parent.mkdir(parents=True, exist_ok=True)
        built_docx.replace(COMMITTED_DOCX)
        print(f"Rebuilt {COMMITTED_DOCX} from {STYLE_YAML}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
