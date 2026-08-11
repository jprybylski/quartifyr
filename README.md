# quartifyr

A code-first system for generating standardized scientific/regulated
documents, built on [Quarto](https://quarto.org) +
[`reportifyr`](https://github.com/A2-ai/reportifyr). Reports today;
presentations, analysis plans, and memos are meant to follow the same
approach over time — see [Scope](#scope) below.

## Why

Hand-built Word "shell" templates don't scale across projects or orgs —
every new study means someone re-clicking through Word's style pane, and
drift between shells is a matter of when, not if. The usual alternative,
pharmtex-style LaTeX pipelines, trades that problem for a steep learning
curve most scientific staff don't have, a toolchain that's genuinely prone
to breaking (LaTeX package resolution, font handling, obscure compile
errors), and an output format (PDF) that's harder for non-technical
reviewers to comment on directly than the Word documents they already
know.

quartifyr's answer: generate everything — the org's docx styling, the
report shell's title/signature/ToC/abbreviations front matter, appendix
numbering — from code and YAML, output real `.docx` all the way through,
and let `reportifyr` do what it already does well: filling that shell with
real tables, figures, and footnotes. No LaTeX. No manual Word template
surgery. A new org's look is a YAML diff; a new project is a copy of the
demo and a frontmatter edit.

## Architecture: two passes

```mermaid
flowchart LR
    subgraph Pass1["Pass 1 — Quarto"]
        yaml["style YAML\n(styling/styles/*.yaml)"] --> refdoc["org-reference.docx\n(quartifyr-styling build)"]
        qmd["shell .qmd\n(title/signature/appendix\nfrontmatter + {rpfy}: placeholders)"]
        refdoc --> render["quarto render"]
        qmd --> render
        render --> shell["shell.docx\n(structure + placeholders,\nno real content yet)"]
    end
    subgraph Pass2["Pass 2 — reportifyr (R)"]
        outputs["OUTPUTS/\n(tables, figures + metadata)"] --> fill["reportifyr::build_report()"]
        shell --> fill
        fill --> draft["report/draft/*.docx"]
        draft -->|finalize_document| final["report/final/*.docx"]
    end
```

1. **Pass 1 (Quarto)** renders a styled, structurally-complete shell
   (`.docx`) from a `.qmd`: title page (dynamic per-project fields, plus a
   DRAFT/FINAL status stamp), contributor/approval signature pages, table
   of contents (including the title page), list of figures, list of
   tables, list of abbreviations (only ones actually used), numbered
   appendices — but no actual figures/tables yet, just `reportifyr`
   magic-string placeholders (`{rpfy}:filename.ext`).
2. **Pass 2 (`reportifyr`, R)** fills that shell with real tables, figures,
   and footnotes from an `OUTPUTS/` directory, exactly as `reportifyr`
   already does for hand-built shells today, then optionally
   `finalize_document()`s it.

Both passes are driven by one call: `render_report()` in `r/` (see
[`r/README.md`](r/README.md)).

## Components

| Path | What it is |
| --- | --- |
| [`styling/`](styling/README.md) | Python package: turns a style YAML (fonts, colors, page setup) into a docx `reference-doc`; the `standard_footnotes.yaml` → `abbreviations.tex` bridge; headless Word field recalculation via LibreOffice (experimental). `uv`-managed venv. |
| [`_extensions/quartifyr/`](_extensions/quartifyr/README.md) | Quarto extension: dynamic title page + status stamp, contributor/approver signature pages, numbered appendices. Composes with [A2-ai's `quarto-plus`](https://github.com/A2-ai/quarto-plus) (ToC/List of Figures/List of Tables/abbreviations/captions) rather than duplicating it. |
| [`r/`](r/README.md) | `rv`-managed R environment pulling `reportifyr` and `pyro` straight from GitHub (no CRAN release exists for either), plus `render_report()`, the pass-1+pass-2 orchestration driver. |
| [`examples/demo-report/`](examples/demo-report/README.md) | Complete, working example exercising every piece above, with an automated end-to-end smoke test. Start here. |

Each org overrides just the parts of the default look that differ
(`styling/styles/default.yaml` is Times New Roman, black text, flat
neutral tables — no brand color baked in) as a small YAML diff, not a
round of clicking through Word's style pane.

## Quick start

```bash
# 1. Toolchain (once)
brew install --cask quarto
brew install uv
brew install a2-ai/tap/rv

# 2. Python tooling
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -e "./styling[dev]"

# 3. Org docx styling
quartifyr-styling build --style styling/styles/default.yaml --out templates/org-reference.docx

# 4. R tooling
cd r && rv sync && cd ..

# 5. Run the demo end to end
cd examples/demo-report
rv sync
Rscript render.R --final
# -> report/draft/report-draft.docx, report/final/report-final.docx
```

Or just run the demo's own smoke test, which does steps 5 for you and
asserts the output is actually correct: `python3
examples/demo-report/smoke_test.py`.

## Standing up a new org

An org's look lives entirely in one YAML file — no Word template editing.

```bash
cp styling/styles/default.yaml styling/styles/acme-pharma.yaml
# edit fonts/colors/page setup/table.header_bold/etc.
quartifyr-styling build \
  --style styling/styles/default.yaml \
  --override styling/styles/acme-pharma.yaml \
  --out templates/acme-pharma-reference.docx
```

See `styling/styles/default.yaml` for the full schema and
`styling/quartifyr_styling/schema.py` for validation rules.

## Standing up a new project

```bash
cp -r examples/demo-report path/to/new-project
cd path/to/new-project
rm -rf .venv .report_init.json .rpfy-logs OUTPUTS/*/* rv/library
```

Then:

1. If the new project lives outside this repo (the normal case — its own
   git repo, not nested under `quartifyr/`), you can also remove `.here`;
   it's only needed for projects nested inside another git repo (see
   `examples/demo-report/README.md`'s explanation).
2. `Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'`
   to regenerate `.report_init.json` and the `report/`/`OUTPUTS/`
   structure for this project.
3. Edit `report.qmd`'s frontmatter (title, lead scientist,
   contributors/approvers, etc.) and body content.
4. Extend `report/standard_footnotes.yaml` with any project-specific
   abbreviations (it starts from `reportifyr`'s org-wide defaults).
5. Point `render.R` at your own `reference_doc` if you're not using the
   default org styling.
6. Write your own `scripts/`, producing `OUTPUTS/tables/`,
   `OUTPUTS/figures/` artifacts via `reportifyr`'s
   `write_csv_with_metadata()`/`ggsave_with_metadata()` wrappers.
7. `Rscript render.R` (add `--final` once ready to finalize).

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

## Status and known limitations

The core pipeline — styling, title/signature pages, ToC/LOF/LOT,
abbreviations, appendices, and the `reportifyr` fill pass — is built and
verified end to end (see `examples/demo-report/smoke_test.py`, which runs
the real pipeline and checks the actual output on every run). Two things
are deliberately incomplete rather than papered over:

- **Word field recalculation** (`quartifyr-styling recalculate-fields`,
  headless LibreOffice) is experimental — it works, but has shown
  non-deterministic failure modes in real testing. See
  [`r/README.md`](r/README.md#word-field-recalculation-optional-off-by-default).
  Off by default; without it, delivered docs need one manual "select all,
  F9" in Word to populate the ToC.
- **Figure/table numbering stays continuous through appendices** (e.g.
  "Figure 12" inside an appendix, not "Figure B-1") — a deliberate v1
  scope call, not a bug. See
  [`_extensions/quartifyr/README.md`](_extensions/quartifyr/README.md#appendices).

## vs. pharmtex

| | pharmtex (LaTeX) | quartifyr |
| --- | --- | --- |
| Toolchain | Full LaTeX distribution + custom packages | Quarto + R + Python, all mainstream, `brew install`-able |
| Org styling | LaTeX template files, org-specific macros | One YAML file per org |
| Failure mode | Obscure LaTeX compile errors, package resolution | Ordinary Quarto/R/Python errors with normal stack traces |
| Output format | PDF | `.docx` — reviewers use Word's own track-changes/comments |
| Learning curve | Steep (LaTeX syntax, package ecosystem) | A `.qmd` is Markdown + YAML frontmatter |
| Report fill | Custom | `reportifyr` (unchanged, proven, already in use) |
