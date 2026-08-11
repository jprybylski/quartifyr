# quartifyr demo report

A complete, working example of quartifyr's two-pass pipeline, in the
spirit of `reportifyr-examples`: a small PK-style report built from base
R's built-in `Theoph` dataset, exercising every piece of the toolkit --
dynamic title page, draft/final status stamp, contributor/approver
signature pages, table of contents (including the title page), list of
figures, list of tables, only-used abbreviations, a numbered appendix, and
a real `reportifyr` fill pass.

## Layout

- `scripts/01_analysis.R` -- generates `OUTPUTS/tables/pk-summary.csv` and
  `OUTPUTS/figures/conc-time.png` (with reportifyr metadata sidecars) from
  `Theoph`. Already run; outputs are committed so the demo works
  immediately after a clone. Re-run it if you want to regenerate them.
- `report/shell/report.qmd` -- the shell source: frontmatter drives the
  title page/signature pages, body uses `{rpfy}:` magic strings plus
  `quarto-plus`/`quartifyr` shortcodes for captions, abbreviations, and the
  appendix.
- `report/standard_footnotes.yaml`, `report/config.yaml` -- reportifyr's
  own defaults (via `reportifyr::initialize_report_project()`).
- `render.R` -- runs the full pipeline via the toolkit's
  `render_report()` (see `../../r/README.md`).
- `smoke_test.py` -- automated end-to-end check (see below).

## Running it

```bash
cd examples/demo-report
Rscript render.R           # -> report/draft/report-draft.docx
Rscript render.R --final   # also -> report/final/report-final.docx
```

Requires this repo's toolchain to already be set up: `rv sync` in both
`../../r/` and this directory, and the `styling/` venv (`uv venv .venv &&
uv pip install -e "./styling[dev]"` from the repo root, plus
`quartifyr-styling build` to produce `templates/org-reference.docx` if you
haven't already).

## Smoke test

```bash
source ../../.venv/bin/activate
python3 smoke_test.py
```

Runs `Rscript render.R --final` for real and asserts on the resulting
docx: no leftover `{rpfy}:` magic strings, the PK summary table and
concentration-time figure are actually filled in (not placeholders), the
title page/status stamp/appendix lettering all rendered, and `\gls{PK}`
resolved through the abbreviations bridge. Skips (exit 0) if `Rscript` or
`quarto` aren't on `PATH`.

## Why this project has its own `.here` file

`pyro` (reportifyr's Python/venv plumbing) resolves its project root via
`here::here()`, which walks up looking for `.git`/`.here`/etc. Since this
example lives *inside* the quartifyr git repo rather than as its own
repo, `here::here()` would otherwise walk straight past this directory to
the outer repo root -- silently seeding `pyproject.toml`/`.venv`/
`.rpfy-logs/` there instead of here. The empty `.here` file is `here`'s own
documented mechanism for pinning the root at this directory; don't remove
it.
