# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

quartifyr is a code-first system for generating standardized scientific/
regulated documents (reports today; presentations/analysis plans/memos
meant to follow later) with Quarto. It only does **pass 1** of a two-pass
pipeline: rendering a styled, structurally-complete `.docx` "shell" (title
page, signature pages, ToC, synopsis, numbered appendices, but no real
content, just `{rpfy}:filename.ext` magic-string placeholders). A separate
**pass 2** fill tool (`reportifyr`, an external R/Python package sourced
from [A2-ai's GitHub org](https://github.com/A2-ai), built and served via
`a2-ai.r-universe.dev`) fills those placeholders with real
tables/figures/footnotes.
The two passes are independent: quartifyr doesn't know about
`reportifyr`'s internals beyond emitting the magic strings it expects, and
`reportifyr` doesn't know or care that a shell came from quartifyr rather
than a hand-built template.

quartifyr is a single installable R package at the repo root
(`DESCRIPTION`/`NAMESPACE`/`R/`), modeled on the sibling `../deckifyr`
project's architecture ("one engine, two facades" -- see issue #13):

| Path | What it is | Language |
| --- | --- | --- |
| `R/` | `render_report()` orchestration driver chaining Quarto render → `apply-layout` → `reportifyr::build_report()`, plus thin `pyro`-bridged `styling_*()` wrapper functions | R |
| `inst/extensions/quartifyr/` | Quarto extension: title page, signature pages, synopsis, appendices, page header/footer. Installed into a project via `install_quartifyr_extension()` or `quarto add jprybylski/quartifyr` | Lua (pandoc filters/shortcodes) |
| `inst/python/` (`quartifyr_styling`) | Turns a style YAML into a docx `reference-doc`; abbreviations bridge; `apply-layout` post-processing; headless LibreOffice field recalc. Bundled inside the R package *and* independently pip/uv-installable (`quartifyr-styling` console script, same source tree -- repo-root `pyproject.toml` points at it) | Python |

`examples/demo-report/` is a complete working example exercising every
piece, with an automated end-to-end smoke test; treat it as the
reference implementation to check changes against.

Read the repo-root `README.md` first for the full two-pass architecture
diagram and rationale; component READMEs (`inst/extensions/quartifyr/README.md`,
`inst/python/README.md`, `examples/demo-report/README.md`) have the
mechanical details referenced below.

## Commands

### Python (`inst/python/`, `quartifyr_styling`)

```bash
# Setup (from repo root) -- root pyproject.toml points at inst/python/
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e '.[dev]'

# Tests
python -m pytest tests/python -v
# single test file
python -m pytest tests/python/test_layout.py -v
# or, without an activated venv:
uv run --extra dev pytest tests/python -v

# Build an org's reference-doc (inst/templates/org-reference.docx itself
# is committed to the repo already -- only rebuild after editing
# inst/python/styles/default.yaml; see check_template_freshness.py below)
quartifyr-styling build --style inst/python/styles/default.yaml --out inst/templates/org-reference.docx
# with an org override
quartifyr-styling build --style inst/python/styles/default.yaml --override /path/to/acme-pharma.yaml --out /path/to/acme-pharma-reference.docx

# Other subcommands (see inst/python/README.md) -- each also has an R
# equivalent via the pyro bridge, e.g. quartifyr::styling_apply_layout()
quartifyr-styling abbrevs --footnotes report/standard_footnotes.yaml --out report/shell/abbreviations.tex
quartifyr-styling apply-layout --docx report/shell/report.docx --qmd report.qmd --status draft
quartifyr-styling recalculate-fields --docx path/to/report-final.docx   # experimental, see below
```

### R (root package)

```bash
# Dev: load without installing (not renv-managed -- see ../deckifyr's
# identical convention)
Rscript -e 'devtools::load_all(".")'

# Install for real use (into a report project's own renv library, run
# from that project's directory so it lands in the right place -- see
# "A calling project's R package library" note below). "local::..." only
# for testing an uncommitted local checkout (matches ci.yml/action.yml's
# own usage) -- a real report project should install from GitHub instead:
Rscript -e 'renv::install("jprybylski/quartifyr")'

# As an R function
Rscript -e 'quartifyr::render_report("/path/to/project/report.qmd", status = "draft")'

# examples/*/render.R is a thin CLI wrapper around the same call:
Rscript render.R
Rscript render.R --final
```

### Demo / integration tests (the real correctness checks)

```bash
# Full render_report() path: asserts on actual rendered docx content
python3 examples/demo-report/smoke_test.py

# "Using the pieces directly" path (quarto render + apply-layout +
# reportifyr::build_report() called directly, no quartifyr::render_report()
# orchestration)
python3 scripts/bare_bones_integration_test.py

# Check every physical extension copy (both examples' + the repo-root
# one, see "Quarto extension host" below) hasn't drifted from the
# inst/extensions/quartifyr/ canonical one (Quarto doesn't follow
# symlinks for extensions)
python3 scripts/sync_demo_extension.py --check
python3 scripts/sync_demo_extension.py   # re-sync if it has drifted

# Check the committed inst/templates/org-reference.docx hasn't drifted
# from inst/python/styles/default.yaml
python3 scripts/check_template_freshness.py --check
python3 scripts/check_template_freshness.py   # rebuild if it has drifted

# Quarto-render-only path (no R, no reportifyr, no Python venv) for both
# examples, against the committed reference-doc -- only needs `quarto`
python3 scripts/quarto_only_smoke_test.py

# Proves `quarto add jprybylski/quartifyr` itself works (see "Quarto
# extension host" below) by running it against a zip of the current
# commit instead of GitHub -- only needs `quarto` and `git`
python3 scripts/quarto_add_smoke_test.py

# Unit-style check of synopsis.lua's synopsis-style: options (definition-list/
# inline/table/false) against a small standalone fixture -- needs `quarto`
# and python-docx (the Python venv), but not R/reportifyr
python3 scripts/test_synopsis_styles.py

# Also (tests/testthat/test-wiring.R): proves the R -> pyro -> bundled-
# Python bridge itself works, and runs render_report() end to end against
# examples/demo-report:
Rscript -e 'devtools::load_all("."); testthat::test_dir("tests/testthat")'
```

Both integration tests require the full toolchain on `PATH` (Quarto, R
with `renv`-restored packages, the Python venv) and skip (exit 0) if
`Rscript`/`quarto` aren't available. These are the tests that actually
prove correctness: the `tests/python` pytest suite covers unit-level
Python logic only, and there is no *native* Lua unit test suite (no
busted/similar harness) -- `scripts/test_synopsis_styles.py` is the
closest thing, a Python-driven test that renders a small fixture per
`synopsis-style:` option and asserts on the resulting docx's raw XML
structure, isolating synopsis.lua's own logic from the full pipeline.
Everything else in `inst/extensions/quartifyr/*.lua` is only verified by
running the smoke test.

### CI

`.github/workflows/ci.yml` runs `styling-tests`, `full-pipeline`
(Quarto+R+reportifyr), and `action-smoke-test` (dogfoods `action.yml`),
across all three OSes (the first two jobs; `action-smoke-test` is
Ubuntu-only). The full-pipeline job runs the repo-root Quick Start
commands verbatim, so it also doubles as a check that the README itself
stays accurate. `full-pipeline`'s very first step after the Quarto setup
action is `scripts/quarto_only_smoke_test.py`, deliberately before any
R/uv setup; proof the Quarto-only render path has no R or Python
dependency of its own. The root `quartifyr` R package itself is **not**
renv-managed (see "A calling project's R package library" below); CI
installs it into each example's own renv library via `renv::install
("local::...")` -- pointed at the checked-out working copy rather than
GitHub specifically so a PR's changes get tested before they're merged,
unlike `action.yml`'s own install step (which installs from GitHub, per
its actual released/default-branch state, not this checkout).

## Architecture notes that span files

**Filter/shortcode load order in `_extension.yml` is load-bearing, not
arbitrary.** See the comment block there. `synopsis.lua` must run before
`title_page.lua` (Meta-stage ordering: `title_page.lua` nulls
`meta.title` to suppress pandoc's auto title-block, and `synopsis.lua`
still needs to read it for its own "Title" row). `signature_page.lua` and
`title_page.lua` both prepend content at document position 1, so their
declared order is the *reverse* of final page order.

**`{rpfy}:filename.ext` magic strings are `reportifyr`'s own mechanism,
not a quartifyr invention.** The Lua filters emit them (e.g.
`synopsis.lua`'s `image:` fields); `reportifyr::build_report()` (pass 2,
external) resolves them from `OUTPUTS/figures/`/`OUTPUTS/tables/`. A
plain `quarto render` alone leaves the literal `{rpfy}:...` text visible;
that's expected, not a bug, until pass 2 runs.

**Scoped figure/table numbering (`appendix_fig_caption`/`section_fig_caption`/
`subsection_fig_caption` etc., `appendix.lua`) needs an explicit
`section_break`/`subsection_break` marker rather than resetting
automatically at each native `#`/`##` heading.** Quarto's shortcode
processing and its `filters:` list (where a `Header`-AST-tracking filter
would have to live) are separate passes with no guaranteed relative
ordering against each other, so a `Header` handler can't reliably reset a
counter *before* an earlier caption shortcode in the same document
already used it. `{{< appendix >}}`'s own boundary sidesteps this
naturally -- it emits raw OOXML directly, never a real `#` heading, so
it's already part of the same shortcode pass as the captions it scopes.
`section_break`/`subsection_break` extend that same trick to ordinary
headings: a lightweight marker shortcode placed next to the `#`/`##`
itself, author-placed and unenforced (same trust model as
`appendix_crossref`'s bookmark target already has). Independent of
`number-sections: true` (plain pandoc, numbers heading *text*) for the
same reason -- the two can visibly disagree if a `section_break` is
missed, which is expected, not a bug.

**Quarto extension host: `_extensions/quartifyr/` at the repo root is a
third physical copy, not the canonical one.** `inst/extensions/quartifyr/`
stays the source of truth (what the R package bundles and installs via
`install_quartifyr_extension()`); the repo-root copy exists solely so
`quarto add jprybylski/quartifyr` (issue #16) finds a valid extension the
way it would in any GitHub-hosted extension repo -- `quarto add` scans a
downloaded repo zip for a root-level `_extension.yml` or `_extensions/*/
_extension.yml` and errors ("Found 0 extensions") without one; it doesn't
know or care about `inst/`. Excluded from the R package build via
`.Rbuildignore`'s `^_extensions$`. Kept in sync (alongside both examples'
own copies) by `scripts/sync_demo_extension.py --check`, and validated
end-to-end by `scripts/quarto_add_smoke_test.py`, which runs `quarto add`
against a zip of the current commit rather than waiting for a push to
GitHub to find out it broke.

**pStyle ID vs. display name: easy to get backwards, fails silently in
opposite directions.** Raw OOXML injected by the Lua filters
(`<w:pStyle w:val="...">`) must reference a style's **ID** (`Heading1`,
no space); Word/LibreOffice render the display-name form fine visually
via fallback, but Word's ToC field silently fails to recognize such a
paragraph as a heading. Conversely, pandoc's `custom-style` Div attribute
in `.qmd` bodies matches by **display name** (`Heading 1`, with the
space); get this backwards and pandoc silently fabricates a blank style
with that literal name instead of erroring. See
`inst/extensions/quartifyr/README.md`'s "A pStyle gotcha" section before
touching either.

**`reportifyr`/`pyro` resolve their project by walking up from R's
current working directory** looking for a `.*_init.json` marker;
they ignore path arguments for this. `render_report()` derives the real
project root from `shell_qmd` and wraps every `reportifyr::` call in
`withr::with_dir(project_dir, ...)`. Don't remove that wrapper without
understanding this: calling `reportifyr` functions directly from a
session rooted elsewhere has been observed to silently seed a stray
`pyproject.toml`/`.venv`/`.rpfy-logs/` in the wrong place. This is also
why `examples/demo-report/` carries its own empty `.here` file (pins
`here::here()`'s root so it doesn't walk past the demo into the outer
quartifyr repo).

**`pyro::get_proj_dir()` (`getOption("venv_dir") %||% here::here()`)
caches its result for the life of an R session, independent of
`withr::with_dir()` or `.here` files.** Confirmed directly: calling it
from two different `with_dir()`-scoped directories in the same session
returns the *first*-resolved directory both times -- a stricter version
of the `reportifyr`/`pyro` cwd gotcha above, since here even the correct
marker being present doesn't help. This bit `R/run-python.R`'s
`.run_quartifyr_styling_cli()` (calls `pyro::get_venv_uv_paths()`, which
takes no arguments) and `R/initialize.R`'s
`initialize_quartifyr_project()` (calls `pyro::write_group_to_pyproject()`/
`pyro::initialize_python()`) the hard way: rendering two different
projects in one R session wrote the second project's Python dependency
group into the *first* project's `pyproject.toml`. Fix used: pass
`venv_dir`/`pyproject_dir` explicitly wherever those functions accept
them, and wrap `get_venv_uv_paths()` (which doesn't) in
`withr::local_options(venv_dir = getwd())` immediately before calling
it -- see `R/run-python.R` for the working pattern. Don't assume a bare
`with_dir()` around a `pyro::` call is sufficient; verify against this.

**A calling project's R package library (its `renv`) activates based on
the working directory an `Rscript` process *starts* in, not anything
`withr::with_dir()` changes afterward.** `render_report()`'s own
`with_dir()` wrapper (above) only fixes where `reportifyr` looks for its
project; it can't retroactively make `quartifyr`/`reportifyr`/`pyro`
importable if the R session never activated that project's
`renv/.Rprofile` in the first place. The `quartifyr` R package itself is
**not** renv-managed (no `renv.lock` at the package root -- see
`../deckifyr`'s identical convention), so every report project needs it
installed into *its own* renv library explicitly:
`renv::install("jprybylski/quartifyr")` (or `"local::/path/to/quartifyr"`
when testing an uncommitted checkout, as `ci.yml` does), run with the
project directory as cwd. `examples/demo-report/render.R`'s own
subprocess call and `action.yml`'s composite steps all run with cwd
already set to the *project's* directory for exactly this reason
(`library(quartifyr)` needs the project's own renv-activated library
path). Don't "simplify" one of these call sites to run from the
quartifyr checkout root instead -- it'll fail to find
`reportifyr`/`pyro`, since quartifyr's own (non-renv) library and a
project's `renv.lock`-pinned library are entirely separate (see
`action.yml`'s "renv restore (calling project)" and "Install the
quartifyr R package" steps).

**A calling project's DESCRIPTION must not list `quartifyr` in
`Imports:`, even though it's a real runtime dependency.** Both
`examples/*/DESCRIPTION` used to; confirmed via a real `renv::restore()`
run against a clean library that this makes `restore()` itself try to
resolve/download a package literally named "quartifyr" from the
configured repos (CRAN/r-universe) and fail -- `[quartifyr]: failed to
download`, cascading into every package depending on it -- since,
per the note above, `quartifyr` is deliberately not in `renv.lock` and
only ever installed via the separate `renv::install("local::...")`/
`renv::install("jprybylski/quartifyr")` step that runs right after
`restore()`. `renv::dependencies()` picks it up from `Imports:` (and
separately from `render.R`'s own `library(quartifyr)` call) regardless
of `snapshot.type: "explicit"`, and neither `restore(exclude = ...)` nor
`renv/settings.json`'s `ignored.packages` was confirmed to suppress that
resolution -- removing the `Imports:` entry is what actually fixed it,
confirmed by reproducing the failure and then the fix locally.
`library(quartifyr)` still works fine afterward: DESCRIPTION only drives
`renv`'s own bookkeeping, not which packages are loadable from the
project's already-populated library.

**The `report/shell` → `report/draft`/`report/final` directory
convention is load-bearing for `render_report()`, not just a naming
convention.** `reportifyr::make_doc_dirs()` derives output paths by
substring-replacing "shell" in the *rendered docx's containing
directory*. A project's `_quarto.yml` must set
`project: {output-dir: report/shell}` for this to work. Projects calling
the three pieces directly (`quarto render` / `apply-layout` /
`build_report()`) instead of `render_report()` aren't bound by this.

**Percentage-width tables, not fixed twips**: every table
`inst/extensions/quartifyr/*.lua` generates uses `w:type="pct"` so it
spans the current usable text width, so changing `page.margins_in` in a
style YAML doesn't leave tables overflowing or falling short.

**`apply-layout`'s header/footer/page-restart requires editing docx
package parts directly** (an independent second header/footer
means adding new OOXML *parts*, which a Lua filter's `RawBlock`
injection can't do); that's why it's a separate post-render Python step
(`inst/python/quartifyr_styling/layout.py`, called via
`styling_apply_layout()`) rather than part of the Quarto filter chain.
`header-format:`/`confidentiality:`/`{{< body-start >}}` in a `.qmd` are
all inert without running it.

**Word field recalculation (`styling_recalculate_fields()` /
`quartifyr-styling recalculate-fields`, headless LibreOffice) is
experimental and known-flaky.** Real-world runs against the same
document have produced three different outcomes (hangs, silent no-op, or
success), reproduced both sandboxed and in a plain macOS terminal. Off
by default (`render_report(..., recalculate_fields = FALSE)`). Don't
treat a clean exit as proof it worked; see the repo-root README's
"Status and known limitations" section before changing this code path.

**`inst/templates/org-reference.docx` is committed, not just a build
artifact.** Every other `templates/*.docx` is gitignored ("regenerate
with `styling_build_reference_docx()`"), but this specific file is the
one `render_report()`'s default (`system.file("templates",
"org-reference.docx", package = "quartifyr")`) and this repo's own
docs/CI point at, committed on purpose so the two bundled examples (and
`scripts/quarto_only_smoke_test.py`'s Quarto-only render path) work
straight out of a clone without needing the Python venv set up first.
`quartifyr-styling build`'s docx output isn't byte-reproducible across
runs (zipfile embeds a per-run timestamp in each entry), so `scripts/
check_template_freshness.py` compares unzipped content, not raw bytes;
run with `--check` (as both examples' `smoke_test.py` already do) to
catch drift from `inst/python/styles/default.yaml`, same pattern as
`scripts/sync_demo_extension.py` for the Lua extension copies.

**YAML lists, not maps, for `synopsis:`/`title-page-extra:`/`address:`.**
Deliberate: pandoc's Lua metadata tables don't preserve map key order
(confirmed by testing), so these are lists specifically to keep row/line
order reliable across renders. Don't "simplify" one of these into a
plain map.

## Working across the two-pass boundary

Most non-trivial changes touch either pass 1 (this repo) or pass 2
(`reportifyr`, external) but rarely need to know about the other's
internals beyond the `{rpfy}:` magic-string contract and the
`document-status`/draft-final distinction (`reportifyr` tracks this via
its own `report/draft/`/`report/final/` directories and
`finalize_document()`; quartifyr's `document-status` frontmatter is set
independently at render time and the orchestration driver, not any
automatic sync, is what keeps the two aligned; see
`inst/extensions/quartifyr/README.md`'s "Title page" section).

When changing `inst/extensions/quartifyr/*.lua`, verify against the demo
(`python3 examples/demo-report/smoke_test.py`) and re-sync the demo's
physical extension copy (`python3 scripts/sync_demo_extension.py`);
there's no Lua unit test suite, so the smoke test is the only real
correctness signal for filter changes.
