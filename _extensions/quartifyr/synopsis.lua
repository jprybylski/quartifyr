-- ::: .synopsis :::
--
-- Renders a bordered Synopsis summary table (Title/Objectives/Methods/
-- Results) from a `synopsis:` frontmatter block -- a standard CSR
-- front-matter convention. The row *labels* are fixed; the *values* are
-- dynamic, per-project. Omit `synopsis:` from frontmatter entirely to
-- disable it -- the div then renders nothing, so authors can leave the
-- `::: .synopsis :::` marker in a shared shell template unconditionally.
--
-- Title/Objectives/Methods/Results is a fixed row set for now (not
-- reading an arbitrary list) to keep the "one table, default shape"
-- behavior predictable; extend FIELD_ORDER below if a project needs more
-- rows.

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

local FIELD_ORDER = {
  { key = "objectives", label = "Objectives" },
  { key = "methods", label = "Methods" },
  { key = "results", label = "Results" },
}

local doc_title = nil
local rows = {} -- list of {label=, value=}

local LABEL_WIDTH = 2000
local VALUE_WIDTH = 6000

local function table_row(label, value)
  return string.format(
    [[
    <w:tr>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>
        <w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
    </w:tr>
  ]],
    LABEL_WIDTH,
    utils.escape_xml(label),
    VALUE_WIDTH,
    utils.escape_xml(value)
  )
end

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)

      local synopsis = meta["synopsis"]
      if synopsis then
        for _, field in ipairs(FIELD_ORDER) do
          local value = stringify_or_nil(synopsis[field.key])
          if value then
            table.insert(rows, { label = field.label, value = value })
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
          <w:tblW w:w="0" w:type="auto"/>
        </w:tblPr>
        <w:tblGrid>
          <w:gridCol w:w="%d"/>
          <w:gridCol w:w="%d"/>
        </w:tblGrid>
        %s
      </w:tbl>
      <w:p/>
      ]],
        LABEL_WIDTH,
        VALUE_WIDTH,
        table.concat(row_xml, "\n")
      )

      table.insert(div.content, pandoc.RawBlock("openxml", ooxml))
      return div
    end,
  },
}
