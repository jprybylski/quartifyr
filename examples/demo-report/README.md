# quartifyr demo report

A complete, working example of quartifyr's two-pass pipeline, in the
spirit of `reportifyr-examples`: a small PK-style report built from base
R's built-in `Theoph` dataset, exercising every piece of the toolkit --
dynamic title page, draft/final status stamp, contributor/approver
signature pages, table of contents (including the title page), list of
figures, list of tables, only-used abbreviations, a citeproc-driven
bibliography (populated before the appendices), a numbered appendix, and
a real `reportifyr` fill pass.

## Layout

- `report.qmd` -- the shell source, at the project root alongside
  `_extensions/` (standard Quarto project layout). Frontmatter drives the
  title page/signature pages, body uses `{rpfy}:` magic strings plus
  `quarto-plus`/`quartifyr` shortcodes for captions, abbreviations, and the
  appendix.
- `references.bib` -- sample bibliography cited from the body via
  `[@key]`, rendered in the extension's default NLM/Vancouver bracketed
  numbered style (`[1]`, `[2]`, ..., each hyperlinked to its entry); see
  `_extensions/quartifyr/README.md`'s "Bibliography / references" section
  for how the References heading + `{#refs}` Div in `report.qmd` control
  where the reference list ends up.
- `_quarto.yml` -- sets `project: {output-dir: report/shell}`, which is
  what actually redirects the render into `report/shell/`
  (`reportifyr::make_doc_dirs()` needs the docx there, not the qmd).
- `_extensions/quartifyr/` -- a **physical copy** of the repo-root
  `_extensions/quartifyr/`, not a symlink (Quarto's extension loader
  doesn't follow symlinks -- confirmed, `quarto render` fails outright
  through one). Kept in sync via `scripts/sync_demo_extension.py`, checked
  automatically by `smoke_test.py` (see below) -- if you edit the
  repo-root extension, re-run that script before trusting this demo's
  output.
- `scripts/01_analysis.R` -- generates `OUTPUTS/tables/pk-summary.csv`,
  `OUTPUTS/tables/participant-demographics.rds`, and
  `OUTPUTS/figures/conc-time.png` (with reportifyr metadata sidecars) from
  `Theoph`. Already run; outputs are committed so the demo works
  immediately after a clone. Re-run it if you want to regenerate them. The
  two tables deliberately demonstrate reportifyr's two ways of filling a
  `{rpfy}:` table magic string: `pk-summary.csv` is a plain data frame,
  which `reportifyr::add_tables()` always reformats with its own hardcoded
  Arial Narrow 10pt styling regardless of this report's actual body font;
  `participant-demographics.rds` is a pre-built, hand-styled `flextable`
  object (matching this report's Times New Roman body font), which
  `add_tables()` inserts completely as-is instead. See that script's
  comment for the full "style bleed" explanation.
- `report/standard_footnotes.yaml`, `report/config.yaml` -- reportifyr's
  own defaults (via `reportifyr::initialize_report_project()`).
- `render.R` -- runs the full pipeline via the `quartifyr` R package's
  `render_report()` (see the repo-root README).
- `smoke_test.py` -- automated end-to-end check (see below).

## Quick look: shell only, Quarto alone (no R, no Python)

`../../inst/templates/org-reference.docx` is committed to the repo (see
the repo-root README's "Style YAML and reference-doc" section), so the
shell alone -- title page, signature pages, synopsis, everything pass 1
produces -- renders with nothing but Quarto installed:

```bash
cd examples/demo-report
quarto render report.qmd --to docx --reference-doc ../../inst/templates/org-reference.docx \
  -M document-status:DRAFT
```

`{rpfy}:` placeholders and `\gls{PK}` stay unresolved in the output --
expected, not a bug: pass 2 (`reportifyr`) and the abbreviations bridge
(`quartifyr-styling abbrevs`) never ran. `scripts/
quarto_only_smoke_test.py` (repo root) runs exactly this and asserts on
the result.

## Running it

For the full two-pass pipeline (real tables/figures/abbreviations filled
in), this repo's toolchain needs to be set up: `Rscript -e
'renv::restore()'` in this directory, the `quartifyr` R package itself
(`Rscript -e 'renv::install("local::../..")'`, from this directory --
installs into this project's own renv library, pulling in
`reportifyr`/`pyro` transitively), and the repo-root Python venv (`uv
venv .venv && uv pip install -e '.[dev]'` from the repo root). If
`renv::restore()`/`renv::install()` here unexpectedly tries to reach
GitHub or recurrently times out against `a2-ai.r-universe.dev`: r-universe
stamps GitHub provenance (`RemoteType`/`RemoteUrl`/`RemoteSha`) into
`reportifyr`/`pyro`'s `DESCRIPTION`, which `renv` can fall back to
`git clone`-ing if a repository-based install doesn't succeed first try;
this project's `.Rprofile` already raises R's download timeout to
mitigate slow/proxied links reaching `a2-ai.r-universe.dev` in the first
place.

`.report_init.json` is gitignored (it embeds a username/timestamp), so a
fresh clone needs two setup calls before the first render -- both are
safe to run even though `report/standard_footnotes.yaml`/
`report/config.yaml`/`OUTPUTS/` are already committed, since neither
overwrites existing files:

```bash
cd examples/demo-report
Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'
Rscript -e 'quartifyr::initialize_quartifyr_project(getwd())'

Rscript render.R           # -> report/draft/report-draft.docx
Rscript render.R --final   # also -> report/final/report-final.docx
```

## Smoke test

```bash
source ../../.venv/bin/activate
python3 smoke_test.py
```

First checks `_extensions/quartifyr/` hasn't drifted from the repo-root
copy (see Layout above), then runs `Rscript render.R --final` for real and
asserts on the resulting docx: no leftover `{rpfy}:` magic strings, the PK
summary table, participant demographics table, and concentration-time
figure are actually filled in (not placeholders), the two tables' body
text renders in their respective fonts (Arial Narrow for the plain-data-
frame table, Times New Roman for the pre-built flextable -- see Layout
above), the title page/status stamp/appendix lettering all rendered,
`\gls{PK}` resolved through the abbreviations bridge, and the bibliography
renders (in-text citations resolved, entries present, and populated
before the appendices rather than after). Skips (exit 0) if `Rscript` or
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
