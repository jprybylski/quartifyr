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

Apply a dynamic page header and footer, and (if the `.qmd` uses `{{<
body-start >}}`) split the rendered docx into title-page/front-matter/body
OOXML sections so the title page has no page number, the rest of the
front matter numbers in lowercase roman, and the body restarts at arabic
"1" -- run this on the shell docx right after the Quarto render, before
`reportifyr`'s pass-2 fill (this is what `render_report()` does
automatically -- see `../r/README.md`'s "Page header/footer and page
numbering" section):

```bash
quartifyr-styling apply-layout --docx report/shell/report.docx --qmd report.qmd --status draft
```

Reads `--qmd`'s frontmatter for `header-format:` (a `"{project} -
{report_number}"`-style template, resolved against any frontmatter keys
plus `{status}` from `--status`) and applies it to the header's left
zone on every page -- the header's right zone always shows the
draft/final status once a header is enabled. Also reads `confidentiality:`
for the footer's left-side label (the same field `title_page.lua` renders
on the title page). A `.qmd` with no `header-format:` and no `{{<
body-start >}}` is left untouched -- both are opt-in.

## Tests

```bash
cd styling && python -m pytest tests/ -v
```
