# quartifyr

A code-first system for generating standardized scientific/regulated
documents with [Quarto](https://quarto.org): an org's docx styling and a
document's title/signature/ToC/abbreviations front matter come from YAML
and a `.qmd`, not a hand-edited Word template. A separate pass-2 tool
then fills the rendered shell with real content — today that's
[`reportifyr`](https://github.com/A2-ai/reportifyr) for reports;
presentations, analysis plans, and memos are meant to follow the same
shell/fill split over time — see [Document kinds](#document-kinds)
below.

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
shell's title/signature/ToC/abbreviations front matter, appendix
numbering — from code and YAML, output real `.docx` all the way through,
then hand the shell to a fill tool to do what it already does well:
filling it with real tables, figures, and footnotes. That's `reportifyr`
today. No LaTeX. No manual Word template surgery. A new org's look is a
YAML diff; a new project is a `.qmd` with the right frontmatter, not a
Word template someone hand-builds from scratch.

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
    subgraph Pass2["Pass 2 — fill (reportifyr, R)"]
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
2. **Pass 2 (fill)** fills that shell with real tables, figures, and
   footnotes from an `OUTPUTS/` directory, then optionally finalizes it.
   `reportifyr` is today's fill tool for reports, doing this exactly as it
   already does for hand-built shells; presentations are meant to use the
   same shell/fill split, filled by `reportifyr`'s sibling `presentifyr`.

Both passes are driven by one call: `render_report()` in `r/` (see
[`r/README.md`](r/README.md)).

## Components

| Path | What it is |
| --- | --- |
| [`styling/`](styling/README.md) | Python package: turns a style YAML (fonts, colors, page setup) into a docx `reference-doc`; the `standard_footnotes.yaml` → `abbreviations.tex` bridge; headless Word field recalculation via LibreOffice (experimental). `uv`-managed venv. |
| [`_extensions/quartifyr/`](_extensions/quartifyr/README.md) | Quarto extension: dynamic title page + status stamp, contributor/approver signature pages, numbered appendices. Composes with [A2-ai's `quarto-plus`](https://github.com/A2-ai/quarto-plus) (ToC/List of Figures/List of Tables/abbreviations/captions) rather than duplicating it. |
| [`r/`](r/README.md) | `rv`-managed R environment providing `render_report()`, the pass-1+pass-2 orchestration driver. Pulls `reportifyr` and `pyro` straight from GitHub (no CRAN release exists for either) as today's fill backend. |
| [`examples/demo-report/`](examples/demo-report/README.md) | Complete, working example exercising every piece above, with an automated end-to-end smoke test — a reference to compare against, not the only way to start a project (see [Standing up a new project](#standing-up-a-new-project)). |

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

A project is a normal Quarto project plus the pieces `reportifyr` and
this repo's `render_report()` expect. It needs:

1. **The extensions**, physically copied (not symlinked — Quarto's
   extension loader doesn't follow symlinks) into `_extensions/` at the
   project root, alongside the shell `.qmd`:
   ```bash
   quarto add A2-ai/quarto-plus
   quarto add jprybylski/quartifyr
   ```
2. **`_quarto.yml`** setting `project: {output-dir: report/shell}` — this
   is what redirects the rendered docx into `report/shell/`, where
   `reportifyr::make_doc_dirs()` (called by `render_report()`) expects to
   find it.
3. **A shell `.qmd`** at the project root with `filters: [quarto-plus,
   quartifyr]` and `toc-style-map: [{style: Title, level: 1}]`, plus
   frontmatter for whichever front-matter pieces you want (`title`,
   `contributors`/`approvers`, `synopsis`, `header-format`, ...) — see
   [`_extensions/quartifyr/README.md`](_extensions/quartifyr/README.md)
   for the full list, and use `{{< body-start >}}`/`{rpfy}:` placeholders/
   `quarto-plus`'s caption shortcodes in the body as needed.
4. **`reportifyr`'s own project structure** (`report/standard_footnotes.yaml`,
   `report/config.yaml`, `OUTPUTS/`):
   ```bash
   Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'
   ```
5. **A docx reference-template** — reuse an existing org one, or build a
   new one (see [Standing up a new org](#standing-up-a-new-org) above).

Then write your own `scripts/`, producing `OUTPUTS/tables/`/
`OUTPUTS/figures/` artifacts via `reportifyr`'s
`write_csv_with_metadata()`/`ggsave_with_metadata()` wrappers, and render
with `Rscript render.R` (add `--final` once ready to finalize).

[`examples/demo-report/`](examples/demo-report/README.md) has all of the
above wired together and working end to end — a reference to check your
own setup against, not a starting point you're expected to fork.

## Document kinds

The shell/fill split generalizes across whatever document kinds a
scientific/regulated team standardizes on, not just reports:

- **Reports** (the current focus, filled by `reportifyr`)
- **Presentations** — filled by `reportifyr`'s sibling `presentifyr`
  (same "fyr" ecosystem as `reportifyr` and `pyro`)
- **Analysis plans**
- **Memos**

The pieces already built stay document-kind-agnostic where that costs
nothing (the style YAML schema, the docx template generator);
document-kind-specific pieces (title/signature pages, appendix numbering)
live in the Quarto extension and get added as needed rather than
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
| Report fill | Custom | `reportifyr` today — pass-2 is a pluggable fill step, not fixed to it |
