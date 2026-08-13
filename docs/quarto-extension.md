---
layout: default
title: Quarto Extension
nav_order: 4
---

# Quarto extension

`_extensions/quartifyr/` is the shell-generation piece: a dynamic title
page (with a draft/final status stamp), a fax-cover-sheet-style memo
cover page, contributor/approval signature pages, a synopsis summary
table, and numbered appendices — layered on top of
[`quarto-plus`](https://github.com/A2-ai/quarto-plus)'s ToC/List of
Figures/List of Tables/abbreviations/caption machinery. Install both:

```bash
quarto add A2-ai/quarto-plus
quarto add jprybylski/quartifyr
```

## Quick look

Rendering the shell needs nothing but Quarto and a reference-doc — no R,
no Python, no `reportifyr`. `{rpfy}:` placeholders and `\gls{}`
abbreviation markers stay unresolved in the output; that's expected,
pass 2 hasn't run.

<img src="{{ '/assets/img/quarto-only.gif' | relative_url }}" alt="Terminal recording of quarto render building a report shell from report.qmd and a committed org-reference.docx, producing a styled docx with title page, signature pages, and unresolved {rpfy}: placeholders" width="700" loading="lazy">

## Frontmatter

```yaml
---
title: "Population PK Analysis of Compound X"
subtitle: "Final Report"
report-type: "Clinical Study Report"
document-status: "draft"   # or "final"
date: "2026-08-11"
lead-scientist: "Jane Doe, PharmD"
version: "1.0"
confidentiality: "Confidential — Do Not Distribute"
logo: "assets/logo.png"          # optional
project: "ACME-001"               # feeds header-format, not shown on its own
report_number: &report_number "RPT-2026-014"   # feeds header-format below
header-format: "{project} - {report_number}"   # optional
title-page-extra:
  - label: "Sponsor"
    value: "Acme Pharma"
  - label: "Report Number"
    value: *report_number            # reuses report_number above, not retyped
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
  - label: "Objectives"
    value: "..."
format: docx
filters:
  - quarto-plus
  - quartifyr
---
```

All fields except `title` are optional — the title page only renders the
rows that are actually set. `document-status` is the exception: it's
*always* shown as a bordered, bold, uppercase stamp under the title,
defaulting to `DRAFT` if omitted.

`title-page-extra:`/`synopsis:`/`address:` are YAML **lists**, not maps
— deliberate, since pandoc's Lua metadata tables don't preserve map key
order (confirmed by testing), so a list is what keeps row order reliable
across renders.

A value that's also used elsewhere (like `report_number` above, reused
by `header-format:`) doesn't need to be written out twice: anchor it
once (`&report_number`) and alias it (`*report_number`) into the
`title-page-extra` row, plain YAML resolved before Quarto/pandoc/Lua see
the data. This is *not* the `{{< meta ... >}}` shortcode — that only
substitutes inside document body content, not frontmatter itself.

## Memo cover page

An alternative to the title page for short, loose-structure documents —
a left-aligned `MEMORANDUM` banner over a To/From/Date/Re/Cc grid,
instead of a centered title/subtitle/info-table title page:

```yaml
memo:
  to: "Jane Doe, CFO"
  from: "John Smith, Controller"
  date: "2026-08-12"
  re: "Q3 Budget Review"
  cc: "Finance Committee"    # optional
```

