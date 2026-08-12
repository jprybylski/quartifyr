# quartifyr (Quarto extension)

This is the shell-generation piece of **quartifyr**, a code-first system
for generating standardized scientific/regulated documents with Quarto
(see the repo-root README for the full picture, including the pass-2 fill
step -- `reportifyr` today). The same shell-generation approach is meant
to extend across document kinds -- reports, presentations, analysis
plans, memos -- over time; this extension currently covers the
front-matter pieces most of them tend to need: a dynamic title page (with
a draft/final status stamp), contributor/approval signature pages, a
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
logo: "assets/logo.png"          # optional
logo-width: "2in"                 # optional, default "2in"
address:                          # optional, for memo-type documents
  - "Acme Pharma"
  - "123 Research Parkway, Suite 400"
  - "Raleigh, NC 27609"
project: "ACME-001"               # feeds header-format below, not shown on its own
report_number: "RPT-2026-014"     # feeds header-format below, not shown on its own
header-format: "{project} - {report_number}"   # optional, see Page header/footer below
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
# signature-mode: "note"                      # default "line" -- see below
# signature-note: "Approved electronically in the XYZ system"
synopsis:
  - label: "Objectives"
    value: "..."
  - label: "Methods"
    value: "..."
  - label: "Results"
    value: "..."
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
project has a `lead-scientist` or not. The info block (Date/Lead
Scientist/Version/Confidentiality/...) renders as a full-width table, not
centered text lines — borderless and unshaded (no header-row styling on
the first row), with the label column bold and the value column plain so
rows stay readable without table gridlines.

`logo:` (a path to an image, relative to the `.qmd`) places a centered
logo below the title-page fields — omit it and no space is reserved, no
placeholder box. `logo-width:` controls its rendered width (default
`"2in"`; any pandoc-recognized image width, e.g. `"150px"`).

`address:` is a YAML list of lines (not a single string, so multi-line
addresses render as genuine separate lines rather than one run-together
paragraph — see `synopsis:`/`title-page-extra:` above for the same
list-over-map reasoning) and adds an "Address" row to the info block, for
memo-type documents that need a sender address on the title page. Omit it
for document kinds that don't need one.

**Fully flexible, not a fixed field list**: `date`/`lead-scientist`/
`version`/`confidentiality` are named convenience fields (simpler to
write than a list for the common case) rendered first, in that order,
when present -- but `title-page-extra` then appends *any number* of
additional label/value rows after them, in whatever order you write
them, with any label you want:

```yaml
title-page-extra:
  - label: "Sponsor"
    value: "Acme Pharma"
  - label: "Protocol Number"
    value: "ACM-1001"
```

This is a YAML *list*, not a plain map (`sponsor: "Acme Pharma"`)
deliberately: pandoc's Lua metadata tables don't preserve map key order
(confirmed by testing -- iterating a YAML map's keys came back in
neither declaration nor alphabetical order), which would make dynamic
fields print in an unreliable order on every render. A list's order is
reliable, so arbitrary rows go through `title-page-extra` rather than
bare top-level `foo: bar` keys.

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
own full-width, bordered signature block: a blank signing space, printed
name, and (for contributors) title stacked in one column, with a role
label ("Author"/"Reviewer") spanning beside it. Approvers use the same
layout, but since "Approvers" is already the section heading, the label
slot next to their signing space shows their actual job title instead of
a redundant "Approver" tag. Either key (`contributors:`, `approvers:`) can
be omitted if not needed.

The signing-space row is a tall, empty cell -- deliberately no line or
box drawn inside it, since the table's own bordered cell already reads
as "sign here" and an internal rule doubled up visually. When physical/
wet signatures aren't the actual workflow (e.g. a validated e-signature
system), set:

```yaml
signature-mode: "note"
signature-note: "Approved electronically in the XYZ system"
```

to replace that empty space with the note text instead, applied
uniformly across every contributor/approver block. Default is
`signature-mode: "line"` (the empty box).

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

Renders a bordered, full-width summary table (a standard CSR
front-matter convention) from a `synopsis:` frontmatter block:

```yaml
synopsis:
  - label: "Objectives"
    value: "..."
  - label: "Methods"
    value: "..."
  - label: "Results"
    value: "..."
```

**Fully flexible, not a fixed field list**: any number of rows, any
labels, in whatever order you write them — this isn't limited to
Objectives/Methods/Results, add or remove rows freely. It's a YAML
*list*, not a plain map (`objectives: "..."`), deliberately: pandoc's Lua
metadata tables don't preserve map key order (confirmed by testing --
iterating a YAML map's keys came back in neither declaration nor
alphabetical order), which would make rows print in an unreliable order
on every render. A list's order is reliable.

A "Title" row (from the top-level `title:` field) is prepended
automatically whenever there's at least one synopsis row. **To turn the
whole section off, omit `synopsis:` from frontmatter entirely** — the
`::: .synopsis :::` div then renders nothing, so a shared shell template
can leave the div marker in unconditionally and let each project's
frontmatter decide.

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

### Page header/footer and page numbering

```yaml
project: "ACME-001"
report_number: "RPT-2026-014"
header-format: "{project} - {report_number}"
```

Everything in this section requires `styling/`'s post-render
`quartifyr-styling apply-layout` step (run automatically by
`r/R/render_report.R` -- see `../../r/README.md`'s "Page header/footer
and page numbering" section and `../../styling/README.md`'s
`apply-layout` entry), since a genuinely independent second header/footer
means adding new *parts* to the docx package, which a Lua filter's
`RawBlock` injection can't do on its own.

**What a plain `quarto render` gives you without that step**:
`header-format:`, `confidentiality:`, and `{{< body-start >}}` are all
inert on their own -- nothing in this extension or `quarto-plus` reads
`header-format:`/`confidentiality:`, so setting them without also running
`apply-layout` has no visible effect at all (no error, no header, no
footer label). `{{< body-start >}}` similarly does nothing by itself; it
just leaves an invisible bookmark for `apply-layout` to find later. What
you *do* get for free, straight from `quarto render --reference-doc
org-reference.docx`, is whatever basic footer the reference-doc itself
was built with -- by default (`styling/styles/default.yaml`'s `footer:`
block) that's a centered, continuous page number across the entire
document, title page included, no restart, no roman numerals. Turn it
off entirely with `footer: {show_page_number: false}` in the style YAML,
or give it static text via `footer: {text: "..."}`; either way, that part
needs no post-processing.

**What `apply-layout` adds**: a two-zone header (the resolved
`header-format:` template flush left, draft/final status flush right --
always shown once a header is enabled, the same "impossible to miss"
precedent as the title page's own status stamp), a confidentiality label
in the footer's left zone (reusing whatever `confidentiality:` is set to
on the title page -- see Title page above -- blank if unset), and, if
`{{< body-start >}}` is present (placed right before your first real body
heading, e.g. `# Introduction`), a three-way page-numbering split: the
title page gets no page number at all, the rest of the front matter (ToC,
list of figures/tables, abbreviations, synopsis, signature pages, ...)
numbers in lowercase roman starting at "i", and the body restarts at
arabic "1". Without `{{< body-start >}}`, `apply-layout` still adds the
header, just with no page-number split (single section throughout).

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

Every table this extension generates (title page info block, synopsis,
signature blocks) is sized with percentage widths (`w:type="pct"`), not
fixed twips — they genuinely span the *current* usable text width, so
changing `page.margins_in` in your style YAML (see
`styling/styles/default.yaml`) doesn't leave a fixed-width table
overflowing the page or falling short of it.
