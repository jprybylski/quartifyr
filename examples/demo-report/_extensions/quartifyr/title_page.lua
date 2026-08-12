-- Builds a standardized, per-project title page from YAML frontmatter and
-- prepends it as the document's first page.
--
-- Pandoc's docx writer emits its own automatic title-block paragraph(s)
-- whenever `title:` is set in the frontmatter. We read that metadata for
-- our own layout, then null it out so pandoc's built-in title block never
-- renders alongside ours.
--
-- To satisfy "the ToC should include the title page": the title line below
-- uses Word's built-in "Title" style, which quarto-plus's table_of_contents
-- filter can pick up via its documented `toc-style-map` frontmatter option
-- (map "Title" to level 1) -- no changes to quarto-plus needed.
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

local LABEL_PCT = 1500 -- 30%
local VALUE_PCT = 3500 -- 70%

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

local function spacer_paragraph()
  return [[<w:p/>]]
end

-- A bordered box rather than a colored watermark, so DRAFT/FINAL stays
-- prominent without breaking the black/Times-New-Roman "professional
-- industrial" default look (see styling/styles/default.yaml).
local function status_box(text)
  return string.format(
    [[
  <w:p>
    <w:pPr>
      <w:pBdr>
        <w:top w:val="single" w:sz="8" w:space="6" w:color="000000"/>
        <w:left w:val="single" w:sz="8" w:space="6" w:color="000000"/>
        <w:bottom w:val="single" w:sz="8" w:space="6" w:color="000000"/>
        <w:right w:val="single" w:sz="8" w:space="6" w:color="000000"/>
      </w:pBdr>
      <w:jc w:val="center"/>
      <w:spacing w:before="120" w:after="240"/>
    </w:pPr>
    <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>
  </w:p>
  ]],
    utils.escape_xml(string.upper(text))
  )
end

-- Splits on literal newlines (e.g. from a YAML block scalar like
-- `address: |` for a multi-line address) into separate runs joined by
-- <w:br/>, so multi-line values render as real line breaks within one
-- cell/paragraph rather than one run with embedded "\n" characters
-- (which OOXML would just ignore/collapse).
local function multiline_runs(value)
  local runs = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    if #runs > 0 then
      table.insert(runs, "<w:br/>")
    end
    table.insert(runs, string.format('<w:t xml:space="preserve">%s</w:t>', utils.escape_xml(line)))
  end
  return table.concat(runs, "")
end

local function table_row(label, value)
  return string.format(
    [[
    <w:tr>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        <w:p><w:r>%s</w:r></w:p>
      </w:tc>
    </w:tr>
  ]],
    LABEL_PCT,
    utils.escape_xml(label),
    VALUE_PCT,
    multiline_runs(value)
  )
end

local function field_table(rows)
  local row_xml = {}
  for _, r in ipairs(rows) do
    table.insert(row_xml, table_row(r.label, r.value))
  end
  -- "TableNormal" (display name "Normal Table"), not "TableGrid" --
  -- genuinely borderless (confirmed: no tblBorders/shading in its style
  -- definition at all), unlike synopsis/signature tables which keep
  -- visible borders on purpose. tblLook firstRow="0" additionally
  -- prevents Word's default bold/shaded first-row treatment (omitting
  -- tblLook entirely was the actual bug: Word applied it by default,
  -- making the "Date" row look like an unwanted header row).
  return string.format(
    [[
  <w:tbl>
    <w:tblPr>
      <w:tblStyle w:val="TableNormal"/>
      <w:tblW w:w="5000" w:type="pct"/>
      <w:tblLook w:val="0000" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
    </w:tblPr>
    <w:tblGrid>
      <w:gridCol/>
      <w:gridCol/>
    </w:tblGrid>
    %s
  </w:tbl>
  ]],
    table.concat(row_xml, "\n")
  )
end

local function page_break_paragraph()
  return [[<w:p><w:r><w:br w:type="page"/></w:r></w:p>]]
end

-- An empty bookmarked paragraph marking where the title page ends and the
-- rest of the front matter (ToC, list of figures/tables, abbreviations,
-- synopsis, signature pages, ...) begins -- read by
-- styling/quartifyr_styling/layout.py's `apply-layout` step to give the
-- title page its own OOXML section, separate from the rest of the front
-- matter, so the title page alone can be excluded from page numbering
-- while the rest of the front matter numbers in roman numerals. Emitted
-- automatically (unlike `{{< body-start >}}`, which marks the front
-- matter/body boundary and has no fixed position an author didn't
-- specify) since the title page's end is always exactly here, right
-- after its own page break.
local function front_matter_start_bookmark()
  return [[
  <w:p>
    <w:bookmarkStart w:id="800002" w:name="quartifyr-front-matter-start"/>
    <w:bookmarkEnd w:id="800002"/>
  </w:p>
  ]]
end

-- Wraps an accumulated OOXML string as a single raw block, for mixing
-- into a list alongside genuine pandoc blocks (e.g. the logo image
-- below).
local function raw_block(ooxml)
  return pandoc.RawBlock("openxml", ooxml)
end

-- A real pandoc.Image, not raw OOXML: embedding an image (the relationship
-- linking to the actual media file) is package-level plumbing a Lua
-- filter's RawBlock injection can't do -- only pandoc's own writer can,
-- which means the image has to travel through the pandoc AST as a genuine
-- Image element, not a string of hand-written XML like everything else
-- this filter emits. Centering it took a real investigation: neither a
-- `.center`-classed Div nor a `fig-align="center"` image attribute
-- produced any alignment in the rendered docx (confirmed empirically --
-- neither produced a <w:jc> anywhere). What does work: pandoc's
-- `custom-style` Div attribute, which applies a *named Word paragraph
-- style* directly -- wrapping in a Div styled "Subtitle" (already
-- center-aligned in the reference-doc, see styling/build_template.py)
-- makes the image inherit that alignment for free, no new style needed.
local function logo_block(path, width)
  local img = pandoc.Image({}, path, "", pandoc.Attr("", {}, { { "width", width } }))
  local para = pandoc.Para({ img })
  return pandoc.Div({ para }, pandoc.Attr("", {}, { { "custom-style", "Subtitle" } }))
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
      -- pandoc.Image block spliced in between -- see logo_block()'s
      -- comment for why it can't just be more raw OOXML).
      local blocks = {}
      local ooxml_parts = {}

      local function flush_ooxml()
        if #ooxml_parts > 0 then
          table.insert(blocks, raw_block(table.concat(ooxml_parts, "\n")))
          ooxml_parts = {}
        end
      end

      if logo_path then
        table.insert(blocks, logo_block(logo_path, logo_width))
      end

      if report_type then
        table.insert(ooxml_parts, styled_paragraph("Subtitle", string.upper(report_type)))
      end

      table.insert(ooxml_parts, styled_paragraph("Title", doc_title))

      if doc_subtitle then
        table.insert(ooxml_parts, styled_paragraph("Subtitle", doc_subtitle))
      end

      table.insert(ooxml_parts, status_box(document_status))

      table.insert(ooxml_parts, spacer_paragraph())

      if #field_rows > 0 then
        table.insert(ooxml_parts, field_table(field_rows))
      end

      table.insert(ooxml_parts, page_break_paragraph())
      table.insert(ooxml_parts, front_matter_start_bookmark())

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
