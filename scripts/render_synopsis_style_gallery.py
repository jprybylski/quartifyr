#!/usr/bin/env python3
"""Regenerate man/figures/synopsis-style-*.png -- a side-by-side
comparison of synopsis-style: definition-list/inline/table, each
rendered from examples/demo-report's actual content through the real
`Rscript render.R --final` pipeline (not a synthetic fixture), so the
docs site shows real output, not a mockup.

Temporarily rewrites report.qmd's `synopsis-style:` line once per
style, renders, screenshots, and restores the original line -- always,
even if a render fails partway through, since leaving the demo's
tracked frontmatter mutated would be a real regression for anyone
working in this repo after this script runs.

Requires the same toolchain as scripts/render_doc_screenshots.py
(Rscript, quarto, soffice, uv) plus PyMuPDF via `uv run --with pymupdf`.
Run from anywhere:

    python3 scripts/render_synopsis_style_gallery.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEMO_DIR = REPO_ROOT / "examples" / "demo-report"
REPORT_QMD = DEMO_DIR / "report.qmd"
IMG_DIR = REPO_ROOT / "man" / "figures"

STYLES = ["definition-list", "inline", "table"]

_CROP_SCRIPT = """
import sys
import fitz

pdf_path, out_path, style = sys.argv[1], sys.argv[2], sys.argv[3]
doc = fitz.open(pdf_path)
page = next(p for p in doc if "Objectives" in p.get_text())

top = min(r.y0 for r in page.search_for("Synopsis"))
images = page.get_image_info()

if style == "table":
    # The embedded figure sits *inside* the table's last row here, and
    # the footnote landing below the whole table (not tucked under the
    # figure) is the entire point of this style's warning -- crop deep
    # enough to actually show that, not just cut it off at the image.
    bottom = min(page.rect.height - 20, (max((im["bbox"][3] for im in images), default=0) + 260))
else:
    # definition-list/inline: stop right before the embedded figure --
    # it's identical across all three styles and would just make the
    # comparison images unnecessarily tall.
    bottom = min((im["bbox"][1] for im in images), default=page.rect.height) - 6

rect = fitz.Rect(page.rect.x0, top - 10, page.rect.x1, bottom)
pix = page.get_pixmap(dpi=200, clip=rect)
pix.save(out_path)
"""


def _render_style(style: str, work_dir: Path) -> Path | None:
    result = subprocess.run(["Rscript", "render.R", "--final"], cwd=DEMO_DIR, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        print(f"FAIL: render.R --final failed for synopsis-style: {style}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None

    final_docx = DEMO_DIR / "report" / "final" / "report-final.docx"
    if not final_docx.exists():
        print(f"FAIL: {final_docx} not produced for synopsis-style: {style}", file=sys.stderr)
        return None

    pdf_path = work_dir / f"{style}.pdf"
    result = subprocess.run(
        ["soffice", "--headless", "--convert-to", "pdf", "--outdir", str(work_dir), str(final_docx)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0 or not (work_dir / "report-final.pdf").exists():
        print(f"FAIL: soffice conversion failed for synopsis-style: {style}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None
    (work_dir / "report-final.pdf").rename(pdf_path)

    out_path = IMG_DIR / f"synopsis-style-{style}.png"
    crop_script = work_dir / "_crop.py"
    crop_script.write_text(_CROP_SCRIPT, encoding="utf-8")
    result = subprocess.run(["uv", "run", "--with", "pymupdf", "python3", str(crop_script), str(pdf_path), str(out_path), style], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAIL: crop failed for synopsis-style: {style}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None

    return out_path


def main() -> int:
    for tool in ("Rscript", "quarto", "soffice", "uv"):
        if shutil.which(tool) is None:
            print(f"SKIP: {tool} not found on PATH", file=sys.stderr)
            return 0

    original_qmd = REPORT_QMD.read_text(encoding="utf-8")
    match = re.search(r"^synopsis-style: \S+$", original_qmd, re.M)
    if match is None:
        print(f"FAIL: no 'synopsis-style: ...' line found in {REPORT_QMD}", file=sys.stderr)
        return 1

    written: list[Path] = []
    try:
        with tempfile.TemporaryDirectory(prefix="quartifyr-synopsis-gallery-") as tmp:
            work_dir = Path(tmp)
            for style in STYLES:
                print(f"Rendering synopsis-style: {style} ...")
                REPORT_QMD.write_text(original_qmd[: match.start()] + f"synopsis-style: {style}" + original_qmd[match.end() :], encoding="utf-8")
                out_path = _render_style(style, work_dir)
                if out_path is None:
                    return 1
                written.append(out_path)
                print(f"wrote {out_path}")
    finally:
        REPORT_QMD.write_text(original_qmd, encoding="utf-8")
        # Restore the demo's own render outputs to match its committed
        # synopsis-style, so a stray `git status` after this script
        # doesn't show gitignored-but-stale build artifacts as a
        # surprise -- cheap since it's the last (and therefore already
        # cached-data) style rendered.
        subprocess.run(["Rscript", "render.R", "--final"], cwd=DEMO_DIR, capture_output=True, text=True, timeout=180)

    print(f"\nWrote {len(written)} comparison images to {IMG_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
