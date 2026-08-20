# Single source of truth for quartifyr's front-matter fields, shared by
# validate_header() and header_helper() (see R/validate-header.R,
# R/header-helper.R). Keeping one registry -- rather than each function
# hardcoding its own field list/wording -- is what issue #31 means by
# "evergreen by design": add or change a field here once, and both the
# validator and the interactive builder (and their cli/YAML output) pick
# it up automatically.
#
# Every entry mirrors a frontmatter key actually read somewhere in
# inst/extensions/quartifyr/*.lua or inst/python/quartifyr_styling/layout.py
# (see inst/extensions/quartifyr/README.md for the human-readable version
# of the same contract). `path` is a character vector for nested keys
# (e.g. `c("memo", "to")`); `applies_when`/`required`/`recommended` are
# predicates over the parsed frontmatter list so conditional fields (memo
# sub-fields, signature-note, ...) show up only when relevant.

#' Read a (possibly nested) frontmatter value by dotted path
#'
#' `NULL` if any path element is absent -- deliberately permissive, since
#' every caller here treats "absent" as "not set" rather than an error.
#'
#' @param fm Parsed frontmatter list.
#' @param path Character vector of keys, e.g. `c("memo", "to")`.
#' @return The value, or `NULL`.
#' @keywords internal
.header_field_get <- function(fm, path) {
  value <- fm
  for (key in path) {
    if (!is.list(value) || is.null(value[[key]])) {
      return(NULL)
    }
    value <- value[[key]]
  }
  value
}

