-- ::: .synopsis :::
--
-- Renders a Synopsis summary -- label/value pairs flowing as plain
-- paragraphs, not a table -- from a `synopsis:` frontmatter block, a
-- standard CSR front-matter convention. Fully dynamic: any number of
-- rows, any labels, in whatever order they're written --
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
-- original behavior); a list of strings (multiple paragraphs); or a
-- list mixing strings with `{image: "path", width: "..."}` entries,
-- interleaved in whatever order they're written.
--
-- Not a table -- deliberately, after two earlier attempts that were:
-- embedding a real `pandoc.Image` directly inside a table cell (which
-- only works by building the table via pandoc's Table AST instead of
-- raw OOXML, and that AST table's column widths come out as fixed twips
-- computed once against whatever reference-doc exists at render time --
-- confirmed by testing: identical gridCol values when rendered against
-- reference-docs with different page margins, a real regression); and
-- routing figures through reportifyr's own cell-aware `{rpfy}:` handling
-- (reportipyr's `add_figure()` does support magic strings inside table
-- cells, confirmed by reading its source), which does land the figure
-- correctly inside the cell, but `reportifyr::build_report()`'s
-- auto-generated Source/Notes/Abbreviations footnote for a cell figure
-- groups *per Word table element* and inserts immediately after the
-- whole table (`tbl_el.addnext(...)`, confirmed by reading
-- reportipyr/footnotes.py) -- so the footnote always spans the full
-- table width, underneath the row's label column too, not tucked
-- directly beneath the figure itself. Plain body-level paragraphs
-- sidestep this entirely: reportifyr's *body-level* (non-cell) figure
-- and footnote handling inserts each figure's footnote as the very next
-- paragraph after that specific figure, individually -- exactly the
-- same mechanism a `{rpfy}:` figure in the qmd body already uses
-- (confirmed: this is why the body's own Figure 1 has never had this
-- problem). A synopsis figure is just another body-level `{rpfy}:`
-- magic string, so it inherits that already-correct positioning for
-- free, with no table-splitting bookkeeping needed at all.
--
-- One consequence of going through reportifyr rather than embedding a
-- picture directly: the picture doesn't exist yet after a plain `quarto
-- render` -- the value shows the literal `{rpfy}:...` text until
-- `reportifyr::build_report()` (pass 2) fills it in, exactly like any
-- other magic-string figure in this project.
--
-- A "Title" row (from the top-level `title:` field) is always prepended
-- automatically when synopsis rows are present. Omit `synopsis:` from
-- frontmatter entirely to disable the whole section -- the div then
-- renders nothing, so a shared shell template can leave the `:::
-- .synopsis :::` marker in unconditionally and let each project's
-- frontmatter decide.

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

local function label_paragraph(label)
  return string.format(
    [[<w:p><w:pPr><w:spacing w:before="240"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>]],
    utils.escape_xml(label)
  )
end

local function value_paragraph(line)
  return string.format([[<w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]], utils.escape_xml(line))
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

      local paras = { label_paragraph("Title"), value_paragraph(doc_title or "") }
      for _, r in ipairs(rows) do
        table.insert(paras, label_paragraph(r.label))
        for _, line in ipairs(r.lines) do
          table.insert(paras, value_paragraph(line))
        end
      end

      table.insert(div.content, pandoc.RawBlock("openxml", table.concat(paras, "\n")))
      return div
    end,
  },
}
