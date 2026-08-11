# quartifyr (Quarto extension)

This is the front-matter piece of **quartifyr**, a code-first system for
generating standardized scientific/regulated documents with Quarto +
`reportifyr`'s two-pass shell/fill workflow (see the repo-root README for
the full picture). It's not scoped to "reports" specifically or to a title
page specifically — the same shell-generation approach is meant to extend
to presentations, analysis plans, memos, and other standardized document
kinds over time; this extension currently covers the front-matter pieces
most of those document kinds tend to need: a dynamic title page (with a
draft/final status stamp), contributor/approval signature pages, a
synopsis summary table, and numbered appendices.

This extension adds those on top of
[`quarto-plus`](https://github.com/A2-ai/quarto-plus)'s ToC/List of
Figures/List of Tables/abbreviations/caption machinery. Install both:

```bash
quarto add A2-ai/quarto-plus
quarto add jprybylski/quartifyr
```

## Usage

```yaml
---
title: "Population PK Analysis of Compound X"
subtitle: "Final Report"
report-type: "Clinical Study Report"
document-status: "draft"   # or "final" -- see Title page below
date: "2026-08-11"
lead-scientist: "Jane Doe, PharmD"
version: "1.0"
confidentiality: "Confidential — Do Not Distribute"
title-page-extra:
  - label: "Sponsor"
    value: "Acme Pharma"
contributors:
  authors:
    - name: "Jane Doe, PharmD"
      title: "Lead Scientist"
  reviewers:
    - name: "John Smith, PhD"
      title: "Senior Biostatistician"
approvers:
  - name: "Alice Lee, MD"
    title: "Medical Director"
synopsis:
  objectives: "..."
  methods: "..."
  results: "..."
format: docx
filters:
  - quarto-plus
  - quartifyr
# Required so the title page (styled "Title") shows up in quarto-plus's
# native Word ToC field, which otherwise only follows heading outline levels:
toc-style-map:
  - style: "Title"
    level: 1
---
```

### Title page

All fields except `title` are optional — the title page only renders the
rows that are actually set, so the same shell template works whether a
project has a `lead-scientist` or not. Add arbitrary extra rows per-project
with `title-page-extra` without touching any Lua.

The filter prepends the title page as the document's first page and
suppresses pandoc's own automatic title-block (which would otherwise
duplicate `title`/`subtitle`/`date`), so no other title-related frontmatter
handling is needed.

`document-status` renders as a bordered, bold, uppercase box right under
the title (a "stamp" rather than a colored watermark, to stay inside the
black/Times-New-Roman default look) -- unlike the other fields, it's
*always* shown, defaulting to `DRAFT` if omitted, since it's meant to be
impossible to miss. This is the same draft/final distinction `reportifyr`
already tracks via its `report/draft/` vs `report/final/` directories and
`finalize_document()` (which strips reportifyr's own bookmarks/magic
strings) -- `document-status` doesn't read that state automatically (the
Quarto render happens before any of reportifyr's pass-2 steps), so the
orchestration driver is responsible for keeping the two in sync: render
with `document-status: DRAFT` for anything headed to `report/draft/`, and
`FINAL` when producing what will become `report/final/`.

### Contributor / approval signature pages

Right after the title page, `contributors:` (with `authors:`/`reviewers:`
lists) renders a "Contributors" section, and a separate top-level
`approvers:` list renders an "Approvers" section. Each person gets their
own signature block: a blank signature line, printed name, and (for
contributors) title stacked in one column, with a role label
("Author"/"Reviewer") spanning beside it. Approvers use the same layout,
but since "Approvers" is already the section heading, the label slot next
to their signature line shows their actual job title instead of a
redundant "Approver" tag. Either key (`contributors:`, `approvers:`) can be
omitted if not needed.

There's no forced page break between the two sections — with only a
handful of contributors they'll naturally share a page; Word just flows
onto a new page once the content no longer fits. The only explicit break
this filter inserts is right after the title page (before "Contributors")
and once more after the last section (before the rest of the document).

### Synopsis

```
Synopsis

::: .synopsis
:::
```

Renders a bordered, two-column summary table (Title/Objectives/Methods/
Results — a standard CSR front-matter convention) from a `synopsis:`
frontmatter block:

```yaml
synopsis:
  objectives: "..."
  methods: "..."
  results: "..."
```

The "Title" row comes from the top-level `title:` field automatically.
Row *labels* are fixed; *values* are dynamic per-project. **To turn it
off, omit `synopsis:` from frontmatter entirely** — the `::: .synopsis
:::` div then renders nothing, so a shared shell template can leave the
div marker in unconditionally and let each project's frontmatter decide.

Author placement of the `::: .synopsis :::` div controls where it lands —
unlike the title page and signature pages (always first/second by
construction), a synopsis's conventional position varies more by org, so
this one isn't auto-inserted.

### Appendices

```
{{< appendix "StatsAppendix" "Statistical Analysis Details" >}}

... appendix body ...

{{< appendix "DataListings" "Data Listings" >}}
```

Each `{{< appendix "BookmarkId" "Title" >}}` renders an "Appendix A: ...",
"Appendix B: ...", ... heading using a native Word `SEQ Appendix \*
ALPHABETIC` field — reordering, adding, or removing appendices never
requires manual relettering, just a field recalculation (see
`../../r/README.md`'s "Word field recalculation" section — experimental,
off by default; without it, a delivered doc needs one manual "select all,
F9" in Word). It uses the `Heading 1` style — referenced by style ID
(`Heading1`), not display name, which matters: see "A pStyle gotcha"
below — so appendices show up in the ToC the same as any other top-level
heading, no `toc-style-map` entry needed.

Reference an appendix from body text with
`{{< appendix_crossref "BookmarkId" >}}`, which resolves to "Appendix A"
(etc.) via a `REF` field to the bookmark `appendix` set.

Note: figure/table numbering from `quarto-plus`'s own `fig_caption`/
`tbl_caption` shortcodes is intentionally left continuous through
appendices (e.g. "Figure 12" inside Appendix B, not "Figure B-1") — see
the comment at the top of `appendix.lua` for why and how that could be
extended later.

### Numbered sections

```yaml
number-sections: true
```

A plain pandoc/Quarto option, no quartifyr-specific code involved — it
numbers real body headings (`# Introduction` → "1.", `## Background` →
"1.1", `# Results` → "2.", ...) as static text baked in at render time,
correctly nested by level. Verified it does **not** touch title/signature/
appendix headings, since those are raw OOXML this extension injects
directly rather than genuine pandoc `Header` nodes — `number-sections`
only walks real ones. Per-project opt-in; see
`examples/demo-report/report.qmd` for a working example.

### A pStyle gotcha (if you're extending this extension)

`<w:pStyle w:val="...">` must reference a style's **ID** (e.g.
`Heading1`, `TableGrid` — no spaces), not its **display name** (`Heading
1`, `Table Grid`). Word/LibreOffice render the display-name form visually
fine via a fallback lookup, which makes this easy to miss — but Word's ToC
field silently fails to recognize such a paragraph as a heading at all
(confirmed via a real Word field-recalculation test: Contributors/
Approvers/the appendix were rendering correctly but missing from the ToC
entirely until this was fixed), and a wrong table style reference silently
drops the reference-doc's customized borders/shading. If you add new raw
OOXML in this extension referencing a multi-word built-in style, use the
ID form.

### Styling

Pair with a docx `reference-doc:` generated by `styling/` (see
`../../styling/README.md`) so the `Title`/`Subtitle`/`Heading N` styles this
filter emits actually carry your org's fonts/colors.
