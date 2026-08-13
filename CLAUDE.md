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

Three components, each independently usable:

| Path | What it is | Language |
| --- | --- | --- |
| `_extensions/quartifyr/` | Quarto extension: title page, signature pages, synopsis, appendices, page header/footer | Lua (pandoc filters/shortcodes) |
| `styling/` | Turns a style YAML into a docx `reference-doc`; abbreviations bridge; `apply-layout` post-processing; headless LibreOffice field recalc | Python (`quartifyr-styling` package) |
| `r/` | `render_report()` orchestration driver chaining Quarto render → `apply-layout` → `reportifyr::build_report()` | R (`renv`-managed) |

`examples/demo-report/` is a complete working example exercising every
piece, with an automated end-to-end smoke test; treat it as the
reference implementation to check changes against.

Read the repo-root `README.md` first for the full two-pass architecture
diagram and rationale; component READMEs (`_extensions/quartifyr/README.md`,
`styling/README.md`, `r/README.md`, `examples/demo-report/README.md`) have
the mechanical details referenced below.

## Commands

### Python (`styling/`)

```bash
# Setup (from repo root)
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e "./styling[dev]"

# Tests
cd styling && python -m pytest tests/ -v
# single test file
cd styling && python -m pytest tests/test_layout.py -v
# or, without an activated venv:
cd styling && uv run --extra dev pytest tests -v

# Build an org's reference-doc (templates/org-reference.docx itself is
# committed to the repo already -- only rebuild after editing
# styling/styles/default.yaml; see check_template_freshness.py below)
quartifyr-styling build --style styling/styles/default.yaml --out templates/org-reference.docx
# with an org override
quartifyr-styling build --style styling/styles/default.yaml --override styling/styles/acme-pharma.yaml --out templates/acme-pharma-reference.docx

# Other subcommands (see styling/README.md)
quartifyr-styling abbrevs --footnotes report/standard_footnotes.yaml --out report/shell/abbreviations.tex
quartifyr-styling apply-layout --docx report/shell/report.docx --qmd report.qmd --status draft
quartifyr-styling recalculate-fields --docx path/to/report-final.docx   # experimental, see below
```

### R (`r/`)

```bash
cd r && Rscript -e 'renv::restore()'   # requires renv: https://rstudio.github.io/renv/

# As a CLI
Rscript render.R /path/to/project/report.qmd
Rscript render.R /path/to/project/report.qmd --final
```

### Demo / integration tests (the real correctness checks)

```bash
# Full render_report() path: asserts on actual rendered docx content
python3 examples/demo-report/smoke_test.py

# "Using the pieces directly" path (quarto render + apply-layout +
# reportifyr::build_report() called directly, no r/ orchestration)
python3 scripts/bare_bones_integration_test.py

# Check the demo's physical extension copy hasn't drifted from the
# repo-root canonical one (Quarto doesn't follow symlinks for extensions)
python3 scripts/sync_demo_extension.py --check
python3 scripts/sync_demo_extension.py   # re-sync if it has drifted

# Check the committed templates/org-reference.docx hasn't drifted from
# styling/styles/default.yaml
python3 scripts/check_template_freshness.py --check
python3 scripts/check_template_freshness.py   # rebuild if it has drifted

# Quarto-render-only path (no R, no reportifyr, no styling venv) for both
# examples, against the committed reference-doc -- only needs `quarto`
python3 scripts/quarto_only_smoke_test.py

# Unit-style check of synopsis.lua's synopsis-style: options (definition-list/
# inline/table/false) against a small standalone fixture -- needs `quarto`
# and python-docx (the styling/ venv), but not R/reportifyr
python3 scripts/test_synopsis_styles.py
```

Both integration tests require the full toolchain on `PATH` (Quarto, R
with `renv`-restored packages, the `styling/` venv) and skip (exit 0) if
`Rscript`/`quarto` aren't available. These are the tests that actually
prove correctness: the `styling/` pytest suite covers unit-level Python
logic only, and there is no *native* Lua unit test suite (no busted/
similar harness) -- `scripts/test_synopsis_styles.py` is the closest
thing, a Python-driven test that renders a small fixture per
`synopsis-style:` option and asserts on the resulting docx's raw XML
structure, isolating synopsis.lua's own logic from the full pipeline.
Everything else in `_extensions/quartifyr/*.lua` is only verified by
running the smoke test.

### CI

`.github/workflows/ci.yml` runs `styling-tests` and `full-pipeline`
(Quarto+R+reportifyr), both across all three OSes. The full-pipeline job
runs the repo-root Quick Start commands verbatim, so it also doubles as a
check that the README itself stays accurate. `full-pipeline`'s very first
step after the Quarto setup action is `scripts/quarto_only_smoke_test.py`,
deliberately before any R/uv setup; proof the Quarto-only render path
has no R or Python dependency of its own.

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

