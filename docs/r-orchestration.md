---
layout: default
title: R Orchestration
nav_order: 6
---

# R orchestration

`r/` is an `rv`-managed R environment providing the pass-2 orchestration
driver: `render_report()` runs the full two-pass pipeline (Quarto shell
render → `reportifyr` fill) in one call, plus a thin CLI (`render.R`)
around it. `reportifyr` and `pyro` are pulled straight from GitHub since
neither has a CRAN release.

This is a convenience wrapper, not a requirement — it chains `quarto
render`, `quartifyr-styling apply-layout`, and
`reportifyr::build_report()` together and adopts a specific
`report/shell`/`report/draft`/`report/final` directory convention. See
[Architecture](architecture.html#using-the-pieces-directly) for calling
the three pieces directly instead.

## Setup

```bash
cd r && rv sync
```

See [Installation](installation.html) for the Windows caveat.

## Usage

As an R function:

```r
source("R/render_report.R")

result <- render_report(
  shell_qmd = "/path/to/project/report.qmd",
  status = "draft"   # or "final"
)
# result$shell, result$draft, result$final (NULL unless status == "final")
```

As a one-shot CLI:

```bash
Rscript render.R /path/to/project/report.qmd
Rscript render.R /path/to/project/report.qmd --final
```

<img src="{{ '/assets/img/render-pipeline.gif' | relative_url }}" alt="Terminal recording of Rscript render.R running the full two-pass pipeline on the demo report, then Rscript render.R --final, producing report/draft and report/final docx files" width="700" loading="lazy">

`shell_qmd` lives at the project root alongside `_extensions/`. The
project's `_quarto.yml` must set `project: {output-dir: report/shell}`,
since `reportifyr::make_doc_dirs()` derives `report/draft/` and
`report/final/` output paths by substring-replacing "shell" in the
*rendered docx's* containing directory — not the qmd's — so this is
load-bearing, not just a naming convention.

## What `render_report()` actually does

1. Regenerates `abbreviations.tex` next to `shell_qmd` from the
   project's `standard_footnotes.yaml`, via `quartifyr-styling abbrevs`.
2. Renders `shell_qmd` with Quarto against `templates/org-reference.docx`,
   passing `-M document-status:DRAFT` or `:FINAL` depending on `status`.
3. Runs `quartifyr-styling apply-layout` on the rendered shell.
4. Runs `reportifyr::build_report()` to fill in tables/figures/footnotes
   from `OUTPUTS/`, producing `report/draft/<name>-draft.docx`.
5. When `status = "final"`, also runs `reportifyr::finalize_document()`,
   producing `report/final/<name>-final.docx`.
6. Optionally (`resolve_same_page_crossrefs = TRUE`, default off), runs
   `quartifyr-styling resolve-same-page-crossrefs` on each produced docx.
7. Optionally (`recalculate_fields = TRUE`, default off), runs
   `quartifyr-styling recalculate-fields` on each produced docx.

See [Styling](styling.html) for what each of those `quartifyr-styling`
subcommands does on its own.

## A load-bearing detail: working directory

`reportifyr`/`pyro` locate their Python venv and project config by
walking **up from R's current working directory** looking for a
`.*_init.json` marker — they ignore path arguments for this.
`render_report()` derives the actual project root from `shell_qmd` and
wraps every `reportifyr::` call in `withr::with_dir(project_dir, ...)`,
so it's safe to call from an R session rooted anywhere. Calling
`reportifyr` functions directly without that scoping, from an R session
whose working directory isn't the target project, has been observed to
silently resolve the *wrong* project and seed a stray
`pyproject.toml`/`.venv`/`.rpfy-logs/` wherever the session happened to
be.

## Word field recalculation (optional, off by default)

Quarto/pandoc docx output contains native Word field codes (`TOC`,
`SEQ`, `REF`) that don't self-populate. For anyone opening the delivered
docx in real Microsoft Word, this is already handled for free — the
reference-doc sets `<w:updateFields w:val="true"/>`, which tells Word to
recalculate every field automatically on open. This doesn't help a
headless pipeline or LibreOffice running non-interactively — see
[Styling](styling.html#recalculate-fields--headless-tocfield-recalculation)
for the experimental step that covers that case, and its known
reliability caveat.

Known coverage gap even when it *does* work: LibreOffice only recognizes
the main document ToC as an updatable index. `quarto-plus`'s List of
Figures/List of Tables and plain `REF`-style cross-references aren't
recalculated by this step and still need a manual Word update.