#' The quartifyr front-matter field registry
#'
#' @return A list of field specs, each a list with `key` (dotted string,
#'   for display), `path` (character vector, for lookup), `label`,
#'   `section`, `applies_when`/`required`/`recommended` (each
#'   `function(fm)`), `description`, and `default` (or `NULL`).
#' @keywords internal
.quartifyr_header_fields <- function() {
  always <- function(fm) TRUE
  has_memo <- function(fm) !is.null(.header_field_get(fm, "memo"))
  no_memo <- function(fm) is.null(.header_field_get(fm, "memo"))
  never <- function(fm) FALSE

  field <- function(key, label, section, description,
                     applies_when = always, required = never, recommended = never,
                     default = NULL, kind = "scalar") {
    list(
      key = key,
      path = strsplit(key, ".", fixed = TRUE)[[1]],
      label = label,
      section = section,
      applies_when = applies_when,
      required = required,
      recommended = recommended,
      description = description,
      default = default,
      # "scalar" fields are prompted for directly by header_helper()'s
      # generic per-field loop; "structured" (nested/list-shaped: address,
      # title-page-extra, synopsis, contributors, approvers, memo itself)
      # and "fixed" (format, filters -- always the same value, never worth
      # prompting for) are handled by their own dedicated code there
      # instead. validate_header() ignores this entirely; it only matters
      # to header_helper()'s interactive flow.
      kind = kind
    )
  }

  list(
    # --- Title page (title_page.lua; inert whenever memo: is set) -------
    field(
      "title", "Title", "Title page",
      "Report title -- shown on the title page and, once any `synopsis:` row exists, prepended there as an automatic \"Title\" row. Mutually exclusive with `memo:` (both set skips the memo cover, with a warning, and renders the title page).",
      required = no_memo
    ),
    field(
      "subtitle", "Subtitle", "Title page",
      "Optional subtitle line under the title.",
      applies_when = no_memo
    ),
    field(
      "report-type", "Report type", "Title page",
      "Optional label (e.g. \"Clinical Study Report\") rendered as part of the title block.",
      applies_when = no_memo
    ),
    field(
      "date", "Date", "Title page",
      "Info-table row. Independent of `memo.date`, which is a separate field for the memo cover.",
      applies_when = no_memo
    ),
    field(
      "lead-scientist", "Lead scientist", "Title page",
      "Info-table row.",
      applies_when = no_memo
    ),
    field(
      "version", "Version", "Title page",
      "Info-table row.",
      applies_when = no_memo
    ),
    field(
      "address", "Address", "Title page",
      "YAML list of address lines (not one string) for a sender address row -- for a fuller To/From/Date/Re cover instead, use `memo:` rather than stacking this on a title page.",
      applies_when = no_memo,
      kind = "structured"
    ),
    field(
      "title-page-extra", "Extra title-page rows", "Title page",
      "YAML list of `{label, value}` rows appended after the named convenience fields, in whatever order written -- a list (not a map) so row order survives pandoc's Lua metadata table, which doesn't preserve map key order. Shared with the memo cover (appended after its To/From/Date/Re/Cc grid).",
      kind = "structured"
    ),
    field(
      "document-status", "Document status", "Title page",
      "Draft/final stamp, always shown (default \"DRAFT\"). `render_report()` always overrides this via Quarto's `-M document-status:` from its own `status` argument, so setting it here only has an effect when rendering directly with `quarto render`.",
      default = "DRAFT"
    ),
    field(
      "logo", "Logo image", "Title page",
      "Path to an image, relative to the .qmd; omitted entirely (no reserved space) when unset. Shared with the memo cover."
    ),
    field(
      "logo-width", "Logo width", "Title page",
      "Any pandoc-recognized image width. Shared with the memo cover.",
      default = "2in"
    ),
    field(
      "logo-align", "Logo alignment", "Title page",
      "\"left\"/\"center\"/\"right\". Shared with the memo cover, but the *default* differs: \"center\" for a title page, \"left\" for a memo cover.",
      default = "center (title page) / left (memo cover)"
    ),
    field(
      "confidentiality", "Confidentiality", "Title page",
      "Info-table row on the title page/memo cover, and (via apply-layout) reused as the rendered footer's confidentiality label."
    ),

    # --- Memo cover (memo_cover.lua; alternative to title:) -------------
    field(
      "memo", "Memo block", "Memo cover",
      "Nested `to`/`from`/`date`/`re`/`cc` block that renders a fax-cover-sheet-style memo cover instead of a formal title page. Mutually exclusive with `title:`.",
      kind = "structured"
    ),
    field(
      "memo.to", "Memo: To", "Memo cover",
      "Only the rows actually set render, in fixed To/From/Date/Re/Cc order.",
      applies_when = has_memo, recommended = has_memo
    ),
    field(
      "memo.from", "Memo: From", "Memo cover",
      "See `memo.to`.",
      applies_when = has_memo, recommended = has_memo
    ),
    field(
      "memo.date", "Memo: Date", "Memo cover",
      "See `memo.to`.",
      applies_when = has_memo, recommended = has_memo
    ),
    field(
      "memo.re", "Memo: Re", "Memo cover",
      "See `memo.to`.",
      applies_when = has_memo, recommended = has_memo
    ),
    field(
      "memo.cc", "Memo: Cc", "Memo cover",
      "Optional.",
      applies_when = has_memo
    ),
    field(
      "memo-heading", "Memo banner text", "Memo cover",
      "Overrides the \"MEMORANDUM\" banner text (rendered uppercased).",
      applies_when = has_memo, default = "MEMORANDUM"
    ),

    # --- Signature page (signature_page.lua) -----------------------------
    field(
      "contributors", "Contributors", "Signature page",
      "Nested `authors`/`reviewers` lists (each entry a `{name, title}` map). Either key, or the whole block, may be omitted.",
      kind = "structured"
    ),
    field(
      "approvers", "Approvers", "Signature page",
      "List of `{name, title}` maps. If both `contributors:` and `approvers:` are omitted, no Signatures page renders at all.",
      kind = "structured"
    ),
    field(
      "signature-mode", "Signature mode", "Signature page",
      "\"line\" (default, a blank signing box) or \"note\" (replace it with `signature-note:` text everywhere) -- e.g. for a validated e-signature workflow.",
      default = "line"
    ),
    field(
      "signature-note", "Signature note text", "Signature page",
      "Required for `signature-mode: \"note\"` to show real text; without it that mode falls back to an empty space.",
      applies_when = function(fm) identical(.header_field_get(fm, "signature-mode"), "note"),
      required = function(fm) identical(.header_field_get(fm, "signature-mode"), "note")
    ),

    # --- Synopsis (synopsis.lua) -----------------------------------------
    field(
      "synopsis", "Synopsis rows", "Synopsis",
      "YAML list of `{label, value}` rows (any labels, any order -- not fixed to Objectives/Methods/Results). A \"Title\" row is prepended automatically. Omit entirely to turn the whole section off. `value:` may also be a list mixing text paragraphs and `{image: ..., width: ...}` entries (bare filenames within `OUTPUTS/figures/`, resolved via reportifyr's `{rpfy}:` mechanism).",
      kind = "structured"
    ),
    field(
      "synopsis-style", "Synopsis style", "Synopsis",
      "Layout of the synopsis table -- see the pkgdown \"Quarto extension\" article for the available values.",
      applies_when = function(fm) !is.null(.header_field_get(fm, "synopsis"))
    ),

    # --- Appendices (appendix.lua) ----------------------------------------
    field(
      "appendix-numbering", "Appendix numbering style", "Appendices",
      "\"alphabetic\" (default, A/B/C), \"arabic\" (1/2/3), or \"roman\" (I/II/III, uppercase only). An unrecognized value falls back to \"alphabetic\" with a render-time warning.",
      default = "alphabetic"
    ),
    field(
      "caption-style-figure", "Figure caption style", "Appendices",
      "Paragraph style name applied to figure captions (default \"Caption\").",
      default = "Caption"
    ),
    field(
      "caption-style-table", "Table caption style", "Appendices",
      "Paragraph style name applied to table captions (default \"Caption\").",
      default = "Caption"
    ),

    # --- Bibliography (bibliography.lua) -----------------------------------
    field(
      "bibliography", "Bibliography file", "Bibliography",
      "Path to a .bib file. Enables citeproc; standard Quarto/pandoc frontmatter, nothing quartifyr-specific beyond the `csl:`/`link-citations:` defaults below."
    ),
    field(
      "csl", "Citation style", "Bibliography",
      "Defaults to this extension's bundled NLM/Vancouver style whenever `bibliography:` is set and this isn't -- only fills the gap, never overrides an explicit choice.",
      applies_when = function(fm) !is.null(.header_field_get(fm, "bibliography")),
      default = "bundled nlm.csl"
    ),
    field(
      "link-citations", "Hyperlink citations", "Bibliography",
      "Defaults to `true` whenever `bibliography:` is set and this isn't.",
      applies_when = function(fm) !is.null(.header_field_get(fm, "bibliography")),
      default = TRUE
    ),

    # --- Page header/footer (apply-layout, layout.py) ----------------------
    field(
      "header-format", "Page header template", "Page header/footer",
      "`{placeholder}` template resolved against other frontmatter values plus `{status}`; every placeholder must name a real top-level frontmatter key. Inert on a plain `quarto render` -- only takes effect via `apply-layout`/`render_report()`."
    ),
    field(
      "crossref-hyperlinks", "Cross-reference hyperlinks", "Page header/footer",
      "`true` (default, always hyperlinked), `false` (never), or `\"same-page\"` (opt-in, needs the separate `resolve_same_page_crossrefs` post-processing step -- see `render_report()`).",
      default = TRUE
    ),

    # --- Document structure (plain Quarto/pandoc options) -------------------
    field(
      "number-sections", "Number sections", "Document structure",
      "Plain pandoc option: numbers real `#`/`##` body headings as static text (\"1.\", \"1.1\", ...). Independent of the raw-OOXML title/signature/appendix headings this extension injects, which are never touched by it."
    ),
    field(
      "indent-headers", "Indent headers", "Document structure",
      "quarto-plus option: set to `false` to drop the leading tab quarto-plus's header.lua inserts before every heading (meant to line up with `number-sections:`' own numbers) -- typically wanted alongside `number-sections: false` on a memo.",
      applies_when = has_memo
    ),
    field(
      "format", "Output format", "Document structure",
      "Must include `docx` -- this extension only targets Word output.",
      required = always,
      kind = "fixed"
    ),
    field(
      "filters", "Quarto filters", "Document structure",
      "Must list `quartifyr` (and, for ToC/List of Figures/List of Tables/abbreviations/fig_caption/tbl_caption, `quarto-plus`) or none of this extension's frontmatter has any effect. quartifyr's own `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables` combined lists and scoped caption shortcodes don't need `quarto-plus` unless a document also uses its continuous `fig_caption`/`tbl_caption`.",
      required = always,
      kind = "fixed"
    )
  )
}
