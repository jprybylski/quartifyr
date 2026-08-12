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

`--style`/`--override`/`--out` are plain file paths, not fixed locations
— `styling/styles/*.yaml` and `templates/org-reference.docx` are just
this repo's own convention. See the repo-root README's "Style YAML and
reference-doc" section for how an org can keep its style YAML and built
reference-doc elsewhere, and how most project authors can skip running
`build` entirely by reusing an already-built `.docx`.

The generated reference-doc also sets `<w:updateFields w:val="true"/>` in
`word/settings.xml`, so Word automatically recalculates every field (ToC,
`SEQ`, `REF`, `PAGE`, ...) the moment a delivered document is opened — no
manual "select all, F9", no LibreOffice involved. See `../r/README.md`'s
"Word field recalculation" section for how this relates to
`recalculate-fields` below (this covers real Word opening the file
interactively; `recalculate-fields` covers headless/non-interactive
pipelines that never open it in an application at all).

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
OOXML sections so the whole front matter numbers in lowercase roman
(starting at "i" on the title page itself) and the body restarts at
arabic "1" -- run this on the shell docx right after the Quarto render, before
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

Also reads `crossref-hyperlinks:` (default `true`) -- `false` strips the
`\h` hyperlink switch from every figure/table/appendix cross-reference's
`REF` field, document-wide, regardless of whether `quarto-plus`'s
`crossref` shortcode or this extension's own `appendix_crossref` emitted
it. `"same-page"` can't be resolved here (no real pagination exists yet
on the pass-1 shell) -- it just marks each crossref for a separate,
opt-in, post-reportifyr step; see the next command and
`../_extensions/quartifyr/README.md`'s "Figures, tables, and
cross-references" section.

```bash
quartifyr-styling resolve-same-page-crossrefs --docx report/draft/report-draft.docx
```

Resolves the markers `apply-layout`'s `crossref-hyperlinks: "same-page"`
left behind, now that reportifyr's pass 2 has filled in real content and
pagination means something -- run on the *filled* draft/final docx, not
the shell. A no-op (skips LibreOffice entirely) if the document has no
same-page markers. Read-only with respect to LibreOffice: it drives a
headless-LibreOffice macro only to read each marked crossref's and its
target's page number (never to re-save the docx, which stays entirely in
Python's hands) -- see
`quartifyr_styling/same_page_crossrefs.py`'s docstring for why, and for
this feature's own experimental/flaky-headless-LibreOffice caveat
(inherited from, and equivalent to, `recalculate-fields`'s below).

## Tests

```bash
cd styling && python -m pytest tests/ -v
```
