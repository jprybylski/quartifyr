# quartifyr_styling

Code-first generation of the docx `reference-doc` used when rendering a
quartifyr report shell with Quarto; the abbreviations YAML →
`abbreviations.tex` bridge consumed by `quarto-plus`; and headless Word
field recalculation via LibreOffice.

## Setup

```bash
uv venv .venv --python 3.12   # from the repo root
source .venv/bin/activate
uv pip install -e "./styling[dev]"
```

## Usage

```bash
quartifyr-styling build \
  --style styling/styles/default.yaml \
  --out templates/org-reference.docx
```

Add `--override styling/styles/<org>.yaml` with just the keys that differ
from the default preset (fonts, colors, page setup, ...) to brand a new
organization — see `styles/default.yaml` for the full schema and
`quartifyr_styling/schema.py` for validation rules (hex colors, positive
sizes, etc.).

The generated docx becomes Quarto's `reference-doc:` for the shell render:

```bash
quarto render report.qmd --to docx --reference-doc templates/org-reference.docx
```

Convert a project's `standard_footnotes.yaml` into the `abbreviations.tex`
`quarto-plus` reads:

```bash
quartifyr-styling abbrevs --footnotes report/standard_footnotes.yaml --out report/shell/abbreviations.tex
```

Recalculate a rendered docx's Word ToC (page numbers, entries) in place via
headless LibreOffice -- see `../r/README.md`'s "Word field recalculation"
section for what this does and does not cover, and a known reliability
caveat:

```bash
quartifyr-styling recalculate-fields --docx path/to/report-final.docx
```

## Tests

```bash
cd styling && python -m pytest tests/ -v
```
