---
layout: default
title: GitHub Action
nav_order: 9
---

# Rendering in CI: the bundled GitHub Action

`action.yml` at the repo root wraps `r/`'s `render_report()` -- the same
Quarto pass-1 render → `apply-layout` → `reportifyr` pass-2 fill pipeline
described in [R orchestration](r-orchestration.html) -- as a composite
[GitHub Action](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action),
so another repo's own workflow can render its report without hand-rolling
the Quarto/R/`reportifyr` setup steps itself.

It only renders and reports output paths; uploading the result as a
build artifact is left to the calling workflow, same as any other
render-then-upload action:

```yaml
jobs:
  render:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: jprybylski/quartifyr@v1
        id: render
        with:
          shell-qmd: report.qmd
          final: 'true'

      - uses: actions/upload-artifact@v4
        with:
          name: report
          path: |
            ${{ steps.render.outputs.draft-docx }}
            ${{ steps.render.outputs.final-docx }}
```

## What it expects from the calling repo

Same idea as `goreleaser`/`.goreleaser.yaml` or `r-lib/actions`/
`renv.lock`: this action doesn't set up a project from nothing, it
expects one that's already a proper quartifyr + `reportifyr` project
(see [Standing up a new project](https://github.com/jprybylski/quartifyr#standing-up-a-new-project)):

- A shell `.qmd` (the `shell-qmd` input) with `_extensions/quartifyr`/
  `_extensions/quarto-plus` installed alongside it, and a `_quarto.yml`
  setting `project: {output-dir: report/shell}` -- load-bearing, not
  just a convention; see the "`report/shell` → `report/draft`/
  `report/final`" note in the repo-root `CLAUDE.md`.
- Its own `renv.lock` (with `reportifyr`/`pyro` pinned, same shape as
  [`examples/demo-report/renv.lock`](https://github.com/jprybylski/quartifyr/blob/main/examples/demo-report/renv.lock))
  -- **not** quartifyr's own `r/renv.lock`. Whatever analysis packages
  produced `OUTPUTS/figures/`/`OUTPUTS/tables/` belong in this
  lockfile too, since the action runs `renv::restore()` against it
  before rendering.
- `report/standard_footnotes.yaml` and `report/config.yaml`
  (`reportifyr::initialize_report_project()`'s usual output).

The action does *not* need `_extensions/`, `templates/`, `styling/`, or
`r/` checked out in the calling repo -- it brings its own copy of all of
those from its own release, resolved via `github.action_path`.

## Inputs

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `shell-qmd` | yes | -- | Path to the shell `.qmd`, relative to the calling repo's root. |
| `final` | no | `false` | Also produce `report/final/` via `reportifyr::finalize_document()`. |
| `reference-doc` | no | *(unset)* | Path to an org's docx reference-doc, relative to the calling repo's root. Unset uses this action's own bundled `templates/org-reference.docx` (quartifyr's default look) -- see [Styling](styling.html) for building your own. |
| `r-version` | no | `release` | Passed straight to `r-lib/actions/setup-r`. |
| `initialize-project` | no | `true` | Runs `reportifyr::initialize_report_project()` first. Set `false` if the calling workflow already does this itself. |

## Outputs

`shell-docx`, `draft-docx`, and (only when `final: true`) `final-docx` --
paths to the rendered docx files, for a following `actions/upload-artifact`
step (or any other step) to consume.

## What it actually does

1. Installs Quarto, R (`r-lib/actions/setup-r`), and `uv`.
2. Restores the calling project's own `renv.lock` (its `reportifyr`/
   `pyro`, plus whatever else its analysis needs).
3. Builds this action's own `styling/` venv, from its own checkout --
   the calling repo never needs to know `quartifyr-styling` exists.
4. Runs `reportifyr::initialize_report_project()` (unless
   `initialize-project: false`).
5. Runs `Rscript r/render.R <shell-qmd> [--final] [--reference-doc ...]
   --toolkit-root <this action's own checkout>`, with the working
   directory set to the calling project's own directory -- so R's normal
   startup activates *that* project's `renv`/`.Rprofile` (giving the
   session `reportifyr`/`pyro`), while `--toolkit-root` still points
   `render.R` at this action's own `templates/`/`_extensions/`/`.venv`
   for everything else. This split matters: package availability is
   fixed at the moment the R process starts (via the working directory's
   `.Rprofile`), not adjustable afterward from inside the script.

## Known limitations

- `recalculate_fields`/`resolve_same_page_crossrefs` (both off by
  default in `render_report()` itself; see
  [R orchestration](r-orchestration.html)) aren't exposed as inputs --
  `r/render.R`'s CLI doesn't take flags for them yet. Both are
  documented as experimental/flaky even in a plain terminal, so running
  them unattended in CI is a bigger ask than a first version of this
  action should default to.
- No dependency caching (`renv::restore()`/`uv`/system packages run
  fresh every invocation). Fine for occasional report renders; a
  frequently-triggered workflow may want to fork the action's steps and
  add `actions/cache` around `renv`'s library and the `uv` cache
  directory.

## Testing it yourself

`.github/workflows/ci.yml`'s `action-smoke-test` job dogfoods `action.yml`
against `examples/demo-report/` on every push -- the closest thing this
repo has to a unit test for the action itself, in the same spirit as the
end-to-end smoke tests described in the repo-root `CLAUDE.md`.
