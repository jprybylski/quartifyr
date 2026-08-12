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

import re
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
    checks.append(("at least 6 tables present (title info + signatures + PK summary + abbreviations; synopsis is plain paragraphs, not a table)", len(document.tables) >= 6))

    with zipfile.ZipFile(final_docx) as z:
        images = [n for n in z.namelist() if n.startswith("word/media/")]
    checks.append(("figure embedded as a real image", len(images) >= 1))

    checks.append(("title page title rendered", "Population Pharmacokinetics of Theophylline" in joined))
    checks.append(("document-status stamp rendered", "DRAFT" in joined or "FINAL" in joined))
    checks.append(("\\gls{PK} resolved to a real definition", "pharmacokinetic (pk)" in joined.lower()))

    # title_page.lua's "Title Page" ToC-entry marker -- a genuinely
    # Heading1-styled paragraph (real outline level, picked up by Word's
    # native ToC field automatically, no apply-layout step needed), made
    # invisible on the page itself via ordinary formatting (1pt size,
    # white color) rather than any "hidden" flag -- confirmed via direct
    # testing in real Word that both `<w:vanish/>` paragraphs and `TC`
    # fields (two earlier attempts) reliably showed *something* on the
    # title page regardless. See title_page.lua's file-header comment.
    checks.append(("'Title Page' ToC-entry marker present", "Title Page" in joined))
    with zipfile.ZipFile(final_docx) as z:
        document_xml_for_toc = z.read("word/document.xml").decode("utf-8")
    checks.append(
        (
            "'Title Page' marker is genuinely Heading1-styled, tiny, and white",
            re.search(
                r'<w:pStyle w:val="Heading1"/>.*?<w:sz w:val="2"/><w:szCs w:val="2"/><w:color w:val="FFFFFF"/></w:rPr><w:t[^>]*>Title Page',
                document_xml_for_toc,
                re.DOTALL,
            )
            is not None,
        )
    )
    # <w:vanish/> would exclude the paragraph from Word's ToC outline scan
    # entirely (confirmed directly in real Word) -- a regression here would
    # silently make the "Title Page" entry disappear from the ToC again.
    title_page_marker_match = re.search(
        r'<w:pStyle w:val="Heading1"/>.*?<w:t[^>]*>Title Page', document_xml_for_toc, re.DOTALL
    )
    checks.append(
        (
            "'Title Page' marker does not use <w:vanish/> (would break ToC inclusion)",
            title_page_marker_match is not None and "<w:vanish/>" not in title_page_marker_match.group(0),
        )
    )

    # Contributors and Approvers now share one "Signatures" page/ToC entry
    # (see signature_page.lua) rather than two separate Heading-1 sections.
    checks.append(("signature page uses a single 'Signatures' heading", "Signatures" in joined))
    checks.append(("Contributors sub-label rendered within Signatures", "Contributors" in joined))
    checks.append(("Approvers sub-label rendered within Signatures", "Approvers" in joined))

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

    # Front-matter section labels (Synopsis, Table of Contents, List of
    # Figures/Tables, Abbreviations) use pandoc's `custom-style="Heading
    # 1"` Div attribute to get the real Heading 1 look without becoming a
    # genuine numbered heading. This matches by *style name* ("Heading 1",
    # with a space) -- get that backwards (the style *ID* "Heading1" has
    # no space, the opposite convention from raw-OOXML pStyle references
    # elsewhere in this extension) and pandoc silently fabricates a new,
    # blank style with that literal name instead of erroring, so the text
    # renders as plain, unstyled body text with no indication anything's
    # wrong. Confirmed by making this exact mistake for real -- see
    # _extensions/quartifyr/README.md's pStyle gotcha section.
    checks.append(
        (
            "front-matter section labels use the real bold Heading 1 style, not a blank phantom one",
            "<w:b/>" in document.styles["Heading 1"].element.xml,
        )
    )

    # Synopsis is plain flowing paragraphs (label, then value line(s)), not
    # a table -- deliberately: reportifyr's auto-generated footnote for a
    # figure embedded in a table cell groups per *table element* and lands
    # after the whole table, not under the specific figure. Plain
    # body-level paragraphs get reportifyr's already-correct per-figure
    # footnote placement instead (the same mechanism the body's own
    # Figure 1 already uses without issue) -- see synopsis.lua's own
    # comment for the full reasoning trail.
    body_paragraphs = list(document.element.body.iter(qn("w:p")))
    body_paragraph_texts = ["".join(t.text or "" for t in p.findall(".//" + qn("w:t"))) for p in body_paragraphs]

    checks.append(
        (
            "synopsis title row has the real report title",
            any(
                body_paragraph_texts[i] == "Title" and body_paragraph_texts[i + 1] == "Population Pharmacokinetics of Theophylline"
                for i in range(len(body_paragraph_texts) - 1)
            ),
        )
    )

    checks.append(("logo image embedded on title page", any("png" in n.lower() for n in images)))
    checks.append(("address rendered on title page", "Raleigh, NC" in joined))

    checks.append(("synopsis value supports multi-line text", "demonstrating multi-line values with an embedded figure" in joined))
    checks.append(("synopsis figure embedded as a real image", len(images) >= 2))

    # The synopsis figure's magic string is the only one with a <width:...>
    # arg (this filter always sets one) -- distinct from the body's own
    # Figure 1 (no width arg, uses the artifact's original size) and the
    # title-page logo (not a reportifyr figure at all), so its alt text is
    # how to find it specifically among all the document's drawings.
    synopsis_fig_idx = None
    synopsis_fig_alt = ""
    for i, p in enumerate(body_paragraphs):
        for d in p.findall(".//" + qn("w:drawing")):
            for dp in d.findall(".//" + qn("wp:docPr")):
                descr = dp.get("descr") or ""
                if "<width:" in descr:
                    synopsis_fig_idx = i
                    synopsis_fig_alt = descr

    checks.append(("synopsis figure embedded as a real body-level image (not inside a table)", synopsis_fig_idx is not None))
    checks.append(
        (
            "synopsis figure carries reportifyr's own provenance metadata (a content hash) as alt text",
            "hash:" in synopsis_fig_alt,
        )
    )
    checks.append(
        (
            "synopsis figure's footnote lands immediately after the figure itself, not after an unrelated table",
            synopsis_fig_idx is not None
            and synopsis_fig_idx + 1 < len(body_paragraph_texts)
            and body_paragraph_texts[synopsis_fig_idx + 1].startswith("[Source:"),
        )
    )

    with zipfile.ZipFile(final_docx) as z:
        document_xml = z.read("word/document.xml").decode("utf-8")
    seq_figure_count = document_xml.count("SEQ Figure")
    checks.append(
        (
            "synopsis figure excluded from the List of Figures (only Figure 1's own SEQ Figure field exists)",
            seq_figure_count == 1,
        )
    )

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
    checks.append(("title page footer has confidentiality label + roman page number", title_section.footer.paragraphs[0].text == f"{confidential_expected}\t1" and any("PAGE" in p._p.xml for p in title_section.footer.paragraphs)))
    checks.append(("front-matter footer has confidentiality label + roman page number", front_matter_section.footer.paragraphs[0].text == f"{confidential_expected}\t1" and any("PAGE" in p._p.xml for p in front_matter_section.footer.paragraphs)))
    checks.append(("body footer has confidentiality label + arabic page number", body_section.footer.paragraphs[0].text == f"{confidential_expected}\t1" and any("PAGE" in p._p.xml for p in body_section.footer.paragraphs)))
    footer_tabs = body_section.footer.paragraphs[0].paragraph_format.tab_stops
    checks.append(("footer has exactly one active (non-cleared) tab stop", sum(1 for t in footer_tabs if t.alignment != WD_TAB_ALIGNMENT.CLEAR) == 1))

    title_pg_num_type = title_section._sectPr.find(qn("w:pgNumType"))
    checks.append(
        (
            "title page numbers in lowercase roman starting at i",
            title_pg_num_type is not None
            and title_pg_num_type.get(qn("w:start")) == "1"
            and title_pg_num_type.get(qn("w:fmt")) == "lowerRoman",
        )
    )
    front_matter_pg_num_type = front_matter_section._sectPr.find(qn("w:pgNumType"))
    checks.append(
        (
            "rest of front matter continues the roman sequence starting at ii",
            front_matter_pg_num_type is not None
            and front_matter_pg_num_type.get(qn("w:start")) == "2"
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
