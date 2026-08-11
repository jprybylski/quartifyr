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
local report_date = nil
local lead_scientist = nil
local report_version = nil
local confidentiality = nil
local extra_fields = {} -- list of {label=, value=}

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

local function label_value_paragraph(label, value)
  return string.format(
    [[
  <w:p>
    <w:pPr><w:jc w:val="center"/></w:pPr>
    <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s: </w:t></w:r>
    <w:r><w:t xml:space="preserve">%s</w:t></w:r>
  </w:p>
  ]],
    utils.escape_xml(label),
    utils.escape_xml(value)
  )
end

local function spacer_paragraph()
  return [[<w:p/>]]
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
      report_date = stringify_or_nil(meta.date)
      lead_scientist = stringify_or_nil(meta["lead-scientist"])
      report_version = stringify_or_nil(meta.version)
      confidentiality = stringify_or_nil(meta.confidentiality)

      if meta["title-page-extra"] then
        for _, entry in ipairs(meta["title-page-extra"]) do
          local label = stringify_or_nil(entry.label)
          local value = stringify_or_nil(entry.value)
          if label and value then
            table.insert(extra_fields, { label = label, value = value })
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

      table.insert(parts, spacer_paragraph())

      if report_date then
        table.insert(parts, label_value_paragraph("Date", report_date))
      end
      if lead_scientist then
        table.insert(parts, label_value_paragraph("Lead Scientist", lead_scientist))
      end
      if report_version then
        table.insert(parts, label_value_paragraph("Version", report_version))
      end
      if confidentiality then
        table.insert(parts, label_value_paragraph("Confidentiality", confidentiality))
      end
      for _, entry in ipairs(extra_fields) do
        table.insert(parts, label_value_paragraph(entry.label, entry.value))
      end

      table.insert(parts, page_break_paragraph())

      local ooxml = table.concat(parts, "\n")
      table.insert(doc.blocks, 1, pandoc.RawBlock("openxml", ooxml))

      return doc
    end,
  },
}