Activates only when `memo:` is present — never set `title:` on a memo
project. See [`examples/memo-example/`](https://github.com/jprybylski/quartifyr/tree/main/examples/memo-example)
for a complete, minimal reference project built this way, and its
rendered output on the [Examples](examples.html) page.

## Signature page

`contributors:` (`authors:`/`reviewers:`) and top-level `approvers:`
render a single "Signatures" section — one heading, one ToC entry. Each
person gets a bordered signature block: signing space, printed name,
title, and role. When physical signatures aren't the actual workflow
(e.g. a validated e-signature system):

```yaml
signature-mode: "note"
signature-note: "Approved electronically in the XYZ system"
```

## Synopsis

```markdown
Synopsis

::: .synopsis
:::
```

Renders a bordered, full-width summary table from a `synopsis:`
frontmatter block — any number of rows, any labels, in whatever order
you write them. A "Title" row is prepended automatically. Omit
`synopsis:` entirely to turn the section off — the div then renders
nothing.

`value:` also accepts a YAML list instead of a plain string, letting a
row mix paragraphs and an inline figure:

```yaml
synopsis:
  - label: "Results"
    value:
      - "Peak concentrations are summarized in Figure 1."
      - image: "summary-plot.png"
        width: "3in"
```

`image:` is a bare filename within `OUTPUTS/figures/` — it emits a
`{rpfy}:` magic string, so the figure only actually appears after pass 2
fills it in.

## Bibliography / references

Ordinary Quarto/pandoc citeproc support — nothing quartifyr-specific
beyond the standard frontmatter field:

```yaml
bibliography: references.bib
```

Citation style defaults to NLM/Vancouver (numbered, bracketed —
`[1]`, `[2]`, ...) via a bundled `nlm.csl`. To control where the
generated reference list lands (by default citeproc appends it to the
very end, after any appendices), add a heading and an empty `{#refs}`
Div at the location you want instead:

```markdown
::: {custom-style="Heading 1"}
References
:::

::: {#refs}
:::
```

## Appendices

{% raw %}
```
{{< appendix "StatsAppendix" "Statistical Analysis Details" >}}

... appendix body ...
```
{% endraw %}

Each `{% raw %}{{< appendix "BookmarkId" "Title" >}}{% endraw %}` renders an "Appendix A: ...",
"Appendix B: ..." heading using a native Word `SEQ Appendix \* ALPHABETIC`
field — reordering, adding, or removing appendices never requires manual
relettering, just a field recalculation. Reference one from body text
with `{% raw %}{{< appendix_crossref "BookmarkId" >}}{% endraw %}`.

## Figures, tables, and cross-references

`quarto-plus`'s own machinery, not something this extension adds:

{% raw %}
```
{{< fig_caption "FigConcTime" "Concentration-time profile" >}}
{{< tbl_caption "TblPkSummary" "Per-subject PK summary statistics" >}}

See {{< crossref "TblPkSummary" >}} for the full profile.
```
{% endraw %}

`crossref-hyperlinks:` in frontmatter controls whether a resolved
cross-reference is a clickable hyperlink, document-wide:

```yaml
crossref-hyperlinks: true          # default -- always a hyperlink
crossref-hyperlinks: false         # never a hyperlink
crossref-hyperlinks: "same-page"   # hyperlink only when the target is on a different page
```

`true`/`false` are handled by `quartifyr-styling apply-layout`.
`"same-page"` needs a further opt-in post-`reportifyr` step — see
[Styling](styling.html).

## Page header/footer and page numbering

```yaml
project: "ACME-001"
report_number: "RPT-2026-014"
header-format: "{project} - {report_number}"
```

Everything here requires `quartifyr-styling apply-layout` (run
automatically by `render_report()`) — a genuinely independent second
header/footer means adding new *parts* to the docx package, which a Lua
filter's `RawBlock` injection can't do. Without that step,
`header-format:`, `confidentiality:`, and `{% raw %}{{< body-start >}}{% endraw %}` are all
inert: no error, just no visible effect. See [Styling](styling.html)'s
`apply-layout` section for what it adds.

## A pStyle gotcha (if you're extending this extension)

`<w:pStyle w:val="...">` must reference a style's **ID** (e.g.
`Heading1`, `TableGrid` — no spaces), not its **display name**
(`Heading 1`, `Table Grid`). Word/LibreOffice render the display-name
form visually fine via a fallback lookup, which makes this easy to miss
— but Word's ToC field silently fails to recognize such a paragraph as a
heading at all, and a wrong table style reference silently drops the
reference-doc's customized borders/shading.

**The opposite is true from the `.qmd` body.** Pandoc's `custom-style`
Div attribute matches by a style's **name** (`Heading 1`, with the
space), not its ID. Get this backwards and pandoc doesn't error — it
silently fabricates a new, blank style with that literal name, so the
text renders in plain body formatting with no indication anything's
wrong.

## Styling

Pair with a docx `reference-doc:` generated by [`styling/`](styling.html)
so the `Title`/`Subtitle`/`Heading N` styles this filter emits actually
carry your org's fonts/colors.
