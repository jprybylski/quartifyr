# quartifyr r/

`rv`-managed R environment providing the pass-2 orchestration driver:
`R/render_report.R`'s `render_report()` runs the full two-pass pipeline
(Quarto shell render → `reportifyr` fill) in one call, plus a thin CLI
(`render.R`) around it. `reportifyr` and `pyro` are pulled straight from
GitHub (see `rproject.toml`) since neither has a CRAN release.

This is a convenience wrapper, not a requirement — it chains `quarto
render`, `quartifyr-styling apply-layout`, and `reportifyr::build_report()`
together and adopts a specific `report/shell`/`report/draft`/`report/final`
directory convention. If you already have your own Quarto and
`reportifyr` project setup, you can call those three pieces yourself
instead; see the repo-root README's
[Using the pieces directly](../README.md#using-the-pieces-directly).

## Setup

Requires [`rv`](https://a2-ai.github.io/rv-docs/) (cross-platform install
instructions at that link), then:

```bash
cd r && rv sync
```

**Windows**: `rv sync` currently isn't reliable on Windows for this
project, for two identified reasons ([investigated here](https://github.com/jprybylski/quartifyr/issues/4)):

- This project's `rproject.toml` files used to pin
  `r_version = "4.6"`, while `pyro` and `reportifyr` (both pulled from
  GitHub, always built from source -- see `rproject.toml`) each carry
  their *own* bundled `rproject.toml` pinned to `r_version = "4.5"`. `rv`
  activates its managed library by walking up from an R subprocess's cwd
  looking for an `rproject.toml`; during `rv sync`, the subprocess built
  to compile `pyro`/`reportifyr` from source picks up *their* bundled
  file, not just this project's, so running R 4.6.1 against that 4.5 pin
  made `rv` enter "safe mode" -- confirmed directly, a real Windows CI
  run of this repo reproduced the exact message: "R version specified in
  config (4.5) does not match session version (4.6.1)... entering safe
  mode". This is now fixed by pinning `r_version = "4.5"` here too,
  matching upstream.

That fix wasn't sufficient, though. With the version pin aligned, `rv
sync` on Windows still fails installing `pyro` from source, every time
(reproduced twice in independent CI runs):

```
Failed to install pyro:
    ...
    ** byte-compile and prepare package for lazy loading
    Error in loadNamespace(j <- i[[1L]], c(lib.loc, .libPaths()), versionCheck = vI[[j]]) :
      there is no package called 'rlang'
    ...
    ERROR: lazy loading failed for package 'pyro'
```

`rlang` *is* correctly resolved as a dependency of `pyro` in the
committed `rv.lock` -- this isn't a dependency-graph bug, it's rv's
installer not guaranteeing `rlang` is actually installed and visible on
the library path before starting `pyro`'s from-source build on Windows.
The identical error/symptom was previously reported and closed as
[A2-ai/rv#27](https://github.com/A2-ai/rv/issues/27) without a documented
fix, so this looks like either a regression or an edge case (specifically
around GitHub-sourced packages' from-source Windows builds) that wasn't
actually resolved. There's no `rv sync` flag to force serial installs as
a workaround. `A2-ai/reportifyr`'s own CI does pass `rv sync` on
`windows-latest` and adds a PPM repository the same way this project
tried, but that's not proof this specific failure is avoidable: its own
`rproject.toml` (`use_lockfile = false`) pulls `pyro` from a private
prebuilt-binary package repository, not from GitHub source like this
project's `rproject.toml` does -- so it never exercises the
build-pyro-from-git-source path that triggers this failure here.

Because of this, CI doesn't verify the full Quarto+R+reportifyr pipeline
on Windows (see `.github/workflows/ci.yml`); `styling/`'s pytest suite,
which doesn't touch `rv`, is verified on Windows.

### Using `renv` instead of `rv`

`rv` was chosen here to match `reportifyr`/`pyro`'s own A2-ai ecosystem
convention (both ship an `rproject.toml`, not a `renv.lock`), but nothing
about quartifyr's own mechanics -- `quarto render`, `quartifyr-styling`,
`render_report()` -- cares which R package manager put `reportifyr` on
the library path. `renv` is a reasonable alternative, particularly on
Windows: it's the more broadly-used, Posit-backed tool, and doesn't have
the all-or-nothing R-version-mismatch gate that causes `rv`'s Windows
problem above -- confirmed directly (not just by reputation): a real
`renv` project with `reportifyr`/`pyro` installed from GitHub, given a
deliberately mismatched R version in `renv.lock`, produced only an
`renv::status()` warning ("out-of-sync... lockfile was generated with R
4.5.0, but you're using R 4.6.1") -- `library(reportifyr)` still loaded
fine, no refusal to activate. `rv` and `renv` can't both manage the same
project at once (they each own `.Rprofile`-based library activation), so
switching means replacing `rv` here entirely, not layering `renv` on top.
What would differ:

- **`renv.lock`** (JSON) instead of `rproject.toml`/`rv.lock` (TOML) as
  the dependency manifest.
- **`renv::restore()`** instead of `rv sync` to install from the lockfile;
  **`renv::snapshot()`** instead of `rv` auto-updating `rv.lock` on
  `rv add`/`rv sync`. Note `renv::snapshot()`'s default `type = "implicit"`
  only records packages actually referenced via `library()`/`require()`
  somewhere in the project's `.R`/`.qmd` files -- confirmed directly: a
  freshly `renv::install()`-ed package didn't appear in `renv.lock` at
  all until a script `library()`-referenced it. `rv`, by contrast, tracks
  whatever's explicitly listed in `rproject.toml` regardless of whether
  any script currently uses it. Worth knowing before assuming an
  `renv::install()` alone is "done."
- **GitHub-only packages** (`reportifyr`, `pyro` -- neither has a CRAN
  release): install with `renv::install("a2-ai/reportifyr")` and
  `renv::install("a2-ai/pyro")`; `renv::snapshot()` then records the
  GitHub remote in `renv.lock` automatically (confirmed directly --
  `"RemoteType": "github", "RemoteUsername": "a2-ai", "RemoteRepo":
  "reportifyr", "RemoteRef": "main", "RemoteSha": "<commit>"`), playing
  the same role as `rproject.toml`'s explicit `git =
  "https://github.com/a2-ai/reportifyr.git"` dependency entries.
- **Activation**: `renv`'s own bootstrap in `.Rprofile`
  (`source("renv/activate.R")`, generated by `renv::init()` -- confirmed
  directly) instead of `rv`'s (`source("rv/scripts/rvr.R")` /
  `source("rv/scripts/activate.R")`).
- **`.gitignore`**: `renv/library/` instead of `rv/library/` (both are
  regenerable local package caches, not source).

## Usage

As an R function (e.g. from an R console, or a project's own analysis
scripts):

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

`shell_qmd` lives at the project root alongside `_extensions/` (standard
Quarto project layout -- extensions are discovered relative to the qmd
being rendered). The project's `_quarto.yml` must set `project:
{output-dir: report/shell}`, since `reportifyr::make_doc_dirs()` derives
`report/draft/` and `report/final/` output paths by substring-replacing
"shell" in the *rendered docx's* containing directory -- not the qmd's --
so this is load-bearing, not just a naming convention. See
`examples/demo-report/` for a working example of this layout.

The example above omits `reference_doc`/`venv_bin`, relying on their
defaults (see `?render_report`/`R/render_report.R`'s own docs) -- that
only works for a project nested inside this quartifyr checkout. For a
standalone project, pass both explicitly; see the repo-root README's
"Style YAML and reference-doc" section.

## What `render_report()` actually does

1. Regenerates `abbreviations.tex` next to `shell_qmd` from the project's
   `standard_footnotes.yaml`, via the `styling/` venv's `quartifyr-styling`
   CLI (see `../styling/README.md`).
2. Renders `shell_qmd` with Quarto against `templates/org-reference.docx`,
   passing `-M document-status:DRAFT` or `:FINAL` depending on `status`.
3. Runs `quartifyr-styling apply-layout` on the rendered shell -- applies a
   dynamic page header (from the `.qmd`'s `header-format:` frontmatter, if
   set) and, if the `.qmd` uses `{{< body-start >}}`, splits front matter
   from the body into separate OOXML sections so body page numbering
   restarts at 1. See "Page header/footer and page-restart" below.
4. Runs `reportifyr::build_report()` to fill in tables/figures/footnotes
   from `OUTPUTS/`, producing `report/draft/<name>-draft.docx`.
5. When `status = "final"`, also runs `reportifyr::finalize_document()`,
   producing `report/final/<name>-final.docx`.
6. Optionally (`resolve_same_page_crossrefs = TRUE`, default off), runs
   `quartifyr-styling resolve-same-page-crossrefs` on each produced docx
   -- see "Same-page cross-reference resolution" below.
7. Optionally (`recalculate_fields = TRUE`, default off), runs
   `quartifyr-styling recalculate-fields` on each produced docx -- see
   "Word field recalculation" below.

## Page header/footer and page numbering

Opt-in, driven entirely by the shell `.qmd`'s frontmatter and body --
nothing to configure in `render_report()` itself:

- `header-format: "{project} - {report_number}"` (any frontmatter keys as
  `{placeholder}`s) renders a two-zone header on every page: the resolved
  template flush left, and the draft/final status flush right (always
  shown, once a header is enabled).
- `title_page.lua` automatically marks where the title page ends, and
  `{{< body-start >}}`, placed right before the first real body heading
  (e.g. right before `# Introduction`), marks where the numbered body
  begins. Together, these split the document into three page-numbering
  regions: the title page (lowercase roman, starting at "i"), the rest
  of the front matter (ToC, list of figures/tables, abbreviations,
  synopsis, signature pages, ... -- same roman sequence, continuing at
  "ii"), and the body (arabic, restarting at "1"). If a `.qmd` never
  uses `{{< body-start >}}`, the document is left as a single section --
  the header (if set) still applies throughout, but there's no
  page-number split.
- Every footer also shows a confidentiality label on the left, reusing
  whatever `confidentiality:` is already set to for the title page (see
  `../_extensions/quartifyr/README.md`) -- blank if `confidentiality:`
  isn't set.

See `../_extensions/quartifyr/README.md` and
`../styling/README.md`'s `apply-layout` section for the mechanics.

## Same-page cross-reference resolution (optional, off by default)

`crossref-hyperlinks: "same-page"` in the shell `.qmd`'s frontmatter (see
`../_extensions/quartifyr/README.md`'s "Figures, tables, and
cross-references" section) asks for figure/table/appendix
cross-references to be hyperlinked only when their target lands on a
*different* page. `apply_layout()` (step 3, above) can't resolve that by
itself -- it runs on the empty pass-1 shell, before real pagination
exists -- so it only marks each crossref for later resolution and leaves
it hyperlinked (the safe fallback).

`../styling/quartifyr_styling/same_page_crossrefs.py` is that later step:
it reads each marked crossref's and its target's real page number via a
small headless-LibreOffice macro (read-only -- it never re-saves the
docx; every actual edit happens in Python) and strips the hyperlink where
they match. A no-op, skipping LibreOffice entirely, if the document has
no same-page markers at all.

It's off by default (`resolve_same_page_crossrefs = FALSE`) and drives
the exact same headless-`soffice --headless ... macro:///...` mechanism
as `recalculate-fields` below, so it inherits that mechanism's own
documented unreliability wholesale -- not independently re-verified
end-to-end in this project's own development environment (every attempted
run, of this step and of the pre-existing `recalculate-fields`, timed out
rather than completing). An earlier version of `"same-page"` instead
tried to push the whole comparison into a live nested Word field so
Word/LibreOffice would resolve it on its own during any later
recalculation; abandoned after confirming, via a real headless-LibreOffice
round-trip, that it silently corrupts the field instead of evaluating it
-- see `same_page_crossrefs.py`'s module docstring for the full story.
Treat this as experimental, the same as `recalculate_fields`: turn it on
only after confirming it's reliable in your own environment, and a
failure here only warns, never fails the render.

## Word field recalculation (optional, off by default)

Quarto/pandoc docx output contains native Word field codes (`TOC`, `SEQ`,
`REF`) that don't self-populate -- without recalculation, a delivered docx
shows "Right-click to update field" instead of the actual ToC.

**For anyone opening the delivered docx in real Microsoft Word, this is
already handled for free**, no LibreOffice involved: the reference-doc
(`../styling/quartifyr_styling/build_template.py`) sets `<w:updateFields
w:val="true"/>` in `word/settings.xml`, which tells Word to recalculate
every field automatically the moment the file is opened -- confirmed to
survive Quarto's reference-doc handling, `apply-layout`, and `reportifyr`
into the actual delivered docx (`examples/demo-report/smoke_test.py`
asserts on this). This is a genuine Word feature, not something quartifyr
invented, and has none of the reliability caveats below -- it's a document
setting Word itself honors, not an external process. It doesn't help
anyone opening the file in a *headless* pipeline (e.g. this project's own
CI, or a script converting the docx without ever displaying it) or in
LibreOffice running non-interactively, which is what the rest of this
section is for.

`../styling/quartifyr_styling/recalculate_fields.py` drives headless
LibreOffice to do that same recalculation for those non-interactive cases,
so a produced docx already shows resolved fields even before anyone opens
it in Word. It *works* -- verified end-to-end: a real render's ToC went
from "Right-click to update field" to real, correctly-paginated entries
(" Signatures2", " Results5", etc.) after running it.

It's off by default in `render_report()` (`recalculate_fields = FALSE`)
and should be considered **experimental**: repeated real-world runs
against the same document have shown three distinct outcomes -- it hangs
indefinitely, it exits cleanly within seconds without the macro having
actually run (file untouched), or it works correctly end-to-end. This has
been reproduced both in a sandboxed environment and a plain native macOS
terminal (ruling out sandboxing as the cause), so it looks like a genuine
LibreOffice/macOS interaction bug outside quartifyr's control, not
something fixable from here. The module now defends against the two
failure modes it *can* control: the whole `soffice` process group gets
killed on timeout (not just the tracked PID, which could otherwise leave
an orphaned worker process running indefinitely), and it verifies the ToC
placeholder actually disappeared rather than trusting a clean exit code --
so a run either genuinely succeeds or fails loudly, never silently
no-ops. Turn it on (`render_report(..., recalculate_fields = TRUE)`) only
after you've confirmed it's reliable enough for your own use, and expect
to sometimes need a manual re-run. When it does fail, it only produces a
warning, not a render failure -- the document is still fully usable, just
needs a manual "select all, F9" in Word.

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
