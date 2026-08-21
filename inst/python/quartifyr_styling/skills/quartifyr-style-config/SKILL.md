---
name: quartifyr-style-config
description: Author or edit a quartifyr style YAML (fonts, colors, page margins, header/footer, equation font, table/heading styles) and build it into a docx reference-doc. Use when creating a new org/project style override, changing typography or page layout for a report shell, or regenerating org-reference.docx after a style edit.
---

# quartifyr style configuration: style YAML → docx reference-doc

quartifyr (https://github.com/jprybylski/quartifyr) generates a
structurally-complete `.docx` report shell with Quarto. The shell's actual
look — fonts, colors, page margins, heading/table styles, header/footer
defaults — comes from a **style YAML**, compiled into a docx
`reference-doc` by the bundled Python engine (`quartifyr_styling`). This
skill covers authoring that style YAML and building/updating the
reference-doc from it. Authoring the shell `.qmd` itself (frontmatter,
appendices, captions) is a different skill (`quartifyr-shell-authoring`) —
don't put document content or frontmatter here.

## Start from the bundled default, don't write from a blank page

```r
quartifyr::styling_example_style(dir = ".", file = "style.yaml")
```

Copies the package's own `inst/python/styles/default.yaml` into your
project and returns its parsed content as an R list, ready to edit in
place. The equivalent CLI form is
`quartifyr-styling example-style --out style.yaml`. Read the copied file
directly for the authoritative, current field list — its own comments
document every section (page margins, fonts, colors, table styles,
header/footer, equation font, ...); don't rely on this skill's examples as
an exhaustive reference, since fields are added as the style schema grows.

## Mental model

- One YAML document, deep-mergeable: a project/org override YAML is
  layered on top of a base style YAML (usually the bundled default),
  field by field — you only need to specify what differs from the base,
  not repeat the whole document.
- Broad sections to expect (see the copied `default.yaml` for the exact,
  current shape): `page` (margins in inches), `fonts` (body/heading font
  families and sizes), `colors`, heading/title/table paragraph styles,
  `footer` (`show_page_number`, or static `text`), and `equation` (the
  default math font `apply-layout` applies to the rendered docx).
- Percentage-width tables: every table quartifyr's Quarto extension
  generates spans the *current* usable text width (`w:type="pct"`), so
  changing `page.margins_in` here never leaves a table overflowing or
  falling short — no extra style-side accounting needed when adjusting
  margins.

## Build (or rebuild) the reference-doc

```r
quartifyr::styling_build_reference_docx(style = "style.yaml", out = "templates/org-reference.docx")
# with an org override layered on top of a base style
quartifyr::styling_build_reference_docx(style = "base.yaml", override = "acme-pharma.yaml", out = "acme-pharma-reference.docx")
```

CLI equivalent: `quartifyr-styling build --style style.yaml --out templates/org-reference.docx`
(`--override` for a layered org/project style). Rebuild whenever the style
YAML changes — the reference-doc isn't regenerated automatically, and a
stale one silently keeps the old look. The docx output isn't
byte-reproducible across runs (each build embeds a per-run timestamp), so
don't diff it directly to check whether a rebuild is needed; diff the
style YAML instead.

## Small, targeted edits

For a single field change rather than a full rewrite, edit the parsed
style list in R and save just the diff from its base:

```r
style <- quartifyr::styling_example_style(dir = ".")
style$page$margins_in$top <- 1.25
quartifyr::styling_save_overrides(base = "style.yaml", style = style, out = "overrides.yaml")
```

`styling_save_overrides()` defaults to saving only what changed from
`base` (an override YAML, not a full copy) — pass `deconvolute = FALSE` to
save the whole style dict as-is instead.
`quartifyr::styling_update_style()` deep-merges a small update onto an
existing style YAML in place, for editing a style file directly without
recomputing the whole document by hand.

## Keep reportifyr's own config in sync

If a project's footnotes render through `reportifyr`, its
`report/config.yaml` tracks its own `footnotes_font`/`footnotes_font_size`
independently of this style YAML — the two can drift apart silently.
`quartifyr::styling_sync_reportifyr_config()` updates `report/config.yaml`
to match a style YAML's footnote font settings; run it after any style
edit that touches typography, or after switching which style YAML a
project uses.