**pStyle ID vs. display name: easy to get backwards, fails silently in
opposite directions.** Raw OOXML injected by the Lua filters
(`<w:pStyle w:val="...">`) must reference a style's **ID** (`Heading1`,
no space); Word/LibreOffice render the display-name form fine visually
via fallback, but Word's ToC field silently fails to recognize such a
paragraph as a heading. Conversely, pandoc's `custom-style` Div attribute
in `.qmd` bodies matches by **display name** (`Heading 1`, with the
space); get this backwards and pandoc silently fabricates a blank style
with that literal name instead of erroring. See
`_extensions/quartifyr/README.md`'s "A pStyle gotcha" section before
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

**A calling project's R package library (its `renv`) activates based on
the working directory an `Rscript` process *starts* in, not anything
`withr::with_dir()` changes afterward.** `render_report()`'s own
`with_dir()` wrapper (above) only fixes where `reportifyr` looks for its
project; it can't retroactively make `reportifyr`/`pyro` importable if
the R session never activated that project's `renv/.Rprofile` in the
first place. Every caller of `r/render.R` -- `examples/demo-report/
render.R`'s own subprocess call, and `action.yml`'s composite steps --
invokes it with the shell's cwd already set to the *project's* directory
(not `r/` or the toolkit root) for exactly this reason, passing
`--toolkit-root` separately so `render.R` still finds `templates/`/
`_extensions/`/the `styling/` venv. Don't "simplify" one of these call
sites to run from the toolkit root instead -- it'll fail with
`reportifyr`/`pyro` not found, since the toolkit's own `r/renv.lock` and
a project's `renv.lock` are two independent lockfiles (see `action.yml`'s
"renv restore (calling project)" step).

**The `report/shell` → `report/draft`/`report/final` directory
convention is load-bearing for `render_report()`, not just a naming
convention.** `reportifyr::make_doc_dirs()` derives output paths by
substring-replacing "shell" in the *rendered docx's containing
directory*. A project's `_quarto.yml` must set
`project: {output-dir: report/shell}` for this to work. Projects calling
the three pieces directly (`quarto render` / `apply-layout` /
`build_report()`) instead of `render_report()` aren't bound by this.

**Percentage-width tables, not fixed twips**: every table
`_extensions/quartifyr/*.lua` generates uses `w:type="pct"` so it spans
the current usable text width, so changing `page.margins_in` in a style
YAML doesn't leave tables overflowing or falling short.

**`apply-layout`'s header/footer/page-restart requires editing docx
package parts directly** (an independent second header/footer
means adding new OOXML *parts*, which a Lua filter's `RawBlock`
injection can't do); that's why it's a separate post-render Python step
(`styling/quartifyr_styling/layout.py`) rather than part of the Quarto
filter chain. `header-format:`/`confidentiality:`/`{{< body-start >}}`
in a `.qmd` are all inert without running it.

**Word field recalculation (`quartifyr-styling recalculate-fields`,
headless LibreOffice) is experimental and known-flaky.** Real-world runs
against the same document have produced three different outcomes (hangs,
silent no-op, or success), reproduced both sandboxed and in a
plain macOS terminal. Off by default (`render_report(..., recalculate_fields = FALSE)`).
Don't treat a clean exit as proof it worked; see `r/README.md`'s "Word
field recalculation" section before changing this code path.

**`templates/org-reference.docx` is committed, not just a build
artifact.** Every other `templates/*.docx` is gitignored ("regenerate
with `quartifyr-styling build`"), but this specific file is the one
`--out` path this repo's own docs/CI/`render_report()` default point at,
committed on purpose so the two bundled examples (and `scripts/
quarto_only_smoke_test.py`'s Quarto-only render path) work straight out
of a clone without needing the `styling/` Python venv set up first.
`quartifyr-styling build`'s docx output isn't byte-reproducible across
runs (zipfile embeds a per-run timestamp in each entry), so `scripts/
check_template_freshness.py` compares unzipped content, not raw bytes;
run with `--check` (as both examples' `smoke_test.py` already do) to
catch drift from `styling/styles/default.yaml`, same pattern as `scripts/
sync_demo_extension.py` for the Lua extension copies.

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
`_extensions/quartifyr/README.md`'s "Title page" section).

When changing `_extensions/quartifyr/*.lua`, verify against the demo
(`python3 examples/demo-report/smoke_test.py`) and re-sync the demo's
physical extension copy (`python3 scripts/sync_demo_extension.py`);
there's no Lua unit test suite, so the smoke test is the only real
correctness signal for filter changes.
