---
layout: default
title: Installation
nav_order: 2
---

# Installation

quartifyr's three components are independently usable — install only
what you need.

## 1. Quarto extension only

If you just want the shell-generation pieces (title page, signature
pages, synopsis, numbered appendices, header/footer), this is a regular
Quarto extension:

```bash
quarto add jprybylski/quartifyr
```

It composes with [A2-ai's `quarto-plus`](https://github.com/A2-ai/quarto-plus)
for ToC/list of figures/list of tables/abbreviations rather than
duplicating them, so install that too:

```bash
quarto add A2-ai/quarto-plus
```

With nothing else installed you can already render a real, styled shell
— see the [Quick start](index.html#quick-start) on the home page. The
only other prerequisite is [Quarto](https://quarto.org/docs/get-started/)
itself.

## 2. `styling/` — the reference-doc builder

Python, managed with [`uv`](https://docs.astral.sh/uv/getting-started/installation/):

```bash
# from the repo root
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e "./styling[dev]"
```

This gets you the `quartifyr-styling` CLI — see [Styling](styling.html)
for its subcommands.

## 3. `r/` — the pass-1 + pass-2 orchestration driver

R, managed with [`renv`](https://rstudio.github.io/renv/):

```bash
cd r && Rscript -e 'renv::restore()'
```

This is a convenience wrapper around Quarto + `quartifyr-styling` +
`reportifyr` — see [R orchestration](r-orchestration.html). It's optional;
you can call the three underlying pieces yourself instead.

## Full toolchain, end to end

For the complete two-pass pipeline (real tables/figures/footnotes
filled in, not just the shell):

```bash
# 1. Python tooling
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e "./styling[dev]"

# 2. R tooling
cd r && Rscript -e 'renv::restore()' && cd ..

# 3. Run the demo end to end
cd examples/demo-report
Rscript -e 'renv::restore()'
Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'   # first clone only
Rscript render.R --final
# -> report/draft/report-draft.docx, report/final/report-final.docx
```

Or just run the demo's own smoke test, which does step 3 for you and
asserts the output is actually correct:

```bash
python3 examples/demo-report/smoke_test.py
```

See [Examples](examples.html) for what this produces.
