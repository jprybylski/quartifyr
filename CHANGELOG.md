# Changelog

All notable changes to quartifyr are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
quartifyr's components (`_extensions/quartifyr/`, `styling/`, `r/`) are
versioned together at the repo level; component-level version numbers
(e.g. `_extensions/quartifyr/_extension.yml`, `styling/pyproject.toml`)
track this same number.

## [Unreleased]

### Added

- `action.yml`: a reusable composite GitHub Action wrapping
  `render_report()`, so another repo can render its report (and upload
  the result as a workflow artifact) without hand-rolling the Quarto/R/
  `reportifyr` setup steps itself. See [docs/github-action.md](docs/github-action.md)
  (issue #9).
- `r/render.R` gained a `--reference-doc PATH` flag (previously only
  settable by calling `render_report()` directly from R), so the action
  -- and any other external caller -- can point a render at an org's own
  reference-doc instead of quartifyr's bundled default.

## [0.1.0] - 2026-08-13

### Changed

- `r/` and both bundled examples (`examples/demo-report/`,
  `examples/memo-example/`) now manage their R package library with
  [`renv`](https://rstudio.github.io/renv/) instead of `rv`. Each
  project's dependencies are declared explicitly in a `DESCRIPTION`
  file's `Imports:`/`Remotes:` fields (`renv`'s `snapshot.type: explicit`
  mode) rather than `rproject.toml`; `renv.lock` replaces `rv.lock`.
  Set up a project's R environment with:
  ```bash
  Rscript -e 'renv::restore()'
  ```
- CI's `full-pipeline` job now runs on Windows as well as Linux/macOS.
  `rv` required an exact R-version match across every `rproject.toml` it
  encountered while walking up from a build subprocess's working
  directory (including `pyro`'s and `reportifyr`'s own bundled files),
  which put it in "safe mode" on Windows; `renv` only warns on a
  version mismatch, so this class of failure no longer exists.
- `render_report()`'s `venv_bin` parameter now defaults to the
  `styling/` venv's `Scripts/` directory on Windows (`bin/` elsewhere),
  and looks for `quartifyr-styling.exe` there -- the layout `uv venv`/
  `python -m venv` actually produce on Windows. `scripts/
  check_template_freshness.py` and `scripts/bare_bones_integration_test.py`
  got the same fix for the venv paths they compute directly.

[0.1.0]: https://github.com/jprybylski/quartifyr/releases/tag/v0.1.0
