#!/usr/bin/env python3
"""Regenerate docs/assets/img/*.png from the two examples' final rendered docx.

Run after re-rendering examples/demo-report and examples/memo-example (via
`Rscript render.R --final` in each), whenever their visible content changes,
so the docs site's screenshots don't drift from what the tool actually
produces. Requires `soffice` (headless LibreOffice, for docx -> pdf) and
`uv` (to run PyMuPDF without adding it to any project's own dependencies):

    cd examples/demo-report && Rscript render.R --final && cd ../..
    cd examples/memo-example && Rscript render.R --final && cd ../..
    python3 scripts/render_doc_screenshots.py
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMG_DIR = REPO_ROOT / "docs" / "assets" / "img"

# (source docx, page index, output filename)
JOBS = [
    ("examples/demo-report/report/final/report-final.docx", 0, "demo-report-title.png"),
    ("examples/demo-report/report/final/report-final.docx", 2, "demo-report-synopsis.png"),
    ("examples/demo-report/report/final/report-final.docx", 8, "demo-report-body.png"),
    ("examples/demo-report/report/final/report-final.docx", 11, "demo-report-appendix.png"),
    ("examples/memo-example/report/final/report-final.docx", 0, "memo-example-cover.png"),
    ("examples/memo-example/report/final/report-final.docx", 1, "memo-example-body.png"),
]


def main() -> None:
    if shutil.which("soffice") is None:
        print("soffice (headless LibreOffice) not found on PATH", file=sys.stderr)
        sys.exit(1)
    if shutil.which("uv") is None:
        print("uv not found on PATH", file=sys.stderr)
        sys.exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        pdfs: dict[str, Path] = {}
        for docx_rel, _, _ in JOBS:
            if docx_rel in pdfs:
                continue
            docx = REPO_ROOT / docx_rel
            if not docx.exists():
                print(f"missing {docx} -- render it first (see module docstring)", file=sys.stderr)
                sys.exit(1)
            outdir = tmp_path / docx_rel.replace("/", "_")
            outdir.mkdir()
            subprocess.run(
                ["soffice", "--headless", "--convert-to", "pdf", "--outdir", str(outdir), str(docx)],
                check=True,
                capture_output=True,
            )
            pdfs[docx_rel] = outdir / (docx.stem + ".pdf")

        script = tmp_path / "extract.py"
        script.write_text(
            "import pymupdf, sys\n"
            "jobs = eval(sys.argv[1])\n"
            "mat = pymupdf.Matrix(2.2, 2.2)\n"
            "for pdf_path, page_idx, out_path in jobs:\n"
            "    doc = pymupdf.open(pdf_path)\n"
            "    pix = doc[page_idx].get_pixmap(matrix=mat)\n"
            "    pix.save(out_path)\n"
            "    print(f'wrote {out_path}')\n"
        )
        jobs_arg = repr(
            [(str(pdfs[docx_rel]), page_idx, str(IMG_DIR / out_name)) for docx_rel, page_idx, out_name in JOBS]
        )
        subprocess.run(["uv", "run", "--with", "pymupdf", "python3", str(script), jobs_arg], check=True)


if __name__ == "__main__":
    main()
