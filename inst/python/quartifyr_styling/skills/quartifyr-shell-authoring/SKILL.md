---
name: quartifyr-shell-authoring
description: "Author or edit a quartifyr shell .qmd — front matter (title page, memo cover, signature page, synopsis, header/footer, confidentiality), appendices, figure/table captions and cross-references, and {rpfy}: magic-string placeholders. Use when standing up a new report/memo shell, adding a section or appendix, wiring up figure/table numbering, or debugging why a rendered docx is missing a page or field."
---

# quartifyr shell authoring: the .qmd itself

quartifyr (https://github.com/jprybylski/quartifyr) renders a **pass-1
shell**: a styled, structurally-complete `.docx` (title page, signature
pages, ToC, synopsis, numbered appendices) with `{rpfy}:filename.ext`
magic-string placeholders where real content will go. A separate pass-2
tool (`reportifyr`) fills those placeholders later — this skill covers
authoring the shell `.qmd` and its front matter, not the style YAML that
controls fonts/colors/margins (that's `quartifyr-style-config`) and not
`reportifyr`'s own pass-2 fill step.

## Get the authoritative front-matter check first

Front-matter fields change as this extension evolves; don't rely on this
skill's own field list as exhaustive. Before or after editing a shell
`.qmd`'s front matter, run:

```r
quartifyr::validate_header("report.qmd")
```

It checks the file's front matter (and its project's `_quarto.yml`)
against every field the Lua filters and the `apply-layout` step actually
read, and reports what's set, what's missing (required vs. merely
recommended), what else is available and what it does, and any conflicts
(e.g. both `title:` and `memo:` set). This needs no Quarto installation.
For a brand-new project, `quartifyr::header_helper()` interactively builds
a front-matter block from scratch instead of writing one from a blank
page.

## Mental model

- **Two mutually-exclusive cover styles**: `title:` (a formal report title
  page: title/subtitle/date/lead-scientist/version/confidentiality/logo,
  plus a `document-status` DRAFT/FINAL stamp) or `memo:` (a fax-cover-sheet
  To/From/Date/Re cover, no ToC/synopsis needed) — set exactly one, never
  both.
- **Signature page**: `contributors:` (`authors:`/`reviewers:` lists) and
  `approvers:` render a combined "Signatures" section right after the
  cover. Omit either key if not needed; omit both and no Signatures page
  renders.
- **Synopsis**: a `synopsis:` YAML *list* of `{label, value}` rows (a list,
  not a map — pandoc's Lua metadata tables don't preserve map key order)
  renders a summary table wherever you place the `::: .synopsis :::` div
  in the body. Omit `synopsis:` entirely to turn the whole section off.
  `value:` can itself be a list mixing plain-string paragraphs with
  `{image: "name.png", width: "3in"}` entries — `image:` is a bare
  filename inside `OUTPUTS/figures/`, resolved by reportifyr's pass 2 via
  a `{rpfy}:` magic string, not a path you can point anywhere.
- **`{rpfy}:filename.ext` placeholders** are `reportifyr`'s own mechanism,
  not something you construct by hand beyond the synopsis `image:` case
  above — the Lua filters emit them, `reportifyr::build_report()` resolves
  them from `OUTPUTS/figures/`/`OUTPUTS/tables/`. A plain `quarto render`
  leaves the literal `{rpfy}:...` text visible; that's expected until
  pass 2 runs, not a bug.
- **Appendices**: `{{< appendix "BookmarkId" "Title" >}}` renders
  "Appendix A: Title" (etc.) via a live field, so reordering/adding/
  removing appendices never needs manual relettering. Reference one with
  `{{< appendix_crossref "BookmarkId" >}}`. `appendix-numbering:` (front
  matter) switches the designator style (`alphabetic`/`arabic`/`roman`).
- **Figures/tables**: `{{< fig_caption "FigId" "Caption" >}}` /
  `{{< tbl_caption "TblId" "Caption" >}}` auto-number continuously through
  the whole document (via `quarto-plus`); cross-reference with
  `{{< crossref "FigId" >}}`. The bookmark id (not a number) must start
  with `Fig`/`Figure` or `Tbl`/`Table` so the right counter picks it up.
- **Scoped numbering** (`appendix_fig_caption`/`section_fig_caption`/
  `subsection_fig_caption` and their `_tbl_caption` counterparts) is an
  *additive*, separate counter for wherever numbering should restart
  within an appendix/section/subsection instead of running continuously —
  numbers like "Figure A.1" or "Figure 3.1". `section_fig_caption`/
  `subsection_fig_caption` need an explicit `{{< section_break >}}` /
  `{{< subsection_break >}}` placed next to the `#`/`##` heading itself
  (ordinary headings aren't shortcodes, so there's no other reliable place
  to reset the counter) — call each exactly once per section/subsection
  you want reflected, in document order. Cross-reference any of the six
  scoped captions with `{{< scoped_crossref "BookmarkId" >}}`.
- **Combined List of Figures/Tables**: `quarto-plus`'s own
  `.list_of_figures`/`.list_of_tables` divs only include the continuous
  `fig_caption`/`tbl_caption` captions. If a document also uses any scoped
  caption, use `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables`
  instead (same div syntax) to get every caption, continuous and scoped
  alike, listed in true document order.

## Header/footer, confidentiality, page numbering

```yaml
project: "ACME-001"
report_number: "RPT-2026-014"
header-format: "{project} - {report_number}"
confidentiality: "Confidential — Do Not Distribute"
```

Inert on a plain `quarto render` — these fields (and `{{< body-start >}}`,
placed right before your first real body heading) only take effect
through the post-render `apply-layout` step, run automatically by
`quartifyr::render_report()`. Without it: no header, no footer
confidentiality label, no roman-numeral/arabic page-number split. Don't
debug a "missing header" as a Lua filter bug before confirming
`render_report()` (not a bare `quarto render`) actually ran.

## Render and verify

```r
quartifyr::render_report("report.qmd", status = "draft")
```

Runs Quarto render → `apply-layout` → `reportifyr::build_report()` in one
call. For debugging shell-only issues (no reportifyr fill), the three
pieces can be run directly instead — see the repo's `README.md` and
`inst/extensions/quartifyr/README.md` for the manual multi-step sequence
and every front-matter field's full behavior in detail.
