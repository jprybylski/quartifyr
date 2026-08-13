---
layout: default
title: Styling
nav_order: 5
---

# Styling

`quartifyr-styling` (the Python package in `styling/`) is code-first
generation of the docx `reference-doc` used when rendering a quartifyr
shell with Quarto, the abbreviations YAML → `abbreviations.tex` bridge
consumed by `quarto-plus`, and headless Word field/cross-reference
post-processing via LibreOffice.

```bash
uv venv .venv --python 3.12   # from the repo root
source .venv/bin/activate
uv pip install -e "./styling[dev]"
```

## `build`: style YAML → reference-doc

```bash
quartifyr-styling build \
  --style styling/styles/default.yaml \
  --out templates/org-reference.docx
```

<img src="{{ '/assets/img/styling-build.gif' | relative_url }}" alt="Terminal recording of quartifyr-styling build generating a docx reference-doc from a style YAML file" width="700" loading="lazy">

Add `--override styling/styles/<org>.yaml` with just the keys that
differ from the default preset (fonts, colors, page setup, ...) to brand
a new organization; see `styling/styles/default.yaml` for the full
schema and `styling/quartifyr_styling/schema.py` for validation rules
(hex colors, positive sizes, valid page sizes, ...).

`--style`/`--override`/`--out` are plain file paths, not fixed locations;
`styling/styles/*.yaml` and `templates/org-reference.docx` are just
this repo's own convention. An org can keep its style YAML anywhere, and
most project authors never need to run `build` at all: reuse an
already-built `.docx`, distributed however your org already shares
binary artifacts.

The generated reference-doc also sets `<w:updateFields w:val="true"/>`
in `word/settings.xml`, so real Word automatically recalculates every
field (ToC, `SEQ`, `REF`, `PAGE`, ...) the moment a delivered document is
opened; no manual "select all, F9", no LibreOffice involved for that
case.

## `abbrevs`: footnotes YAML → abbreviations bridge

```bash
quartifyr-styling abbrevs \
  --footnotes report/standard_footnotes.yaml \
  --out report/shell/abbreviations.tex
```

Converts a project's `standard_footnotes.yaml` (`reportifyr`'s own
format) into the `abbreviations.tex` that `quarto-plus` reads to render
a "only abbreviations actually used via `\gls{}`" list.

## `apply-layout`: header/footer + page-number split

```bash
quartifyr-styling apply-layout \
  --docx report/shell/report.docx --qmd report.qmd --status draft
```

Run on the shell docx right after the Quarto render, before
`reportifyr`'s pass-2 fill. Reads `--qmd`'s frontmatter for
`header-format:` and applies it to a two-zone page header (template flush
left, draft/final status flush right). Also reads `confidentiality:` for
the footer's left zone, and, if the `.qmd` uses `{% raw %}{{< body-start >}}{% endraw %}`,
splits the rendered docx into title-page/front-matter/body OOXML
sections so the whole front matter numbers in lowercase roman (starting
at "i") and the body restarts at arabic "1". A `.qmd` with neither
`header-format:` nor `{% raw %}{{< body-start >}}{% endraw %}` is left untouched; both are
opt-in.

Also reads `crossref-hyperlinks:` (default `true`); `false` strips the
`\h` hyperlink switch from every figure/table/appendix cross-reference's
`REF` field, document-wide. `"same-page"` can't be resolved here (no
real pagination exists yet on the pass-1 shell); it just marks each
crossref for the next command.

## `resolve-same-page-crossrefs`: post-fill crossref resolution

```bash
quartifyr-styling resolve-same-page-crossrefs \
  --docx report/draft/report-draft.docx
```

Resolves the markers `apply-layout`'s `crossref-hyperlinks: "same-page"`
left behind, now that `reportifyr`'s pass 2 has filled in real content
and pagination means something; run on the *filled* draft/final docx,
not the shell. A no-op (skips LibreOffice entirely) if the document has
no same-page markers. Read-only with respect to LibreOffice: it drives a
headless-LibreOffice macro only to read page numbers, never to re-save
the docx.

**Experimental.** Inherits the same intermittent-hang behavior
documented for `recalculate-fields` below. Off by default in
`render_report()`.

## `recalculate-fields`: headless ToC/field recalculation

```bash
quartifyr-styling recalculate-fields --docx path/to/report-final.docx
```

Drives headless LibreOffice to recalculate a docx's Word ToC (page
numbers, entries) in place; for non-interactive pipelines that never
open the file in an application at all. Real Word already recalculates
fields automatically on open (via the reference-doc's own
`updateFields` setting above), so this is only needed for headless
consumers.

**Experimental and known-flaky.** Real-world runs against the same
document have produced three different outcomes: it hangs, it exits
cleanly as a silent no-op, or it actually succeeds. Reproduced both
sandboxed and in a plain native terminal, ruling out sandboxing as the
cause. Off by default (`render_report(..., recalculate_fields = FALSE)`).
When it does fail, it only produces a warning, not a render failure;
the document is still fully usable, just needs a manual "select all,
F9" in Word.

## Tests

```bash
cd styling && python -m pytest tests/ -v
```
