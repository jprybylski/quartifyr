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
--         - image: "summary-plot.png"   # bare filename within OUTPUTS/figures/,
--           width: "3in"                # NOT a path including that directory --
--                                        # matches reportifyr's own {rpfy}: convention
--                                        # (see reportipyr's safe_resolve(figures_path,
--                                        # figure), which joins them itself; a path here
--                                        # doubles up and the figure silently won't be
--                                        # found -- confirmed by testing this mistake for
--                                        # real). Optional width defaults to
--                                        # DEFAULT_FIGURE_WIDTH below.
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
-- "..."}` entries, interleaved in whatever order they're written.
--
-- An `image:` entry does NOT embed a picture directly -- it emits a
-- `{rpfy}:path<width: N>` magic string, exactly like a `{rpfy}:` figure
-- placeholder in the qmd body, just written into the cell from Lua
-- instead of by hand. This is deliberate, not a shortcut: reportifyr's
-- own figure-insertion (reportipyr's `add_figure()`/`add_figure_alt_text()`,
-- run by `reportifyr::build_report()` in pass 2) has first-class,
-- dedicated support for magic strings inside table cells -- confirmed by
-- reading its source (`iter_cell_paragraphs()` is used throughout
-- reportipyr's figures/alt_text/magic modules specifically for this).
-- Routing through the same mechanism as body figures means: the actual
-- picture lands genuinely inside the cell (not a full-width block
-- elsewhere -- an earlier version of this file tried embedding a real
-- `pandoc.Image` directly in pass 1, which only works by building the
-- table via pandoc's Table AST instead of raw OOXML, and that AST
-- table's column widths come out as fixed twips computed once against
-- whatever reference-doc exists at render time -- confirmed by testing:
-- identical gridCol values when rendered against reference-docs with
-- different page margins, a real regression against every other
-- percentage-width table in this extension); the figure gets
-- reportifyr's own provenance alt-text (a hash from the artifact's
-- `_metadata.json` sidecar, the same traceability every other
-- `{rpfy}:` figure gets); and -- since this never goes through
-- `{{< fig_caption >}}` -- it's excluded from quarto-plus's List of
-- Figures by construction (that list is populated only from its own
-- caption-style/SEQ-Figure-tagged paragraphs, not "any image in the
-- document").
--
-- One consequence of going through reportifyr rather than embedding
-- directly: the picture doesn't exist yet after a plain `quarto render`
-- -- the cell shows the literal `{rpfy}:...` text until
-- `reportifyr::build_report()` (pass 2) fills it in, exactly like any
-- other magic-string figure in this project.
--
-- A second consequence, and why any row containing a `{rpfy}:` magic
-- string gets its own dedicated single-row table rather than sharing one
-- with every other row: `reportifyr::build_report()`'s footnote step
-- (reportipyr's `add_figure_footnotes()`) auto-inserts a Source/Notes/
-- Abbreviations block for every `{rpfy}:` figure, and for cell figures
-- specifically it groups that footnote *per table element*, inserting
-- one combined footnote paragraph immediately after the whole table
-- (`tbl_el.addnext(...)`, confirmed by reading its source) -- not
-- attached to any specific cell. If every synopsis row shared one table,
-- that footnote would land after the *entire synopsis*, misattributed
-- to whichever row happens to be last, and multiple figure-bearing rows
-- would have their footnotes merged together indiscriminately. Isolating
-- a figure-bearing row into its own table means reportifyr's per-table
-- grouping lands its footnote immediately after *that row alone* --
-- correctly scoped even with multiple figures in the same row (their
-- footnotes combine, which is reportifyr's own correct behavior for
-- multiple figures sharing one context) -- without merging across
-- unrelated rows. Rows with no magic string still share a table with
-- their neighbors, so plain text-only synopses render exactly as before
-- (one table, no fragmentation).
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

local DEFAULT_FIGURE_WIDTH = "3in"

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
local rows = {} -- list of {label=, lines={...}}

local LABEL_PCT = 1500 -- 30%
local VALUE_PCT = 3500 -- 70%

local function table_row(label, lines)
  local value_paras = {}
  if #lines == 0 then
    table.insert(value_paras, "<w:p/>")
  else
    for _, line in ipairs(lines) do
      table.insert(
        value_paras,
        string.format([[<w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]], utils.escape_xml(line))
      )
    end
  end

  return string.format(
    [[
    <w:tr>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        %s
      </w:tc>
    </w:tr>
  ]],
    LABEL_PCT,
    utils.escape_xml(label),
    VALUE_PCT,
    table.concat(value_paras, "\n")
  )
end

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

local function row_has_magic_string(lines)
  for _, line in ipairs(lines) do
    if line:match("^{rpfy}:") then
      return true
    end
  end
  return false
end

-- reportifyr's magic-string width arg is a bare number of inches (see
-- reportipyr/figures.py: `Inches(float(embedded_width))`) -- strip a
-- trailing "in" if present so `width: "3in"` (matching every other width
-- field in this extension, e.g. logo-width:) and a bare `width: "3"`
-- both work.
local function magic_string_for_image(path, width)
  local width_arg = ""
  if width then
    local bare = width:match("^%s*([%d%.]+)%s*in%s*$") or width
    width_arg = string.format("<width: %s>", bare)
  end
  return string.format("{rpfy}:%s%s", path, width_arg)
end

-- Parses a `value:` field into an ordered list of lines -- see the
-- file-level comment above for the three accepted shapes. `image:`
-- entries become a `{rpfy}:` magic-string line in place, interleaved
-- with any surrounding text exactly as written.
local function parse_value(meta_val)
  local lines = {}
  if meta_val == nil then
    return lines
  end

  if pandoc.utils.type(meta_val) == "List" then
    for _, item in ipairs(meta_val) do
      if type(item) == "table" and item["image"] ~= nil then
        local path = stringify_or_nil(item["image"])
        if path then
          table.insert(lines, magic_string_for_image(path, stringify_or_nil(item["width"]) or DEFAULT_FIGURE_WIDTH))
        end
      else
        local line = stringify_or_nil(item)
        if line then
          table.insert(lines, line)
        end
      end
    end
  else
    local line = stringify_or_nil(meta_val)
    if line then
      table.insert(lines, line)
    end
  end

  return lines
end

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)

      local synopsis = meta["synopsis"]
      if synopsis then
        for _, entry in ipairs(synopsis) do
          local label = stringify_or_nil(entry.label)
          local lines = parse_value(entry.value)
          if label and #lines > 0 then
            table.insert(rows, { label = label, lines = lines })
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

      -- See the file-level comment above for why figure-bearing rows
      -- each get isolated into their own single-row table.
      local blocks = {}
      local segment_rows = { table_row("Title", { doc_title or "" }) }

      local function flush_segment()
        if #segment_rows > 0 then
          table.insert(blocks, TABLE_OPEN .. table.concat(segment_rows, "\n") .. TABLE_CLOSE)
          segment_rows = {}
        end
      end

      for _, r in ipairs(rows) do
        if row_has_magic_string(r.lines) then
          flush_segment()
          table.insert(segment_rows, table_row(r.label, r.lines))
          flush_segment()
        else
          table.insert(segment_rows, table_row(r.label, r.lines))
        end
      end
      flush_segment()

      table.insert(div.content, pandoc.RawBlock("openxml", table.concat(blocks, "\n")))
      return div
    end,
  },
}
