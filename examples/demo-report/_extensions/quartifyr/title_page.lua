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
        <w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
    </w:tr>
  ]],
    LABEL_PCT,
    utils.escape_xml(label),
    VALUE_PCT,
    utils.escape_xml(value)
  )
end

local function field_table(rows)
  local row_xml = {}
  for _, r in ipairs(rows) do
    table.insert(row_xml, table_row(r.label, r.value))
  end
  return string.format(
    [[
  <w:tbl>
    <w:tblPr>
      <w:tblStyle w:val="TableGrid"/>
      <w:tblW w:w="5000" w:type="pct"/>
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

      local parts = {}

      if report_type then
        table.insert(parts, styled_paragraph("Subtitle", string.upper(report_type)))
      end

      table.insert(parts, styled_paragraph("Title", doc_title))

      if doc_subtitle then
        table.insert(parts, styled_paragraph("Subtitle", doc_subtitle))
      end

      table.insert(parts, status_box(document_status))

      table.insert(parts, spacer_paragraph())

      if #field_rows > 0 then
        table.insert(parts, field_table(field_rows))
      end

      table.insert(parts, page_break_paragraph())

      local ooxml = table.concat(parts, "\n")
      table.insert(doc.blocks, 1, pandoc.RawBlock("openxml", ooxml))

      return doc
    end,
  },
}
