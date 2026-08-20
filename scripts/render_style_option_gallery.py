#!/usr/bin/env python3
"""Regenerate man/figures/style-gallery-*.png -- a side-by-side comparison
of the default style preset against a "branded" override touching most
of the style YAML's visually distinctive options at once (fonts, heading
colors/all-caps, code block shading, table banding), rendered from
examples/demo-report's actual content through the real
`Rscript render.R --final` pipeline (not a synthetic fixture), so the
docs site shows real output, not a mockup -- same technique as
render_synopsis_style_gallery.py, see that script for the rationale.

Crops the "Analysis Code" appendix page (heading + a real syntax-
highlighted code block, both style-sensitive) from each variant's final
docx.

Always restores examples/demo-report's own build artifacts (its reference
-doc, report/final/report-final.docx) to the *default* style afterward,
even if a render fails partway through -- leaving them branded would be
a real regression for anyone working in this repo, and would feed a
branded-looking screenshot into a later `render_doc_screenshots.py` run.

Requires the same toolchain as render_synopsis_style_gallery.py
(Rscript, quarto, soffice, uv, PyMuPDF) plus a `quartifyr` R package
already renv::install()d into examples/demo-report's own library (`cd
examples/demo-report && Rscript -e 'renv::install("local::../..")'` if
testing local R changes not yet released). Run from anywhere:

    python3 scripts/render_style_option_gallery.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEMO_DIR = REPO_ROOT / "examples" / "demo-report"
DEFAULT_STYLE_YAML = REPO_ROOT / "inst" / "python" / "styles" / "default.yaml"
DEFAULT_REFERENCE_DOCX = REPO_ROOT / "inst" / "templates" / "org-reference.docx"
IMG_DIR = REPO_ROOT / "man" / "figures"

# Touches most of the style YAML's visually distinctive options at once,
# to make one compelling "this is what a rebrand looks like" comparison
# rather than a screenshot per option -- see vignettes/articles/
# styling.Rmd's own reference table for the exhaustive, non-visual list.
BRANDED_OVERRIDE_YAML = """
fonts:
  body: "Calibri"
  heading: "Calibri"
  monospace: "Consolas"
colors:
  heading: "#0054AD"
  title: "#0054AD"
  table_header_fill: "#CFE2FF"
  rule: "#0054AD"
heading:
  all_caps: true
code:
  background_color: "#FFF3CD"
  padding_pt: 4
table:
  banding: true
"""

_CROP_SCRIPT = """
import sys
import fitz

pdf_path, out_path = sys.argv[1], sys.argv[2]
doc = fitz.open(pdf_path)
# Case-insensitive: heading.all_caps (the "branded" variant) bakes an
# actual ALL CAPS text layer into the exported PDF, not just a visual
# transform -- confirmed via a real soffice conversion.
page = next(p for p in doc if "analysis code" in p.get_text().lower())
appendix_hits = page.search_for("Appendix") or page.search_for("APPENDIX")
top = min(r.y0 for r in appendix_hits) - 10
bottom = min(page.rect.height - 20, top + 430)
rect = fitz.Rect(page.rect.x0, top, page.rect.x1, bottom)
pix = page.get_pixmap(dpi=200, clip=rect)
pix.save(out_path)
"""

_RENDER_R = """
library(quartifyr)
render_report(
  shell_qmd = file.path("{project_dir}", "report.qmd"),
  status = "final",
  reference_doc = "{reference_doc}"
)
"""


def _render_variant(name: str, reference_doc: Path, work_dir: Path) -> Path | None:
    r_script = _RENDER_R.format(project_dir=str(DEMO_DIR), reference_doc=str(reference_doc))
    result = subprocess.run(["Rscript", "-e", r_script], cwd=DEMO_DIR, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        print(f"FAIL: render_report() failed for style variant: {name}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None

    final_docx = DEMO_DIR / "report" / "final" / "report-final.docx"
    if not final_docx.exists():
        print(f"FAIL: {final_docx} not produced for style variant: {name}", file=sys.stderr)
        return None

    pdf_path = work_dir / f"{name}.pdf"
    result = subprocess.run(
        ["soffice", "--headless", "--convert-to", "pdf", "--outdir", str(work_dir), str(final_docx)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0 or not (work_dir / "report-final.pdf").exists():
        print(f"FAIL: soffice conversion failed for style variant: {name}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None
    (work_dir / "report-final.pdf").rename(pdf_path)

    out_path = IMG_DIR / f"style-gallery-{name}.png"
    crop_script = work_dir / "_crop.py"
    crop_script.write_text(_CROP_SCRIPT, encoding="utf-8")
    result = subprocess.run(["uv", "run", "--with", "pymupdf", "python3", str(crop_script), str(pdf_path), str(out_path)], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAIL: crop failed for style variant: {name}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None

    return out_path


def main() -> int:
    for tool in ("Rscript", "quarto", "soffice", "uv"):
        if shutil.which(tool) is None:
            print(f"SKIP: {tool} not found on PATH", file=sys.stderr)
            return 0

    written: list[Path] = []
    try:
        with tempfile.TemporaryDirectory(prefix="quartifyr-style-gallery-") as tmp:
            work_dir = Path(tmp)

            branded_yaml = work_dir / "branded.yaml"
            branded_yaml.write_text(BRANDED_OVERRIDE_YAML, encoding="utf-8")
            branded_docx = work_dir / "branded-reference.docx"
            result = subprocess.run(
                [
                    "quartifyr-styling", "build",
                    "--style", str(DEFAULT_STYLE_YAML),
                    "--override", str(branded_yaml),
                    "--out", str(branded_docx),
                ],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                print("FAIL: building the branded reference-doc failed", file=sys.stderr)
                print(result.stdout, file=sys.stderr)
                print(result.stderr, file=sys.stderr)
                return 1

            for name, reference_doc in [("default", DEFAULT_REFERENCE_DOCX), ("branded", branded_docx)]:
                print(f"Rendering style variant: {name} ...")
                out_path = _render_variant(name, reference_doc, work_dir)
                if out_path is None:
                    return 1
                written.append(out_path)
                print(f"wrote {out_path}")
    finally:
        # Restore the demo's own render outputs to the default style, so a
        # stray `git status` after this script doesn't show a
        # gitignored-but-branded build artifact as a surprise, and so a
        # later render_doc_screenshots.py run doesn't pick up branded
        # output by accident.
        subprocess.run(["Rscript", "render.R", "--final"], cwd=DEMO_DIR, capture_output=True, text=True, timeout=180)

    print(f"\nWrote {len(written)} comparison images to {IMG_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
