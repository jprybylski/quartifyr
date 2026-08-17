# quartifyr

# quartifyr (development version)

## Fixed

* `check_quarto_extensions()` (called by `render_report()` before every
  render) now catches failures from `quarto::quarto_list_extensions()`
  and re-raises them with an explanation, instead of letting Quarto's own
  raw internal error propagate uninterpreted. `quarto list extensions`
  resolves a project's entire markdown as a side effect of listing
  extensions -- not just its own output -- so a missing file referenced
  by any `.qmd` in the project (e.g. a `{{< include >}}` pointing at a
  file that wasn't copied over) could previously surface here as a
  deeply nested, extensions-unrelated-looking error.

# quartifyr 0.2.2

## Fixed

* `initialize_quartifyr_project()` no longer fails with uv's "Empty field
  is not allowed for PEP508" on a project where it's the first `pyro`-
  based initializer to run (i.e. before
  `reportifyr::initialize_report_project()`). The failure came from an
  upstream `pyro` quirk: seeding a brand-new `pyproject.toml` for an
  unrecognized dependency-group name (`"quartifyr"` isn't one of `pyro`'s
  own bundled groups) rendered that group with a single spurious
  empty-string dependency. `initialize_quartifyr_project()` now seeds a
  minimal `pyproject.toml` itself first, so `pyro` never has to.

# quartifyr 0.2.1

## Added

* `check_quarto_extensions()`, checking a project's installed Quarto
  extensions (via `quarto::quarto_list_extensions()`) against a new
  formal registry, `quartifyr_quarto_extensions` -- currently just
  `A2-ai/quarto-plus`, but a one-line addition away from covering any
  future required/suggested extension. Reports anything missing with a
  clickable `quarto::quarto_add_extension()` suggestion.
  `render_report()` now calls this itself before rendering (erroring on
  a missing *required* extension, with a specific actionable message,
  instead of Quarto's own much less specific "could not find executable"
  filter failure); `install_quartifyr_extension()` calls it too, as a
  non-fatal warning-only nudge.

# quartifyr 0.2.0

## Changed

* **Restructured the repo from three independent components
  (`_extensions/quartifyr/`, `styling/`, `r/`) into a single installable
  R package (`quartifyr`) at the repo root**, modeled on the sibling
  `deckifyr` project's architecture (issue #13):
  * `styling/` moved to `inst/python/` and is now called from R via a
    `pyro` bridge (`R/run-python.R`, `styling_build_reference_docx()`/
    `styling_apply_layout()`/etc.) instead of shelling out to a
    separately-managed CLI binary path; it's still independently
    pip/uv-installable as `quartifyr-styling` from the same source tree
    (repo-root `pyproject.toml`).
  * `_extensions/quartifyr/` moved to `inst/extensions/quartifyr/`,
    installable via the new `install_quartifyr_extension()` or still via
    `quarto add jprybylski/quartifyr`.
  * `r/`'s `render_report()` is now `quartifyr::render_report()`, a real
    exported function rather than a `source()`d script; the `toolkit_root`/
    `venv_bin` parameters are gone (the package resolves its own bundled
    assets via `system.file()`). `r/render.R`'s CLI wrapper is gone;
    `examples/*/render.R` now `library(quartifyr)` instead of `source()`-ing
    a sibling file.
  * New: `initialize_quartifyr_project()`, provisioning a report project's
    `quartifyr` pyro dependency group (call once per project, alongside
    `reportifyr::initialize_report_project()`).
  * The `quartifyr` R package itself is not `renv`-managed (no
    `renv.lock` at the package root); install it into a report project's
    own renv library with `renv::install("jprybylski/quartifyr")`.
  * `templates/org-reference.docx` moved to `inst/templates/`.
* Docs site moved from a hand-authored Jekyll site (`docs/` as source) to
  [pkgdown](https://pkgdown.r-lib.org/): narrative pages are now
  `vignettes/articles/*.Rmd`, function reference is generated from
  roxygen comments, and `docs/` itself is pure build output (no longer
  committed). Terminal-recording GIFs/screenshots moved from
  `docs/assets/img/` to `man/figures/`; VHS recipes moved from
  `docs/assets/tapes/` to `dev/tapes/`.
* Release automation ported from `deckifyr`'s sibling project
  `xpose.xtras`: a `VERSION` file at the repo root drives
  `.github/workflows/release.yaml`, which syncs `DESCRIPTION`'s
  `Version` and this file's own heading structure, tags, and publishes a
  GitHub release on push to `main` (`.github/scripts/
  sync-release-metadata.R`). Never touches CRAN. `CHANGELOG.md` (Keep a
  Changelog format) is retired in favor of this file, the format the
  release automation and pkgdown's News page both expect natively.
* `DESCRIPTION` gained `Depends: R (>= 4.1.0)`, matching `reportifyr`/
  `pyro`'s own floor (both already require it) -- not an arbitrary
  style constraint, so native pipes (`|>`) and lambda shorthand
  (`\(...)`) are fine to use in this package's own R code.

## Added

* `action.yml`: a reusable composite GitHub Action wrapping
  `render_report()`, so another repo can render its report (and upload
  the result as a workflow artifact) without hand-rolling the Quarto/R/
  `reportifyr` setup steps itself. See
  [the GitHub Action article](https://jprybylski.github.io/quartifyr/articles/github-action.html)
  (issue #9). Its `reference-doc` input lets an external caller point a
  render at an org's own reference-doc instead of quartifyr's bundled
  default.

# quartifyr 0.1.0

## Changed

* `r/` and both bundled examples (`examples/demo-report/`,
  `examples/memo-example/`) now manage their R package library with
  [`renv`](https://rstudio.github.io/renv/) instead of `rv`. Each
  project's dependencies are declared explicitly in a `DESCRIPTION`
  file's `Imports:`/`Remotes:` fields (`renv`'s `snapshot.type: explicit`
  mode) rather than `rproject.toml`; `renv.lock` replaces `rv.lock`.
  Set up a project's R environment with:
  ```bash
  Rscript -e 'renv::restore()'
  ```
* CI's `full-pipeline` job now runs on Windows as well as Linux/macOS.
  `rv` required an exact R-version match across every `rproject.toml` it
  encountered while walking up from a build subprocess's working
  directory (including `pyro`'s and `reportifyr`'s own bundled files),
  which put it in "safe mode" on Windows; `renv` only warns on a
  version mismatch, so this class of failure no longer exists.
* `render_report()`'s `venv_bin` parameter now defaults to the
  `styling/` venv's `Scripts/` directory on Windows (`bin/` elsewhere),
  and looks for `quartifyr-styling.exe` there -- the layout `uv venv`/
  `python -m venv` actually produce on Windows. `scripts/
  check_template_freshness.py` and `scripts/bare_bones_integration_test.py`
  got the same fix for the venv paths they compute directly.
