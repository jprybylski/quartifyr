# quartifyr

A code-first system for generating standardized scientific/regulated
documents, built on [Quarto](https://quarto.org) +
[`reportifyr`](https://github.com/A2-ai/reportifyr). Reports today;
presentations, analysis plans, and memos are meant to follow the same
approach over time — see [Scope](#scope) below.

## Why

Hand-built Word "shell" templates don't scale across projects or orgs, and
[pharmtex](https://github.com/search?q=pharmtex) (the LaTeX-based
alternative some teams reach for) trades that problem for a steep LaTeX
learning curve and a toolchain that's prone to breaking. quartifyr's answer
is: generate everything — the org's docx styling, the report shell's
title/signature/ToC/abbreviations front matter, appendix numbering — from
code and YAML, and let `reportifyr` do what it already does well: filling
that shell with real tables, figures, and footnotes.

## Architecture: two passes

1. **Pass 1 (Quarto)** renders a styled, structurally-complete shell
   (`.docx`) from a `.qmd`: title page, contributor/approval signature
   pages, table of contents, list of figures, list of tables, list of
   abbreviations, numbered appendices — but no actual figures/tables yet,
   just `reportifyr` magic-string placeholders (`{rpfy}:filename.ext`).
2. **Pass 2 (`reportifyr`, R)** fills that shell with real tables, figures,
   and footnotes from an `OUTPUTS/` directory, exactly as `reportifyr`
   already does for hand-built shells today.

## Components

| Path | What it is |
| --- | --- |
| [`styling/`](styling/README.md) | Python package: turns a style YAML (fonts, colors, page setup) into a docx `reference-doc`, plus the `standard_footnotes.yaml` → `abbreviations.tex` bridge. `uv`-managed venv. |
| [`_extensions/quartifyr/`](_extensions/quartifyr/README.md) | Quarto extension: dynamic title page, contributor/approver signature pages, numbered appendices. Composes with [A2-ai's `quarto-plus`](https://github.com/A2-ai/quarto-plus) (ToC/List of Figures/List of Tables/abbreviations/captions) rather than duplicating it. |
| `r/` | `rv`-managed R environment pulling `reportifyr` and `pyro` straight from GitHub (no CRAN release exists for either), plus the pass-2 orchestration driver. |
| `examples/demo-report/` | End-to-end example project exercising the full pipeline, in the spirit of `reportifyr-examples`. |

Each style/org can override just the parts of the default look that
differ (`styling/styles/default.yaml` is Times New Roman, black text, flat
neutral tables — no brand color baked in) as a small YAML diff, not a round
of clicking through Word's style pane.

## Scope

This is not a "title page generator." The two-pass, code-first
shell/fill approach is meant to generalize across document kinds that
scientific/regulated teams standardize on:

- **Reports** (the current focus, via `reportifyr`)
- **Presentations** — co-generated alongside reports, tying into A2-ai's
  sibling `presentifyr` package (same "fyr" ecosystem as `reportifyr` and
  `pyro`)
- **Analysis plans**
- **Memos**

The pieces already built stay deliberately document-kind-agnostic where
that costs nothing (the style YAML schema, the docx template generator);
document-kind-specific pieces (title/signature pages, appendix numbering)
live in the Quarto extension and are added as needed rather than
speculatively.

## Status

Actively under construction. See open issues/project board for what's
built vs. in progress; each component's own README documents what's usable
today.

## Setup

```bash
# Python tooling (styling/)
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e "./styling[dev]"

# R tooling (r/, examples/demo-report/) -- reportifyr/pyro pulled from GitHub
brew install a2-ai/tap/rv   # or see https://a2-ai.github.io/rv-docs/
cd r && rv sync

# Quarto extension (in a report project)
quarto add A2-ai/quarto-plus
quarto add jprybylski/quartifyr
```
