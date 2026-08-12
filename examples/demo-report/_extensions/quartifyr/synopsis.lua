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
--       value:
--         - "First paragraph."
--         - "Second paragraph."
--     - label: "Results"
--       value:
--         - "Summary text."
--         - image: "OUTPUTS/figures/summary-plot.png"
--           width: "5in"   # optional, defaults to DEFAULT_FIGURE_WIDTH below
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
-- `value:` accepts three shapes: a plain string (single paragraph, the
-- original behavior); a list of strings (multiple paragraphs within the
-- same cell); or a list mixing strings with `{image: "path", width:
-- "..."}` entries. Images always render *after* that row's text,
-- regardless of where they appear in the list -- interleaving text
-- before AND after an image within one row isn't supported, since it'd
-- require splitting a single row's own cell across multiple OOXML
-- tables, not just splitting between rows.
--
-- Why images render as full-width blocks after their row rather than
-- inside the value cell: an image genuinely embedded inside a cell is
-- only possible by building that table via pandoc's Table AST rather
-- than raw OOXML (confirmed by testing -- raw-OOXML `<w:drawing>`
-- injection can't create the image's package-level relationship, the
-- same constraint documented in title_page.lua's logo_block()). But an
-- AST-built table's column widths come out as fixed twips computed once
-- against whatever reference-doc exists at render time (confirmed by
-- testing: identical gridCol values in the OOXML when rendered against
-- reference-docs with different page margins), losing the
-- percentage-width responsiveness every other table in this extension
-- has. So instead: the table is *split* around each image -- closed
-- with the current rows (including the one with the image), the image
-- inserted as its own full-width centered block (the same real
-- `pandoc.Image` + `custom-style="Subtitle"` centering technique as
-- title_page.lua's logo_block(), needed for the same relationship-
-- plumbing reason), then a fresh table opened for any rows after it.
-- Every table segment stays percentage-width; only the split point
-- changes.
--
-- Images inserted this way are never captioned (no `{{< fig_caption >}}`
-- applied), so they're excluded from quarto-plus's List of Figures by
-- construction -- that list is populated only from its own
-- caption-style/SEQ-Figure-tagged paragraphs, not "any image in the
-- document."
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

local DEFAULT_FIGURE_WIDTH = "5in"

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
local rows = {} -- list of {label=, text_lines={...}, images={{path=, width=}, ...}}

local LABEL_PCT = 1500 -- 30%
local VALUE_PCT = 3500 -- 70%

local TABLE_OPEN = [[
  <w:tbl>
    <w:tblPr>
      <w:tblStyle w:val="TableGrid"/>
      <w:tblW w:w="5000" w:type="pct"/>
      <w:tblLook w:val="04A0" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
    </w:tblPr>
    <w:tblGrid>
      <w:gridCol/>
      <w:gridCol/>
    </w:tblGrid>
]]
local TABLE_CLOSE = [[
  </w:tbl>
  <w:p/>
]]

-- Renders `lines` as one paragraph each, all in the same cell. An empty
-- list still needs at least one (empty) paragraph -- OOXML table cells
-- require one.
local function cell_paragraphs(lines, bold)
  local rpr = bold and [[<w:rPr><w:b/></w:rPr>]] or ""
  if #lines == 0 then
    return "<w:p/>"
  end
  local paras = {}
  for _, line in ipairs(lines) do
    table.insert(
      paras,
      string.format([[<w:p><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>]], rpr, utils.escape_xml(line))
    )
  end
  return table.concat(paras, "\n")
end

local function table_row(label, text_lines)
  return string.format(
    [[
    <w:tr>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        %s
      </w:tc>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        %s
      </w:tc>
    </w:tr>
  ]],
    LABEL_PCT,
    cell_paragraphs({ label }, true),
    VALUE_PCT,
    cell_paragraphs(text_lines, false)
  )
end

-- Same technique as title_page.lua's logo_block(): a real pandoc.Image,
-- not raw OOXML, since embedding an image (the relationship linking to
-- the actual media file) is package-level plumbing a Lua filter's raw
-- OOXML injection can't do.
local function image_block(path, width)
  local img = pandoc.Image({}, path, "", pandoc.Attr("", {}, { { "width", width } }))
  local para = pandoc.Para({ img })
  return pandoc.Div({ para }, pandoc.Attr("", {}, { { "custom-style", "Subtitle" } }))
end

-- Parses a `value:` field into its text lines and image entries -- see
-- the file-level comment above for the three accepted shapes.
local function parse_value(meta_val)
  local text_lines = {}
  local images = {}
  if meta_val == nil then
    return text_lines, images
  end

  if pandoc.utils.type(meta_val) == "List" then
    for _, item in ipairs(meta_val) do
      if type(item) == "table" and item["image"] ~= nil then
        local path = stringify_or_nil(item["image"])
        if path then
          table.insert(images, { path = path, width = stringify_or_nil(item["width"]) or DEFAULT_FIGURE_WIDTH })
        end
      else
        local line = stringify_or_nil(item)
        if line then
          table.insert(text_lines, line)
        end
      end
    end
  else
    local line = stringify_or_nil(meta_val)
    if line then
      table.insert(text_lines, line)
    end
  end

  return text_lines, images
end

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)

      local synopsis = meta["synopsis"]
      if synopsis then
        for _, entry in ipairs(synopsis) do
          local label = stringify_or_nil(entry.label)
          local text_lines, images = parse_value(entry.value)
          if label and (#text_lines > 0 or #images > 0) then
            table.insert(rows, { label = label, text_lines = text_lines, images = images })
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

      -- Mixed list of blocks: RawBlock openxml table segments alternate
      -- with real pandoc.Div image blocks wherever a row has a figure.
      local blocks = {}
      local segment_rows = { table_row("Title", { doc_title or "" }) }

      local function flush_segment()
        if #segment_rows > 0 then
          table.insert(blocks, pandoc.RawBlock("openxml", TABLE_OPEN .. table.concat(segment_rows, "\n") .. TABLE_CLOSE))
          segment_rows = {}
        end
      end

      for _, r in ipairs(rows) do
        table.insert(segment_rows, table_row(r.label, r.text_lines))
        if #r.images > 0 then
          flush_segment()
          for _, image in ipairs(r.images) do
            table.insert(blocks, image_block(image.path, image.width))
          end
        end
      end
      flush_segment()

      for _, block in ipairs(blocks) do
        table.insert(div.content, block)
      end
      return div
    end,
  },
}
