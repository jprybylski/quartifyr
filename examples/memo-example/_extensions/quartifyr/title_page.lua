-- Builds a standardized, per-project title page from YAML frontmatter and
-- prepends it as the document's first page.
--
-- Pandoc's docx writer emits its own automatic title-block paragraph(s)
-- whenever `title:` is set in the frontmatter. We read that metadata for
-- our own layout, then null it out so pandoc's built-in title block never
-- renders alongside ours.
--
-- To satisfy "the ToC should include the title page" *without* the entry
-- just duplicating the document's own title text: a genuinely
-- `Heading1`-styled paragraph, carrying the literal text "Title Page",
-- independent of the real, visible title paragraph (which keeps its own
-- actual title text, unchanged, purely for its on-page look). Word's ToC
-- field scans outline levels 1-3 by default (present unconditionally,
-- not something quartifyr adds), so a genuine Heading-1 paragraph is
-- picked up automatically -- no `apply-layout` step needed for this, and
-- it shows up in Word's Navigation Pane for free too, same as any other
-- heading. What makes it invisible on the page itself is *ordinary*
-- run formatting -- 1pt size, white text color -- not any kind of
-- "hidden" flag.
--
-- Two earlier attempts relied on Word's various "hidden content"
-- mechanisms instead, and both failed in real Word (not just this repo's
-- own testing -- confirmed directly against the user's own Word install):
-- a `<w:vanish/>`-hidden paragraph showed up, visibly, on the title page
-- regardless of which style drove the ToC entry (`<w:vanish/>` does not
-- reliably suppress on-screen display the way its name suggests); a `TC`
-- (table-of-contents-entry) field correctly fed the ToC (confirmed: after
-- a manual field recalculation, the ToC entry was correct) but Word
-- persistently rendered the field's own raw code, not nothing, right on
-- the title page -- a field with no visible result content apparently
-- can't be given a *reliably* invisible on-screen appearance through
-- field mechanics alone (adding a `separate` fldChar marker and
-- `w:dirty="true"` -- both otherwise-legitimate fixes -- didn't change
-- this). Tiny, white, ordinary text sidesteps both problems: there's no
-- special "hidden" semantics for Word to second-guess or show an
-- editing aid for -- it's just text that happens to be too small and
-- the same color as the page to see. A third round confirmed
-- `<w:vanish/>` is worth avoiding entirely here, not just redundant:
-- stacked on top of the tiny/white run (belt-and-suspenders, reasoned to
-- be harmless), it made Word's outline scan skip the paragraph
-- altogether -- an all-vanish paragraph is apparently treated as having
-- no heading content at all, so the ToC entry vanished along with it.
--
-- The info block (Date/Lead Scientist/Version/Confidentiality/...) is a
-- full-width, percentage-sized (w:type="pct") bordered table -- not fixed
-- twips -- so it genuinely spans the *current* usable text width
-- regardless of the page margins configured in the docx reference-doc
-- (see styling/styles/*.yaml's page.margins_in).
--
-- Flexibility: date/lead-scientist/version/confidentiality are named
-- convenience fields (simpler to write than a list for the common case),
-- rendered first, in that fixed order, when present. `title-page-extra:`
-- then appends any number of additional label/value rows after them, in
-- whatever order they're written -- this is a YAML *list*, not a plain
-- map, deliberately: pandoc's Lua metadata tables don't preserve map key
-- order (confirmed by testing), which would make extra fields print in an
-- unreliable order every render. So the title page is fully open-ended
-- (any label, any value, any count) via title-page-extra, just not via
-- bare top-level `foo: bar` keys, which can't be told apart from
-- unrelated frontmatter and wouldn't have a reliable order anyway.

local utils = require("utils")

-- `address:` needs multi-line support (street/suite/city-state-zip), but
-- pandoc.utils.stringify() collapses ALL line breaks to spaces (confirmed
-- by testing -- a YAML `|` block scalar comes back as one space-joined
-- line), so a literal multi-line string can never work here. Accept a
-- YAML *list* of lines instead (reliable, and consistent with how this
-- extension already handles anything needing order -- see
-- title-page-extra/synopsis), falling back to a plain single-line string
-- when a list isn't used.
local function stringify_lines(meta_val)
  if meta_val == nil then
    return nil
  end
  if pandoc.utils.type(meta_val) == "List" then
    local lines = {}
    for _, line in ipairs(meta_val) do
      local s = pandoc.utils.stringify(line)
      if s ~= "" then
        table.insert(lines, s)
      end
    end
    if #lines == 0 then
      return nil
    end
    return table.concat(lines, "\n")
  end
  local s = pandoc.utils.stringify(meta_val)
  if s == "" then
    return nil
  end
  return s
end

local function stringify_or_nil(meta_val)
  if meta_val == nil then
    return nil
  end
  local s = pandoc.utils.stringify(meta_val)
  if s == "" then
    return nil
  end
  return s
end

local doc_title = nil
local doc_subtitle = nil
local report_type = nil
local document_status = nil
local field_rows = {} -- list of {label=, value=}, in display order
local logo_path = nil
local logo_width = "2in"
local logo_align = "center"

local function styled_paragraph(style, text)
  return string.format(
    [[
  <w:p>
    <w:pPr><w:pStyle w:val="%s"/></w:pPr>
    <w:r><w:t xml:space="preserve">%s</w:t></w:r>
  </w:p>
  ]],
    utils.escape_xml(style),
    utils.escape_xml(text)
  )
end

-- See the file-header comment on why this exists: a genuinely
-- `Heading1`-styled paragraph (real outline level, picked up by Word's
-- native ToC field automatically) whose text is invisible on the page
-- itself purely through ordinary formatting -- 1pt size (the smallest
-- OOXML unit that stays valid), white color -- not a "hidden" flag of
-- any kind. `<w:vanish/>` was tried too, belt-and-suspenders, but
-- confirmed in real Word to be actively harmful here, not just
-- redundant: an all-vanish paragraph is excluded from the ToC's outline
-- scan entirely (Word apparently treats "no visible content" as "no
-- heading here"), which defeats the entire point. Tiny/white alone
-- (no vanish) is both invisible on the page *and* still a real,
-- present paragraph as far as outline scanning is concerned.
local function tiny_heading_paragraph(style, text)
  return string.format(
    [[
  <w:p>
    <w:pPr>
      <w:pStyle w:val="%s"/>
      <w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/>
    </w:pPr>
    <w:r>
      <w:rPr><w:sz w:val="2"/><w:szCs w:val="2"/><w:color w:val="FFFFFF"/></w:rPr>
      <w:t xml:space="preserve">%s</w:t>
    </w:r>
  </w:p>
  ]],
    utils.escape_xml(style),
    utils.escape_xml(text)
  )
end

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)
      doc_subtitle = stringify_or_nil(meta.subtitle)
      report_type = stringify_or_nil(meta["report-type"])
      -- Always shown (unlike the other optional fields below): the
      -- draft/final state is meant to be impossible to miss, and lines up
      -- with reportifyr's own report/draft vs report/final convention
      -- (see r/README.md's orchestration driver docs).
      document_status = stringify_or_nil(meta["document-status"]) or "DRAFT"
      logo_path = stringify_or_nil(meta.logo)
      logo_width = stringify_or_nil(meta["logo-width"]) or "2in"
      logo_align = stringify_or_nil(meta["logo-align"]) or "center"
      if logo_align ~= "left" and logo_align ~= "center" and logo_align ~= "right" then
        quarto.log.warning(
          "title_page.lua: logo-align must be 'left', 'center', or 'right' (got '"
            .. logo_align
            .. "'); defaulting to 'center'"
        )
        logo_align = "center"
      end

      local report_date = stringify_or_nil(meta.date)
      local lead_scientist = stringify_or_nil(meta["lead-scientist"])
      local report_version = stringify_or_nil(meta.version)
      local confidentiality = stringify_or_nil(meta.confidentiality)

      if report_date then
        table.insert(field_rows, { label = "Date", value = report_date })
      end
      if lead_scientist then
        table.insert(field_rows, { label = "Lead Scientist", value = lead_scientist })
      end
      if report_version then
        table.insert(field_rows, { label = "Version", value = report_version })
      end
      if confidentiality then
        table.insert(field_rows, { label = "Confidentiality", value = confidentiality })
      end

      local address = stringify_lines(meta["address"])
      if address then
        table.insert(field_rows, { label = "Address", value = address })
      end

      if meta["title-page-extra"] then
        for _, entry in ipairs(meta["title-page-extra"]) do
          local label = stringify_or_nil(entry.label)
          local value = stringify_or_nil(entry.value)
          if label and value then
            table.insert(field_rows, { label = label, value = value })
          end
        end
      end

      -- Prevent pandoc's own automatic title-block from also rendering.
      meta.title = nil
      meta.subtitle = nil
      meta.author = nil
      meta.date = nil

      return meta
    end,
  },
  {
    Pandoc = function(doc)
      if not doc_title then
        quarto.log.warning(
          "title_page.lua: no 'title' set in frontmatter; skipping title page generation"
        )
        return doc
      end

      -- Mixed list of pandoc blocks (RawBlock strings get accumulated and
      -- flushed as a group; the logo, when present, is a genuine
      -- pandoc.Image block spliced in between -- see utils.logo_block()'s
      -- comment for why it can't just be more raw OOXML).
      local blocks = {}
      local ooxml_parts = {}

      local function flush_ooxml()
        if #ooxml_parts > 0 then
          table.insert(blocks, utils.raw_block(table.concat(ooxml_parts, "\n")))
          ooxml_parts = {}
        end
      end

      if logo_path then
        table.insert(blocks, utils.logo_block(logo_path, logo_width, logo_align))
      end

      if report_type then
        table.insert(ooxml_parts, styled_paragraph("Subtitle", string.upper(report_type)))
      end

      table.insert(ooxml_parts, styled_paragraph("Title", doc_title))
      table.insert(ooxml_parts, tiny_heading_paragraph("Heading1", "Title Page"))

      if doc_subtitle then
        table.insert(ooxml_parts, styled_paragraph("Subtitle", doc_subtitle))
      end

      table.insert(ooxml_parts, utils.status_box(document_status))

      table.insert(ooxml_parts, utils.spacer_paragraph())

      if #field_rows > 0 then
        table.insert(ooxml_parts, utils.field_table(field_rows))
      end

      table.insert(ooxml_parts, utils.page_break_paragraph())
      table.insert(ooxml_parts, utils.front_matter_start_bookmark())

      flush_ooxml()

      -- Insert the whole ordered `blocks` list at the front of the
      -- document, in one pass, by inserting each element at position 1
      -- starting from the *last* one -- each insert pushes the prior
      -- ones down, so working backwards yields the correct final order.
      for i = #blocks, 1, -1 do
        table.insert(doc.blocks, 1, blocks[i])
      end

      return doc
    end,
  },
}
