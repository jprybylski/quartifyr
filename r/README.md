# quartifyr r/

`rv`-managed R environment providing the pass-2 orchestration driver:
`R/render_report.R`'s `render_report()` runs the full two-pass pipeline
(Quarto shell render → `reportifyr` fill) in one call, plus a thin CLI
(`render.R`) around it. `reportifyr` and `pyro` are pulled straight from
GitHub (see `rproject.toml`) since neither has a CRAN release.

## Setup

```bash
brew install a2-ai/tap/rv   # if not already installed
cd r && rv sync
```

## Usage

As an R function (e.g. from an R console, or a project's own analysis
scripts):

```r
source("R/render_report.R")

result <- render_report(
  shell_qmd = "/path/to/project/report/shell/report.qmd",
  status = "draft"   # or "final"
)
# result$shell, result$draft, result$final (NULL unless status == "final")
```

As a one-shot CLI:

```bash
Rscript render.R /path/to/project/report/shell/report.qmd
Rscript render.R /path/to/project/report/shell/report.qmd --final
```

`shell_qmd` must live under a `report/shell/` directory --
`reportifyr::make_doc_dirs()` derives `report/draft/` and `report/final/`
output paths by substring-replacing "shell" in the containing directory
path, so this is load-bearing, not just a naming convention.

## What `render_report()` actually does

1. Regenerates `abbreviations.tex` next to `shell_qmd` from the project's
   `standard_footnotes.yaml`, via the `styling/` venv's `quartifyr-styling`
   CLI (see `../styling/README.md`).
2. Renders `shell_qmd` with Quarto against `templates/org-reference.docx`,
   passing `-M document-status:DRAFT` or `:FINAL` depending on `status`.
3. Runs `reportifyr::build_report()` to fill in tables/figures/footnotes
   from `OUTPUTS/`, producing `report/draft/<name>-draft.docx`.
4. When `status = "final"`, also runs `reportifyr::finalize_document()`,
   producing `report/final/<name>-final.docx`.
5. Optionally (`recalculate_fields = TRUE`, default off), runs
   `quartifyr-styling recalculate-fields` on each produced docx -- see
   "Word field recalculation" below.

## Word field recalculation (optional, off by default)

Quarto/pandoc docx output contains native Word field codes (`TOC`, `SEQ`,
`REF`) that don't self-populate -- without recalculation, a delivered docx
shows "Right-click to update field" instead of the actual ToC.
`../styling/quartifyr_styling/recalculate_fields.py` drives headless
LibreOffice to do that recalculation automatically, and it *works* --
verified end-to-end: a real render's ToC went from "Right-click to update
field" to real, correctly-paginated entries (" Contributors2", " Results5",
etc.) after running it.

It's off by default in `render_report()` (`recalculate_fields = FALSE`)
because the underlying `soffice --headless` invocation has also been
observed to hang intermittently in some environments, for reasons not
fully root-caused yet (ruled out: Python venv env leakage, a real
`subprocess.run(capture_output=True)` pipe-deadlock bug that's now fixed
regardless, stale profile lock files). Turn it on
(`render_report(..., recalculate_fields = TRUE)`) once you've confirmed
`quartifyr-styling recalculate-fields --docx <file>` is reliable in your
own environment. When it does fail, it only produces a warning, not a
render failure -- the document is still fully usable, just needs a manual
"select all, F9" in Word.

Known coverage gap even when it *does* work: LibreOffice only recognizes
the main document ToC as an updatable index. `quarto-plus`'s List of
Figures/List of Tables and plain `REF`-style cross-references (e.g. this
project's `appendix_crossref` shortcode) aren't recalculated by this step
and still need that manual Word update.

## A load-bearing detail: working directory

`reportifyr`/`pyro` locate their Python venv and project config by walking
**up from R's current working directory** looking for a `.*_init.json`
marker (`reportifyr:::find_project_root(start_path = getwd())`) -- they
ignore any path arguments for this. `render_report()` derives the actual
project root from `shell_qmd` and wraps every `reportifyr::` call in
`withr::with_dir(project_dir, ...)`, so it's safe to call from an R
session rooted anywhere (this `r/` project, a report project, CI). Calling
`reportifyr` functions directly without that scoping, from an R session
whose working directory isn't the target project, has been observed to
silently resolve the *wrong* project and seed a stray `pyproject.toml`/
`.venv`/`.rpfy-logs/` wherever the session happened to be -- ask why this
comment exists before removing the `with_dir()` wrapper.
