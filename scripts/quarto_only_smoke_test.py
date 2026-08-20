#!/usr/bin/env python3
"""Proves the repo-root README's "Using the pieces directly" step 1 --
plain `quarto render --reference-doc templates/org-reference.docx`, no R,
no reportifyr, no styling/ Python venv -- actually works for both bundled
examples, using nothing but `quarto` itself and the committed reference-
doc (see scripts/check_template_freshness.py).

This is deliberately NOT the same thing smoke_test.py checks: it only
renders the shell (pass 1), so `{rpfy}:` magic strings and any `\\gls{}`
abbreviation references stay unresolved in the output -- expected, not a
bug, since pass 2 (reportifyr) and the abbreviations bridge
(`quartifyr-styling abbrevs`) never ran. The point is narrower: someone
who just wants to see quartifyr's styling/title-page/signature-page/
synopsis output, without installing R or Python, can do exactly this.

Each example is rendered from a temp copy containing only what `quarto
render` itself needs (report.qmd, _extensions/, assets/, references.bib)
-- deliberately no _quarto.yml, matching scripts/
bare_bones_integration_test.py's "no project scaffolding" precedent --
so nothing lands back in the tracked example directory.

Deliberately stdlib-only (zipfile + re to pull text out of the rendered
docx, no python-docx) so this needs nothing beyond `quarto` itself and a
plain `python3` -- not even the styling/ venv -- letting it run as the
very first check in CI, before any R/uv setup, as real proof the
Quarto-only path has no Python or R dependency of its own.

Run from anywhere:

    python3 scripts/quarto_only_smoke_test.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = REPO_ROOT / "inst" / "templates" / "org-reference.docx"

EXAMPLES = [
    {
        "name": "demo-report",
        "dir": REPO_ROOT / "examples" / "demo-report",
        # scripts/01_analysis.R is needed even in this no-R/no-reportifyr
        # path: report.qmd's Analysis Code appendix embeds it via Quarto's
        # own native `{{< include >}}` shortcode, resolved by `quarto
        # render` itself, not by executing any R.
        "extra_files": ["references.bib", "scripts/01_analysis.R"],
        "expect_present": ["Population Pharmacokinetics of Theophylline"],
        # report.qmd's main-body "Scoped Numbering Example" is the first
        # plain (non-appendix) section_fig_caption use in the document --
        # appendix.lua's note_plain_scope_independence() should fire
        # exactly once, on stderr (confirmed: quarto.log.warning() prints
        # there, not stdout).
        "expect_stderr_contains": ["section_fig_caption/section_tbl_caption/subsection_fig_caption"],
    },
    {
        "name": "memo-example",
        "dir": REPO_ROOT / "examples" / "memo-example",
        "extra_files": [],
        "expect_present": ["MEMORANDUM"],
    },
]


def _docx_text(docx_path: Path) -> str:
    with zipfile.ZipFile(docx_path) as z:
        document_xml = z.read("word/document.xml").decode("utf-8")
    # Join all w:t run text with spaces -- coarser than python-docx's
    # per-paragraph text, but plenty precise for a substring containment
    # check, and needs nothing beyond the stdlib.
    return " ".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", document_xml))


def _render_one(example: dict) -> list[tuple[str, bool]]:
    checks: list[tuple[str, bool]] = []
    project_dir = example["dir"]
    name = example["name"]

    with tempfile.TemporaryDirectory(prefix=f"quartifyr-quarto-only-{name}-") as tmp:
        work_dir = Path(tmp)
        shutil.copytree(project_dir / "_extensions", work_dir / "_extensions")
        shutil.copy(project_dir / "report.qmd", work_dir / "report.qmd")
        if (project_dir / "assets").exists():
            shutil.copytree(project_dir / "assets", work_dir / "assets")
        for extra in example["extra_files"]:
            (work_dir / extra).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(project_dir / extra, work_dir / extra)

        output_docx = work_dir / "shell.docx"
        result = subprocess.run(
            [
                "quarto", "render", "report.qmd",
                "--to", "docx",
                "--reference-doc", str(TEMPLATE),
                "--output", output_docx.name,
                "-M", "document-status:DRAFT",
            ],
            cwd=work_dir,
            capture_output=True,
            text=True,
        )
        checks.append((f"[{name}] quarto render exits 0 (no R, no Python, just quarto)", result.returncode == 0))
        if result.returncode != 0:
            print(result.stdout, file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            return checks
        checks.append((f"[{name}] output docx produced", output_docx.exists()))
        if not output_docx.exists():
            return checks

        joined = _docx_text(output_docx)
        for expected in example["expect_present"]:
            checks.append((f"[{name}] shell contains {expected!r}", expected in joined))
        # Pass 2 never ran -- {rpfy}: placeholders are expected to still be
        # literal, not a failure of this step.
        checks.append((f"[{name}] {{rpfy}}: placeholders still literal (pass 2 not run, as expected)", "{rpfy}:" in joined))
        for expected in example.get("expect_stderr_contains", []):
            checks.append((f"[{name}] quarto's stderr contains {expected!r}", expected in result.stderr))

    return checks


def main() -> int:
    if shutil.which("quarto") is None:
        print("SKIP: quarto not found on PATH", file=sys.stderr)
        return 0
    if not TEMPLATE.exists():
        print(f"FAIL: {TEMPLATE} not found -- it should be committed to the repo", file=sys.stderr)
        return 1

    all_checks: list[tuple[str, bool]] = []
    for example in EXAMPLES:
        print(f"Rendering {example['name']} with plain `quarto render` (no R, no reportifyr)...")
        all_checks.extend(_render_one(example))

    failed = [n for n, ok in all_checks if not ok]
    for n, ok in all_checks:
        print(f"{'PASS' if ok else 'FAIL'}: {n}")

    if failed:
        print(f"\n{len(failed)}/{len(all_checks)} checks failed", file=sys.stderr)
        return 1

    print(f"\nAll {len(all_checks)} checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
