# quartifyr r/

`renv`-managed R environment providing the pass-2 orchestration driver:
`R/render_report.R`'s `render_report()` runs the full two-pass pipeline
(Quarto shell render → `reportifyr` fill) in one call, plus a thin CLI
(`render.R`) around it. `reportifyr` and `pyro` are pulled from
[A2-ai's r-universe](https://a2-ai.r-universe.dev) (see `.Rprofile`'s
`repos` option and `renv.lock`'s `Repositories`) since neither has a
CRAN release.

This is a convenience wrapper, not a requirement — it chains `quarto
render`, `quartifyr-styling apply-layout`, and `reportifyr::build_report()`
together and adopts a specific `report/shell`/`report/draft`/`report/final`
directory convention. If you already have your own Quarto and
`reportifyr` project setup, you can call those three pieces yourself
instead; see the repo-root README's
[Using the pieces directly](../README.md#using-the-pieces-directly).

## Setup

Requires [`renv`](https://rstudio.github.io/renv/) (`install.packages("renv")`
from any R session), then:

```bash
cd r && Rscript -e 'renv::restore()'
```

This installs every package pinned in `renv.lock` -- including
`reportifyr`/`pyro`, resolved as ordinary package-repository installs
against `a2-ai.r-universe.dev` -- into a project-local `renv/library/`,
isolated from any other R project's library. `.Rprofile`
(`source("renv/activate.R")`) activates that library automatically the
moment R starts in this directory, so no further setup is needed once
`restore()` finishes.

`DESCRIPTION`'s `Imports:` list, not what any individual `.R` file happens
to `library()`/`::`-reference, is what `renv::snapshot()` treats as this
project's direct dependencies (`snapshot.type: explicit` in
`renv/settings.json`) -- add a new direct dependency there before running
`renv::install()`/`renv::snapshot()` for it.

### If `renv::restore()` tries to reach GitHub

r-universe stamps GitHub provenance (`RemoteType`/`RemoteUrl`/`RemoteSha`,
with a full-length SHA) into `reportifyr`/`pyro`'s `DESCRIPTION`, and
`renv::snapshot()` only strips `Remote*` fields when the SHA is
short/absent -- so a naive snapshot carries them into `renv.lock`. `renv`
then treats `RemoteUrl`+`RemoteSha` as license to fall back to a raw `git
clone` of `RemoteUrl` if retrieval from the declared repos doesn't succeed
on the first try, which is what surfaces as `restore()` reaching
`github.com` on a GitHub-blocked network. Fixed by stripping those four
fields from both entries in `renv.lock` (`"Source": "Repository"` is
sufficient on its own) -- re-strip them if you ever regenerate the lockfile
via `renv::snapshot()`, or the fallback comes back.

If `restore()` still recurrently hits curl error 28 (timeout) against
`a2-ai.r-universe.dev`, `.Rprofile` raises R's default 60s download timeout
to 600s before activating `renv`. Persisting past that is a network-path
issue outside quartifyr's control.

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
