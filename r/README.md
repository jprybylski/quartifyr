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
