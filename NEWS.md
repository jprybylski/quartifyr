# quartifyr

# quartifyr (development version)

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
