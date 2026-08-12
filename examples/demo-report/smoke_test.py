#!/usr/bin/env python3
"""End-to-end smoke test for the quartifyr demo report.

Runs the real two-pass pipeline (Rscript render.R --final, which drives
Quarto + reportifyr exactly as a report author would) and asserts on the
resulting docx: no leftover reportifyr magic strings, the expected tables/
images/abbreviations are present, and appendix numbering resolved.

Requires the full toolchain: R (with this repo's rv-managed packages),
Quarto, and the styling/ venv. Run from anywhere:

    python3 examples/demo-report/smoke_test.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import docx
from docx.enum.text import WD_TAB_ALIGNMENT
from docx.oxml.ns import qn

PROJECT_DIR = Path(__file__).resolve().parent
REPO_ROOT = PROJECT_DIR.parent.parent


def _iter_paragraph_text(document: docx.Document):
    for p in document.element.body.iter(qn("w:p")):
        texts = p.findall(".//" + qn("w:t"))
        text = "".join(t.text or "" for t in texts)
        if text.strip():
            yield text


def main() -> int:
    if shutil.which("Rscript") is None:
        print("SKIP: Rscript not found on PATH", file=sys.stderr)
        return 0
    if shutil.which("quarto") is None:
        print("SKIP: quarto not found on PATH", file=sys.stderr)
        return 0

    # Quarto's extension loader doesn't follow symlinks, so this demo
    # carries a physical copy of _extensions/quartifyr/ rather than a
    # symlink to the canonical one at the repo root -- which means it can
    # silently drift out of sync with real fixes (this happened for real:
    # a Heading1-vs-"Heading 1" style-ID bugfix landed in the canonical
    # copy but the demo kept rendering with the stale, buggy version until
    # caught). Fail fast, before wasting time on a render that would only
    # prove the *old* code works.
    sync_check = subprocess.run(
        ["python3", str(REPO_ROOT / "scripts" / "sync_demo_extension.py"), "--check"],
        capture_output=True,
        text=True,
    )
    if sync_check.returncode != 0:
        print("FAIL: demo's _extensions/quartifyr/ copy has drifted from the canonical one", file=sys.stderr)
        print(sync_check.stdout, file=sys.stderr)
        print(sync_check.stderr, file=sys.stderr)
        return 1

    print("Running Rscript render.R --final ...")
    result = subprocess.run(
        ["Rscript", "render.R", "--final"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        print("FAIL: render.R exited non-zero", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return 1

    final_docx = PROJECT_DIR / "report" / "final" / "report-final.docx"
    if not final_docx.exists():
        print(f"FAIL: expected output not found: {final_docx}", file=sys.stderr)
        return 1

    document = docx.Document(str(final_docx))
    all_text = list(_iter_paragraph_text(document))
    joined = " | ".join(all_text)

    checks: list[tuple[str, bool]] = []

    checks.append(("no leftover {rpfy}: magic strings", "{rpfy}:" not in joined))
    checks.append(("at least 6 tables present (signatures + synopsis + PK summary + abbreviations)", len(document.tables) >= 6))

    with zipfile.ZipFile(final_docx) as z:
        images = [n for n in z.namelist() if n.startswith("word/media/")]
    checks.append(("figure embedded as a real image", len(images) >= 1))

    checks.append(("title page title rendered", "Population Pharmacokinetics of Theophylline" in joined))
    checks.append(("document-status stamp rendered", "DRAFT" in joined or "FINAL" in joined))
    checks.append(("\\gls{PK} resolved to a real definition", "pharmacokinetic (pk)" in joined.lower()))

    def _table_row_texts(table) -> list[list[str]]:
        return [[cell.text for cell in row.cells] for row in table.rows]

    all_rows = [row for table in document.tables for row in _table_row_texts(table)]
    checks.append(
        ("abbreviations table has a PK row", any("PK" in row and "Pharmacokinetic" in row for row in all_rows))
    )
    checks.append(("appendix auto-lettered", "Appendix A: Statistical Methods" in joined))
    checks.append(
        ("PK summary table header present", any({"Cmax", "Cmin"}.issubset(set(row)) for row in all_rows))
    )
    checks.append(("synopsis section rendered", "Synopsis" in joined))
    checks.append(
        (
            "synopsis title row has the real report title",
            any(
                len(row) >= 2 and row[0] == "Title" and row[1] == "Population Pharmacokinetics of Theophylline"
                for row in all_rows
            ),
        )
    )

    checks.append(("logo image embedded on title page", any("png" in n.lower() for n in images)))
    checks.append(("address rendered on title page", any("Raleigh, NC" in row_cell for row in all_rows for row_cell in row)))

    checks.append(("document split into title/front-matter/body sections", len(document.sections) == 3))
    title_section, front_matter_section, body_section = document.sections

    header_expected = "ACME-001 - RPT-2026-014\tFINAL"
    checks.append(("dynamic 2-zone page header resolved from header-format:", title_section.header.paragraphs[0].text == header_expected))
    checks.append(
        (
            "header applies to all three sections",
            title_section.header.paragraphs[0].text
            == front_matter_section.header.paragraphs[0].text
            == body_section.header.paragraphs[0].text,
        )
    )
    # Tab stop must actually be flush right, not landing on the Header
    # style's own inherited center tab -- see layout.py's
    # _clear_inherited_tab_stops() docstring for the real-Word-verified bug
    # this guards against.
    header_tabs = title_section.header.paragraphs[0].paragraph_format.tab_stops
    checks.append(("header has exactly one active (non-cleared) tab stop", sum(1 for t in header_tabs if t.alignment != WD_TAB_ALIGNMENT.CLEAR) == 1))

    confidential_expected = "Confidential — Do Not Distribute"
    checks.append(("title page footer has confidentiality label but no page number", title_section.footer.paragraphs[0].text == confidential_expected))
    checks.append(("front-matter footer has confidentiality label + roman page number", front_matter_section.footer.paragraphs[0].text == f"{confidential_expected}\t1" and any("PAGE" in p._p.xml for p in front_matter_section.footer.paragraphs)))
    checks.append(("body footer has confidentiality label + arabic page number", body_section.footer.paragraphs[0].text == f"{confidential_expected}\t1" and any("PAGE" in p._p.xml for p in body_section.footer.paragraphs)))
    footer_tabs = body_section.footer.paragraphs[0].paragraph_format.tab_stops
    checks.append(("footer has exactly one active (non-cleared) tab stop", sum(1 for t in footer_tabs if t.alignment != WD_TAB_ALIGNMENT.CLEAR) == 1))

    front_matter_pg_num_type = front_matter_section._sectPr.find(qn("w:pgNumType"))
    checks.append(
        (
            "front-matter section numbers in lowercase roman starting at i",
            front_matter_pg_num_type is not None
            and front_matter_pg_num_type.get(qn("w:start")) == "1"
            and front_matter_pg_num_type.get(qn("w:fmt")) == "lowerRoman",
        )
    )
    body_pg_num_type = body_section._sectPr.find(qn("w:pgNumType"))
    checks.append(
        (
            "body section numbers in arabic, restarting at 1",
            body_pg_num_type is not None
            and body_pg_num_type.get(qn("w:start")) == "1"
            and body_pg_num_type.get(qn("w:fmt")) == "decimal",
        )
    )

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"{'PASS' if ok else 'FAIL'}: {name}")

    if failed:
        print(f"\n{len(failed)}/{len(checks)} checks failed", file=sys.stderr)
        return 1

    print(f"\nAll {len(checks)} checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
