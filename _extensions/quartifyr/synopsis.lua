-- ::: .synopsis :::
--
-- Renders a bordered, full-width Synopsis summary table from a
-- `synopsis:` frontmatter block -- a standard CSR front-matter
-- convention. Fully dynamic: any number of rows, any labels, in
-- whatever order they're written --
--
--   synopsis:
--     - label: "Objectives"
--       value: "..."
--     - label: "Methods"
--       value: "..."
--     - label: "Results"
--       value: "..."
--
-- This is a YAML *list* rather than a plain map (`objectives: "..."`)
-- deliberately: pandoc's Lua metadata tables don't preserve map key
-- order (confirmed by testing -- iterating a YAML map's keys came back
-- in neither declaration nor alphabetical order), which would make
-- Objectives/Methods/Results potentially print in a different order
-- every render. A YAML list's order is reliable, so that's what dynamic
-- rows use here -- the same pattern title_page.lua's `title-page-extra:`
-- already uses for the same reason.
--
-- A "Title" row (from the top-level `title:` field) is always prepended
-- automatically when synopsis rows are present. Omit `synopsis:` from
-- frontmatter entirely to disable the whole section -- the div then
-- renders nothing, so a shared shell template can leave the `:::
-- .synopsis :::` marker in unconditionally and let each project's
-- frontmatter decide.
--
-- Table width is percentage-based (w:type="pct"), not fixed twips, so it
-- genuinely spans the *current* usable text width regardless of the page
-- margins configured in the docx reference-doc (see
-- styling/styles/*.yaml's page.margins_in).

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
local rows = {} -- list of {label=, value=}

local LABEL_PCT = 1500 -- 30%
local VALUE_PCT = 3500 -- 70%

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

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)

      local synopsis = meta["synopsis"]
      if synopsis then
        for _, entry in ipairs(synopsis) do
          local label = stringify_or_nil(entry.label)
          local value = stringify_or_nil(entry.value)
          if label and value then
            table.insert(rows, { label = label, value = value })
          end
        end
      end

      return meta
    end,
  },
  {
    Div = function(div)
      if not div.classes:includes(".synopsis") then
        return nil
      end
      if #rows == 0 then
        -- No synopsis: block in frontmatter -- this is the "toggle off".
        return div
      end

      local row_xml = { table_row("Title", doc_title or "") }
      for _, r in ipairs(rows) do
        table.insert(row_xml, table_row(r.label, r.value))
      end

      local ooxml = string.format(
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
      <w:p/>
      ]],
        table.concat(row_xml, "\n")
      )

      table.insert(div.content, pandoc.RawBlock("openxml", ooxml))
      return div
    end,
  },
}
