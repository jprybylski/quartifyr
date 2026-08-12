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
logo-align: "center"              # optional, "left"/"center"/"right", default "center"
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
`"2in"`; any pandoc-recognized image width, e.g. `"150px"`). `logo-align:`
controls its horizontal alignment (`"left"`, `"center"`, or `"right"`;
default `"center"`).

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

The ToC's entry for the title page reads "Title Page", not the document's
actual title text -- a genuinely `Heading 1`-styled paragraph, independent
of the real, visible `Title`-styled paragraph that still shows the
report's own title. Word's ToC field scans outline levels 1-3 by default,
so this needs no per-project configuration and no `apply-layout` step --
it's automatic whenever a title page renders, exactly like every other
real heading, and shows up in Word's Navigation Pane for free too. What
makes it invisible on the page itself is ordinary formatting (1pt size,
white text) rather than any "hidden" flag -- confirmed in real Word (not
just this repo's own testing) that both a `<w:vanish/>`-hidden paragraph
and a `TC` (table-of-contents-entry) field -- two earlier attempts --
reliably showed *something* on the title page regardless of which
mechanism drove it.

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

### Signature page

Right after the title page, `contributors:` (with `authors:`/`reviewers:`
lists) and a separate top-level `approvers:` list render a single
"Signatures" section — one heading, one ToC entry, covering both groups.
"Contributors" and "Approvers" appear within that page as smaller bold
sub-labels (not headings of their own, so they don't add extra ToC
entries) directly above their respective blocks; either sub-label is
omitted entirely if its key isn't set. Each person gets their own
full-width, bordered signature block: a blank signing space, printed
name, and (for contributors) title stacked in one column, with a role
label ("Author"/"Reviewer") spanning beside it. Approvers use the same
layout, but since "Approvers" is already the sub-label, the slot next to
their signing space shows their actual job title instead of a redundant
"Approver" tag. Either key (`contributors:`, `approvers:`) can be omitted
if not needed — if both are omitted, no Signatures page renders at all.

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

There's no forced page break between the Contributors and Approvers
sub-sections — with only a handful of people they'll naturally share a
page; Word just flows onto a new page once the content no longer fits.
The only explicit break this filter inserts is right after the title page
(before "Signatures") and once more after the whole Signatures page
(before the rest of the document).

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

**Multi-line values, and values with a figure**: `value:` also accepts a
YAML list instead of a plain string — each string item becomes its own
paragraph within the cell, and an `{image: "...", width: "..."}` item
embeds a figure inline, in whatever order they're written:

```yaml
synopsis:
  - label: "Results"
    value:
      - "Peak concentrations are summarized in Figure 1."
      - image: "summary-plot.png"
        width: "3in"   # optional, defaults to 3in
```

`image:` is a **bare filename within `OUTPUTS/figures/`**, not a path
that includes that directory — the same convention a `{rpfy}:` figure
placeholder in the qmd body already uses. This isn't a shortcut for
embedding an arbitrary picture: it emits a `{rpfy}:filename.png<width:
N>` magic string into the cell, so the figure only actually appears
after `reportifyr::build_report()` (pass 2) fills it in from
`OUTPUTS/figures/` — a plain `quarto render` alone shows the literal
`{rpfy}:...` text, exactly like any other figure placeholder in this
project. Getting the filename convention wrong doesn't error -- reportifyr
just logs a "Figure file not found" warning and leaves the cell showing
the raw magic string (confirmed by making this exact mistake while
building this feature: writing the full relative path instead of the
bare filename silently produced nothing).

Routing through `{rpfy}:` rather than embedding a picture directly
(which is what an earlier version of this feature did) is deliberate:
`reportipyr` (the Python package `reportifyr::build_report()` drives)
has dedicated, first-class support for magic strings inside table
cells — confirmed by reading its source — so the figure genuinely lands
inside the cell, carries the same provenance alt text (a content hash
from the artifact's `_metadata.json` sidecar) every other `{rpfy}:`
figure gets, and — since it's never captioned via `{{< fig_caption >}}`
— stays excluded from `quarto-plus`'s List of Figures, the same as
before.

`reportifyr::build_report()` also auto-inserts a Source/Notes/
Abbreviations footnote block for every `{rpfy}:` figure, cell figures
included — this extension can't turn that off (and doesn't try to;
the footnote *is* the "appropriate reportifyr-generated metadata"
this feature is for). What it does control is *where that footnote
lands*: reportifyr groups it per Word table element, inserting one
combined footnote immediately after the whole table — not attached to
any specific cell. A synopsis row containing a `{rpfy}:` magic string
therefore gets its own dedicated single-row table rather than sharing
one with every other row, so the footnote lands immediately after
*that row alone* (confirmed by rendering: it appears directly below
the row's own table, not after the whole synopsis). Multiple figures
in the same row still combine into one footnote, correctly, since
they share that row's table; rows with no magic string keep sharing a
table with their neighbors, so a plain text-only synopsis still
renders as a single table with no fragmentation.

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

### Figures, tables, and cross-references

Auto-numbering and cross-referencing for figures and tables is already
available — it's `quarto-plus`'s own machinery, not something this
extension adds on top:

```
{{< fig_caption "FigConcTime" "Concentration-time profile" >}}
{{< tbl_caption "TblPkSummary" "Per-subject PK summary statistics" >}}

See {{< crossref "TblPkSummary" >}} for the full profile.
```

The first argument is a bookmark ID `crossref` looks up by (it must start
with `Figure`/`Fig` or `Table`/`Tbl`, case-insensitive, for `quarto-plus`
to know which counter it belongs to) — **not** the displayed number.
Deliberately spelled without a digit above (`FigConcTime`, not `Figure1`):
the actual "Figure 1"/"Table 1" text comes entirely from a live Word `SEQ
Figure`/`SEQ Table` field, so reordering/adding/removing figures or tables
renumbers correctly on the next field recalculation regardless of what the
bookmark ID says — an ID like `Figure1` would still work, but reads as a
manually-typed number even though it isn't one. `crossref` itself resolves
to that live number via a `REF ... \h` field back to the bookmark. This
extension's own `appendix_crossref` (above) emits the identical `REF ...
\h` shape for appendix references, reimplemented rather than reused only
because `quarto-plus`'s version is hardcoded to the "Figure"/"Table" SEQ
names.

The `\h` switch is what makes a resolved cross-reference a clickable
hyperlink — Word does this unconditionally by default, regardless of
whether the reference and its target end up on the same page or ten pages
apart. `crossref-hyperlinks:` in the shell `.qmd`'s frontmatter controls
this, document-wide, for every `crossref`/`appendix_crossref` alike:

```yaml
crossref-hyperlinks: true          # default -- always a hyperlink
crossref-hyperlinks: false         # never a hyperlink
crossref-hyperlinks: "same-page"   # hyperlink only when the target is on a different page
```

`true`/`false` are handled entirely by `quartifyr-styling apply-layout`
(`../../styling/quartifyr_styling/layout.py`), which adds or strips the
`\h` switch directly on the rendered docx's `REF` fields rather than
patching each shortcode separately, so it applies uniformly no matter
which extension emitted the field.

`"same-page"` needs an extra step, and can't be resolved by `apply-layout`
alone: real page numbers don't exist yet at that point — `apply-layout`
runs on the pass-1 shell, before reportifyr has filled in the actual
content pagination depends on. So `apply-layout` only *marks* each
same-page crossref (a small bookmark next to its `REF` field) and leaves
it hyperlinked, the safe fallback if nothing resolves the mark later. The
actual decision happens in a separate, **opt-in** post-reportifyr step —
`quartifyr-styling resolve-same-page-crossrefs` (see
`../../styling/README.md` and `../../r/README.md`'s `render_report()`
`resolve_same_page_crossrefs` argument) — which reads each marked
crossref's and its target's real page number via headless LibreOffice
(read-only; it never re-saves the docx itself) and strips `\h` wherever
they match. It's off by default and inherits the same intermittent-hang
behavior already documented for `recalculate-fields` (see
`../../styling/quartifyr_styling/same_page_crossrefs.py`'s docstring) —
an earlier version of this mode instead tried to push the whole
comparison into a live nested Word field so Word/LibreOffice would
resolve it on its own; abandoned after confirming, via a real
headless-LibreOffice round-trip, that it silently corrupts the field
rather than evaluating it. If you never run
`resolve-same-page-crossrefs`, a `"same-page"` document just stays
hyperlinked everywhere, same as `true`.

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
heading, e.g. `# Introduction`), a page-numbering split: the whole front
matter (title page through abbreviations) numbers in lowercase roman
starting at "i" on the title page itself, and the body restarts at arabic
"1". Without `{{< body-start >}}`, `apply-layout` still adds the header,
just with no page-number split (single section throughout).

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

**The opposite is true from the `.qmd` body.** Pandoc's `custom-style`
Div attribute (used, for example, to give a front-matter section label
like "Synopsis" the real Heading 1 look without making it a genuine
numbered heading — see `examples/demo-report/report.qmd`) matches by a
style's **name** (`Heading 1`, with the space), not its ID (`Heading1`).
Get this backwards and pandoc doesn't error or fall back to the real
style — it silently fabricates a new, blank style with that literal name,
based on Normal, so the text renders in plain body formatting with no
indication anything's wrong (confirmed by making this exact mistake:
`custom-style="Heading1"` produced a style with no `<w:rPr>`/`<w:pPr>` at
all, while `custom-style="Heading 1"` correctly resolved to the
reference-doc's real bold/16pt Heading 1). If a `custom-style` block
doesn't visually match same-style content elsewhere in the document,
this mismatch is the first thing to check.

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
