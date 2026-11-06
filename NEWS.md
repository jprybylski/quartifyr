# quartifyr

# quartifyr (development version)

## New features

* `render_report(soffice_bin = )` / `render.R --soffice-bin <path>` name the
  LibreOffice executable for `--recalculate-fields` and
  `--resolve-same-page-crossrefs`, falling back to `QUARTIFYR_SOFFICE_BIN`
  and then `soffice` on `PATH` (the same order as `quarto_bin`). The styling
  CLI's two LibreOffice subcommands and `styling_recalculate_fields()` /
  `styling_resolve_same_page_crossrefs()` take it too. A missing or
  non-executable path fails before the render starts, and the result's
  `versions$libreoffice` records the resolved path and `soffice --version`
  of the one that ran (#83).

## Bug fixes

* A failed, rejected or interrupted render no longer leaves a
  complete-looking docx in `report/draft` or `report/final`. A render now
  works in `report/.staging-<id>/` (Quarto is pointed at it with
  `--output-dir`) and is only moved into `report/{shell,draft,final}` once it
  has finished and been accepted, so a `strict = TRUE` rejection, a pass-2
  failure partway through (reportifyr's `-clean`/`-tabs`/`-draft` files) or a
  killed R process never reaches the live folders. What a failed or rejected
  render produced is kept in `report/.failed/` with a `FAILED` file giving the
  reason (the next failure replaces it); a killed render's staging folder is
  deleted by the next render. `report/.previous/` now only ever receives
  delivered outputs, so a failure followed by another render no longer pushes
  the last good outputs out of it, and moving the previous outputs there is
  all or nothing instead of stopping half way. reportifyr's
  `<final>_docx_metadata.json` is repointed from the staging folder to
  `report/final/` (#81).
* `--recalculate-fields` and `--resolve-same-page-crossrefs` no longer hang
  on macOS with LibreOffice 26.2 (every run timed out). A fresh profile
  that already holds the seeded macro when LibreOffice first starts never
  runs it, so the profile is now initialised first (`--terminate_after_init`)
  and the macro added afterwards; a run then takes about two seconds (100 of
  100 sequential and concurrent runs on macOS 26.6 / LibreOffice 26.2.5.2).
  The macro also writes a heartbeat file as its first action, and a
  LibreOffice that doesn't start it within 30 seconds is abandoned and
  reported as unavailable instead of waiting out the full timeout. Not
  re-tested on Windows or Linux (#84).
* The two headless-LibreOffice steps (`--recalculate-fields`,
  `--resolve-same-page-crossrefs`) now work on Windows and with profile
  paths that contain a space. The `-env:UserInstallation` profile URL was
  built as `file://<path>`, which is malformed on Windows and breaks on a
  space; it is now a proper `file:///` URI. A timeout now kills the whole
  LibreOffice process tree on Windows too (`taskkill /T /F` plus a sweep by
  profile path; the POSIX-only process-group kill raised there), and a
  `soffice` that still holds its temporary profile no longer turns a
  timeout into a `PermissionError`. Both steps share one launcher
  (`quartifyr_styling/_soffice.py`) (#86).

# quartifyr 0.3.2

## New features

* `render_report()` gains `quarto_timeout` (default 600 seconds, `Inf`
  disables) and `quarto_bin`. A hung Quarto render is now killed along
  with its whole process tree (Deno/Pandoc/knitr children) and signals an
  error of class `quartifyr_quarto_timeout` that includes the tail of
  Quarto's stderr. `quarto_bin` (or the `QUARTO_PATH` environment variable)
  selects the Quarto executable instead of relying on `PATH` (#71).
* New `check_report_project()` is a render-free preflight (it never invokes
  Quarto). It returns a data frame of findings (`check`, `severity`,
  `path`, `message`) covering the project preconditions `render_report()`
  enforces, the required Quarto extensions, every `{rpfy}:` placeholder's
  artifact and metadata sidecar, the abbreviation keys and `meta_type`
  those sidecars reference in `standard_footnotes.yaml`, and placeholders
  that end their section. `render_report()` now shares the precondition
  checks with it, with unchanged error messages (#70).
* `render_report()` now returns a structured `quartifyr_render_result`
  (still containing `shell`/`draft`/`final`): `status` (`"ok"`,
  `"warning"` or `"error"`), `artifacts` with SHA-256 hashes,
  `unfilled_placeholders` (scanned from the produced docx),
  `missing_metadata`, `warnings`, `errors` and `log_dir`. New
  `strict = TRUE` signals an error of class `quartifyr_render_incomplete`
  instead of returning an incomplete result; the default stays `FALSE`. A
  failed LibreOffice step still only warns, but is now recorded in the
  result. When `build_report()` fails because a metadata sidecar is
  missing, the error (class `quartifyr_pass2_failed`) now names it (#69).
* New `inst/scripts/render.R` entry point for CI and background jobs:
  `--project <dir> --shell report.qmd --status draft --json [--strict]`
  prints the result as JSON on stdout (shape in
  `inst/schemas/render-result.schema.json`), sends everything else to
  stderr, and exits non-zero on any error or, with `--strict`, any non-ok
  status. The GitHub Action gains a `strict` input and a `status` output
  (#69).
* New `install_quarto_extensions()` installs the required third-party Quarto
  extension (`A2-ai/quarto-plus`) without network access, from a copy now
  bundled in the package or from a directory or `.zip`/`.tar.gz` archive of
  your choosing. The bundled copy is unmodified upstream (MIT-licensed, with
  its `LICENSE` kept alongside; provenance in `inst/extensions/README.md`)
  and is drift-checked against the examples' copies by
  `scripts/sync_demo_extension.py`. `check_quarto_extensions()` now points
  at it (#72).
* Offline and pre-provisioned setup (#72). `initialize_quartifyr_project()`
  gains `python_env` (an existing environment with `python-docx` and
  `pyyaml`: verified by name, then pyro and uv are skipped entirely, and
  `render_report()`'s Python steps run in it via
  `options(quartifyr.python_env = ...)`), `install_extensions` and
  `extensions_from`. With `options(quartifyr.offline = TRUE)` or
  `UV_OFFLINE=1`, pyro's provisioning runs offline, stops up front if `uv`
  isn't installed instead of letting pyro download and install it into
  `~/.local/bin`, and refuses `from_repo`. Every network-dependent failure
  names the step, the resource and how to provide it locally (error class
  `quartifyr_offline_failure`), including uv's own stderr, which pyro
  otherwise hides.

* `initialize_quartifyr_project()` can now scaffold a new project's
  `_quarto.yml`/style YAML/shell `.qmd` from a template source instead of
  leaving the directory empty (issue #23): `from_dir`/`from_repo` (with
  `ref`/`subdir`/`type`/`force`) pull from a local directory or a git repo
  (`"[host/]owner/repo[/subdir][@ref]"` shorthand, or a full URL),
  mirroring `../deckifyr`'s identical `initialize_deck_project()` template
  mechanism (issue #34 there). New `quartifyr-styling init` CLI
  subcommand backs this.
* New `quartifyr-styling skills [DIRECTORY]` / `styling_export_skills()`
  (issue #57): exports two bundled Claude Skills-format `SKILL.md` files
  (`quartifyr-style-config`, `quartifyr-shell-authoring`) to a directory of
  your choice, for use with Claude Code or any other coding agent that
  reads `SKILL.md` files.

## Documentation

* Removed the awkward "(All)" wording from the demo report's combined List
  of Figures/List of Tables headings and docs-site screenshots/alt text,
  and added a `section_fig_caption`/`subsection_fig_caption` code sample
  to the "Scoped figure/table numbering" article section (issue #59).
* Removed stray GitHub issue-number references from roxygen documentation
  (issue #60).
* Added `@examples` to every exported R function/data object that was
  missing one (issue #61).

## Bug fixes

* Excluded `LICENSE` and the large `man/figures/` demo GIFs/downloadable
  `.docx` files (pkgdown-site-only assets, not needed by the installed
  package) from the built package tarball, fixing an "unmentioned
  DESCRIPTION" `R CMD check` NOTE and shrinking the tarball from ~4.8MB to
  ~2.2MB (issue #62).
* `render_report()` is offline-safe by itself (#76). New `offline` argument
  (and `--offline` on `render.R`), defaulting to offline mode as set by
  `options(quartifyr.offline = TRUE)` or `UV_OFFLINE`: for the whole render it
  sets `UV_OFFLINE`, `UV_NO_INDEX`, `UV_PYTHON_DOWNLOADS=never` and
  `UV_NO_SYNC`, so quartifyr's styling step and every `uv run` in reportifyr's
  pass 2 use the already-provisioned environment instead of re-syncing (and
  recreating) `.venv`, even with a cold uv cache. A uv failure at render time
  is now a `quartifyr_offline_failure` naming the step. The offline article
  lists the variables and the exact conditions under which a render makes no
  network calls, and says concurrent renders of one project are not
  supported.
* The render result is versioned and carries provenance (#78). Every JSON
  result, including the error object of a failed render, has
  `schema_version: 1`, and the schema is now
  `inst/schemas/render-result-v1.schema.json` (renamed from
  `render-result.schema.json`; new optional fields keep the version, removing
  or renaming one bumps it). Results gain `inputs` (path, SHA-256 and size of
  the shell `.qmd`, each figure, table and metadata sidecar used,
  `standard_footnotes.yaml`, `config.yaml` and the reference-doc), `versions`
  (quartifyr, reportifyr, Quarto, `quartifyr_styling`, R) and
  `started_at`/`finished_at`.
* New `inst/scripts/check.R --project <dir> --shell report.qmd [--json]` runs
  `check_report_project()` for scripts and launchers: JSON with
  `schema_version` and `findings`, exit status 0 without error findings, 1
  with, 2 on bad usage (#78).
* A strict render that is incomplete now always reports `status: "error"`,
  also when the render itself only warned. `--help` and the docs say that
  exit status 0 without `--strict` only means the render finished (#78).
* `render_report()` resolves a relative `shell_qmd` and the default
  `standard_footnotes_yaml`, `config_yaml`, `figures_path` and `tables_path`
  against the calling directory before changing into the project, so a
  relative `--shell` works from outside the project (#78).
* The docs now state which steps `quarto_timeout` does not bound, and why the
  timeout cleanup test does not run on Windows (#78).
* A failed, timed-out or interrupted `render_report()` no longer leaves the
  previous render's `report/draft` and `report/final` documents in place
  looking complete. Once the render starts, the outputs it will regenerate
  are first moved to `report/.previous/`, and an output only counts as
  produced if it was written after the render began (#77).
* The release workflow no longer rewrites a published release: a refresh
  (moving the tag, replacing the tarball) only happens while the release is
  under 24 hours old, and is skipped with a warning after that, so a
  version number keeps naming one source tree and one tarball. Each release now also carries a `SHA256SUMS` file. This
  release is 0.3.2 because 0.3.1's tag and tarball had been replaced with
  the job-contract and offline work (#75).

# quartifyr 0.3.1

## New features

* New `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables` divs build
  a combined List of Figures/List of Tables spanning both `quarto-plus`'s
  own continuous `fig_caption`/`tbl_caption` and all six of this
  extension's scoped caption shortcodes (`appendix_fig_caption`/
  `appendix_tbl_caption`, `section_fig_caption`/`section_tbl_caption`,
  `subsection_fig_caption`/`subsection_tbl_caption`), in true document
  order -- unlike `quarto-plus`'s own `.list_of_figures`/
  `.list_of_tables` (which stay as-is, continuous-only, and keep working
  unchanged), a native Word `TOC` field switch can't merge multiple `SEQ`
  families into one document-ordered list. A hand-built list, with live
  `REF`/`PAGEREF` fields per entry, built by a new post-render step in
  `quartifyr_styling.layout.apply_layout()` rather than a Lua filter --
  see `inst/extensions/quartifyr/README.md`'s "Combined List of
  Figures/Tables" section for why (#54).
* The reference-doc template now also configures a "Table of Figures"
  style (Word's built-in style for `quarto-plus`'s own
  `.list_of_figures`/`.list_of_tables`, previously left unstyled/
  Word-default) to match "TOC 1" -- the style `.quartifyr_list_of_figures`/
  `.quartifyr_list_of_tables` entries above use -- so both kinds of list
  render identically once recalculated (#54).

# quartifyr 0.3.0

## New features

* New `validate_header()` checks a shell `.qmd`'s front matter (and its
  project's `_quarto.yml`) against every field this extension's Lua
  filters and `apply-layout` step actually read, and prints a
  cli-formatted report: what's provided, what's missing (required or
  merely recommended), what else is available and what it does, and any
  conflicts (`title:`/`memo:` both set, an unresolvable
  `header-format:` placeholder, an unrecognized `crossref-hyperlinks:`
  value, a `logo:`/`bibliography:` path that doesn't exist, ...). New
  `header_helper()` interactively builds a front-matter block from the
  same field catalog and copies (or prints) the result, ready to paste
  into a new `.qmd`. Both are driven by one shared field registry, so a
  field added to the extension only needs documenting in one place (#31).
* New `styling_example_template()`/`styling_example_style()` pull the
  bundled reference-doc/default style YAML into a project (the latter
  also returning its parsed content as a list, ready to edit), and new
  `styling_save_overrides()`/`styling_update_style()` save an edited
  style back out -- by default as just its diff from the base style
  YAML, an override ready to deep-merge back on at load time -- or
  deep-merge a targeted change onto an existing style YAML in place.
  Each also available as a `quartifyr-styling` CLI subcommand (#27).
* `{{< appendix >}}`'s designator style is now configurable document-wide
  via `appendix-numbering:` frontmatter (`alphabetic` (default) / `arabic`
  / `roman`), instead of always lettering A/B/C (#26).
* New scoped figure/table caption shortcodes --
  `appendix_fig_caption`/`appendix_tbl_caption`,
  `section_fig_caption`/`section_tbl_caption` (with a new `section_break`
  marker), and `subsection_fig_caption`/`subsection_tbl_caption` (with a
  new `subsection_break` marker) -- number "Figure A.1"/"Figure 3.1"/
  "Figure 3.2.1" respectively, restarting within their scope instead of
  running continuously through the whole document like `quarto-plus`'s
  own `fig_caption`/`tbl_caption`. Used after an `{{< appendix >}}` call,
  `section_fig_caption`/`subsection_fig_caption` nest that appendix's own
  designator into their number too ("Figure C.3.1"), so a figure numbered
  mid-appendix never reads as though it belongs to the main body's own
  third section. A new `scoped_crossref` shortcode resolves any of the
  six. Additive: nothing here changes `quarto-plus`'s own shortcodes, and
  an author can mix scoped and continuous captions freely -- though a
  plain (non-appendix) scoped number has no relationship to `quarto-plus`'s
  own continuous numbering even when digits happen to match, so the first
  use of plain `section_fig_caption`/`subsection_fig_caption` in a
  document logs a one-time reminder about picking one convention per
  figure/table type. See `inst/extensions/quartifyr/README.md`'s "Scoped
  figure/table numbering" section (#26).
* Style YAML: new `code:` section (`font_size`, `background_color`,
  `padding_pt`) styles pandoc's `Source Code`/`Verbatim Char` docx styles
  for fenced code blocks/inline code, using `fonts.monospace` (previously
  declared but never actually applied anywhere -- now wired up).
  `background_color` also applies to every per-token syntax-highlight
  character style pandoc's docx writer can emit inside a fenced code
  block (`KeywordTok`, `StringTok`, `CommentTok`, ...), so a keyword or
  string shares the same background as the block around it instead of
  keeping pandoc's own hardcoded shading regardless of this setting.
  Defaults match pandoc's own previous built-in fallback, so existing
  renders are unaffected unless a style YAML opts into non-default
  values (#29).
* Style YAML: new `equation.font` sets the docx-wide default math font
  (applied by `styling_apply_layout()`/`render_report()`'s new `style`/
  `override` arguments post-render, since pandoc's docx writer doesn't
  carry this setting through from the reference-doc template). Font
  family only -- an unstyled math run inherits its size from the
  surrounding paragraph (#29).
* Style YAML: new `heading.all_caps` applies an all-caps *visual*
  transform (OOXML `w:caps`) to `Heading 1`-`6`, leaving the underlying
  heading text untouched (#29).
* New `styling_sync_reportifyr_config()` (`quartifyr-styling
  sync-reportifyr-config`) updates reportifyr's own `report/config.yaml`
  `footnotes_font`/`footnotes_font_size` to match a style YAML's
  `fonts.body`/`fonts.sizes.footnote` -- previously only kept in sync by
  hand, per both bundled examples' own `config.yaml` comments. Requires
  an interactive confirmation unless `yes = TRUE` is passed; not run
  automatically by `render_report()` (#29).
* New `inst/python/styles/schema.json` -- a machine-readable JSON Schema
  for the style YAML, for editor autocomplete/inline validation
  (`default.yaml` now carries a `# yaml-language-server: $schema=...`
  header pointing at it). Guarded against drifting from `schema.py` by
  `tests/python/test_schema_json.py` (#28).

## Documentation

* The [Styling](https://jprybylski.github.io/quartifyr/articles/styling.html)
  article gained a full style YAML reference table (every key, what it
  controls, its default) and a real rendered default-vs-branded
  comparison, generated by the new
  `scripts/render_style_option_gallery.py` from `examples/demo-report`'s
  actual content -- not a mockup.

## Fixed

* `render_report()`'s `reference_doc` argument now defaults to `NULL`
  instead of the bundled package template. When unset, it checks (via
  `quarto::quarto_inspect()`, so it follows Quarto's own
  frontmatter-over-`_quarto.yml` merge precedence) whether the project
  already configures a docx `reference-doc` and, if so, leaves it alone
  instead of silently overriding it with the package default as before.
  Only when neither sets one does it fall back to the package default,
  now with a `cli` notice pointing at `styling_build_reference_docx()`
  (#30).

## Breaking changes

* Removed the style YAML's `identity.org_name`/`identity.logo_path` keys
  -- confirmed dead: nothing read them (the actual title-page logo comes
  from the `.qmd`'s own `logo:` frontmatter). Delete them from any style
  YAML that set them; they're a no-op removal otherwise (#28).

# quartifyr 0.2.4

## Fixed

* `initialize_quartifyr_project()` now catches failures from
  `pyro::initialize_python()` and re-raises them with an explanation,
  instead of letting pyro/uv's raw internal error propagate
  uninterpreted (#46). On a project already initialized by reportifyr
  *before* it depended on pyro (reportifyr < 0.4.0), that project's
  Python environment predates pyro/uv and isn't necessarily something
  `uv sync` can adopt as-is -- the error now points at re-running
  `reportifyr::initialize_report_project()` first to bring the
  environment up to a pyro-compatible state.

# quartifyr 0.2.3

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

* Appendices past the first now show their correct letter in the ToC.
  `{{< appendix >}}`'s native Word `SEQ Appendix \* ALPHABETIC` field
  always cached its placeholder result as "A", so a document's ToC
  (positioned earlier than the appendices, and built from each heading's
  already-resolved text during a single field-update pass) could pick up
  that stale "A" for appendix B, C, ... even though the heading itself
  recalculated correctly. Each appendix's cached placeholder is now
  pre-computed to its actual letter, so the ToC and the heading agree
  even before any field recalculation happens.

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
