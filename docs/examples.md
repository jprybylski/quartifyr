---
layout: default
title: Examples
nav_order: 7
---

# Examples

Two complete, working examples ship in
[`examples/`](https://github.com/jprybylski/quartifyr/tree/main/examples)
— each a real project you can `cd` into and render yourself. Both are
built from base R's built-in datasets, so no external data is needed,
and both ship pre-generated `OUTPUTS/` so they work immediately after a
clone even before you've set up the full toolchain.

## `demo-report` — the full pipeline

A small PK-style report built from `Theoph`, exercising every piece of
the toolkit: dynamic title page, draft/final status stamp,
contributor/approver signature pages, table of contents (including the
title page), list of figures, list of tables, only-used abbreviations, a
citeproc-driven bibliography, a numbered appendix, and a real
`reportifyr` fill pass.

**Quick look (Quarto only, no R/Python)** — renders the shell with
`{rpfy}:` placeholders left literal:

```bash
cd examples/demo-report
quarto render report.qmd --to docx --reference-doc ../../templates/org-reference.docx \
  -M document-status:DRAFT
```

**Full pipeline** — real tables/figures/footnotes filled in:

```bash
cd examples/demo-report
Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'   # first clone only
Rscript render.R --final
# -> report/draft/report-draft.docx, report/final/report-final.docx
```

Rendered output from a real `report/final/report-final.docx`:

<div style="display:flex; flex-wrap:wrap; gap:1rem; margin: 1rem 0;">
<div><img src="{{ '/assets/img/demo-report-title.png' | relative_url }}" alt="demo-report title page, showing dynamic title, draft/final status stamp, and info table" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Title page</p></div>
<div><img src="{{ '/assets/img/demo-report-synopsis.png' | relative_url }}" alt="demo-report synopsis page, a bordered summary table with Title/Objectives/Methods/Results rows, including an inline embedded figure in the Results row" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Synopsis</p></div>
<div><img src="{{ '/assets/img/demo-report-body.png' | relative_url }}" alt="demo-report body page showing the filled per-participant PK summary table with a live caption, source footnote, and abbreviations line" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Filled body (PK summary table)</p></div>
<div><img src="{{ '/assets/img/demo-report-appendix.png' | relative_url }}" alt="demo-report numbered appendix page, Appendix A, generated via a Word SEQ field" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Numbered appendix</p></div>
</div>

Verify it worked with the bundled smoke test, which asserts on the
actual rendered content (no leftover `{rpfy}:` strings, tables/figures
really filled in, bibliography populated before the appendices, ...):

```bash
python3 examples/demo-report/smoke_test.py
```

## `memo-example` — the minimal end

The same pipeline's other extreme: a fax-cover-sheet-style memo cover
page (logo, left-aligned `MEMORANDUM` banner, To/From/Date/Re/Cc grid)
instead of a formal title page, and no ToC/list of figures/list of
tables/abbreviations/signature pages — a loose, short-form document. The
body still exercises a real `reportifyr` fill pass: one figure (a
milestone timeline) with a live caption and hyperlinked crossref.

```bash
cd examples/memo-example
quarto render report.qmd --to docx --reference-doc ../../templates/org-reference.docx \
  -M document-status:DRAFT   # quick look, quarto only

# full pipeline
Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'   # first clone only
Rscript render.R --final
```

<div style="display:flex; flex-wrap:wrap; gap:1rem; margin: 1rem 0;">
<div><img src="{{ '/assets/img/memo-example-cover.png' | relative_url }}" alt="memo-example cover page, showing a left-aligned MEMORANDUM banner and To/From/Date/Re/Cc grid, no table of contents" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Memo cover</p></div>
<div><img src="{{ '/assets/img/memo-example-body.png' | relative_url }}" alt="memo-example body page showing the filled budget-timeline figure with a live caption and hyperlinked crossref" width="330" loading="lazy"><p style="text-align:center; font-size:0.85em;">Filled body (figure)</p></div>
</div>

```bash
python3 examples/memo-example/smoke_test.py
```

None of the omitted sections (ToC, signature pages, ...) needed any
quartifyr code changes — see [Quarto extension](quarto-extension.html)
for how each front-matter piece is opt-in via frontmatter alone.
