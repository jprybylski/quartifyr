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
--
-- `synopsis-border: true` draws a single box around the label/value
-- paragraphs -- via per-paragraph `w:pBdr`, not a real table (same
-- rationale as above). This can't be a shared "Synopsis Label"/"Synopsis
-- Value" *style*-level border the way build_template.py's other styling
-- is: a style applies uniformly to every paragraph using it, with no
-- notion of "first" or "last" paragraph in a run, so getting one
-- seamless box (rather than a separate box per paragraph -- confirmed by
-- testing: OOXML/Word do NOT auto-merge adjacent paragraphs' borders
-- just because their w:pBdr values match) means each paragraph needs its
-- own top/bottom sides computed from its position, which only this
-- filter knows. The border color/weight is hardcoded (matching
-- utils.status_box's own hardcoded black) rather than sourced from a
-- style YAML's colors.rule, deliberately: that would mean this Lua
-- extension reading the separate styling/ Python package's config,
-- which breaks the "each of the three components is independently
-- usable" boundary documented in the repo README.
--
-- A synopsis figure's own image paragraph and its reportifyr-inserted
-- footnote are never part of the box: reportifyr's add_figure() deletes
-- the magic-string paragraph entirely and inserts a fresh, unstyled one
-- for the actual picture (confirmed by reading reportipyr/figures.py),
-- and its footnote paragraph (reportipyr/footnotes.py) is likewise
-- fresh and unstyled -- neither carries any pStyle this filter could
-- give a border to, since both are created in pass 2, after this filter
-- has already run. The box therefore closes right before an image line
-- and (if more label/value paragraphs follow one) reopens right after
-- it, rather than trying to wrap around the figure.

local utils = require("quartifyr_utils")

local DEFAULT_FIGURE_WIDTH = "3in"

local BORDER_SZ = "8"
local BORDER_SPACE = "4"
local BORDER_COLOR = "000000"

local function border_edge(name)
  return string.format(
    '<w:%s w:val="single" w:sz="%s" w:space="%s" w:color="%s"/>',
    name,
    BORDER_SZ,
    BORDER_SPACE,
    BORDER_COLOR
  )
end

-- CT_PBdr requires its child borders in schema order (top, left, bottom,
-- right, ...) -- always emit left/right, top/bottom only when this
-- paragraph is first/last in its (image-interrupted) run.
local function pbdr_xml(has_top, has_bottom)
  local parts = {}
  if has_top then
    table.insert(parts, border_edge("top"))
  end
  table.insert(parts, border_edge("left"))
  if has_bottom then
    table.insert(parts, border_edge("bottom"))
  end
  table.insert(parts, border_edge("right"))
  return "<w:pBdr>" .. table.concat(parts) .. "</w:pBdr>"
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
local rows = {} -- list of {label=, lines={...}}
local border_enabled = false

-- "SynopsisLabel"/"SynopsisValue" are the style *IDs* (no space) of the
-- "Synopsis Label"/"Synopsis Value" paragraph styles build_template.py
-- defines -- raw OOXML w:pStyle references the ID, not the display name
-- (see this repo's pStyle-vs-display-name gotcha docs); that pair is what
-- gives the definition-list look (bold label line, indented value beneath)
-- quartifyr issue #11 asked for, without a real Word table. `border`, when
-- given, is a `{top=bool, bottom=bool}` table (see pbdr_xml above); pass
-- nil to leave the paragraph unbordered regardless of synopsis-border.
local function synopsis_paragraph(style_id, text, border)
  local ppr = string.format('<w:pStyle w:val="%s"/>', style_id)
  if border then
    ppr = ppr .. pbdr_xml(border.top, border.bottom)
  end
  return string.format(
    [[<w:p><w:pPr>%s</w:pPr><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]],
    ppr,
    utils.escape_xml(text)
  )
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

-- Parses a `value:` field into an ordered list of `{text=, is_image=}`
-- lines -- see the file-level comment above for the three accepted
-- shapes. `image:` entries become a `{rpfy}:` magic-string line in
-- place (is_image=true), interleaved with any surrounding text exactly
-- as written. is_image is what the border run-boundary logic below uses
-- to know which lines will end up as an unstyled, reportifyr-inserted
-- paragraph rather than keeping this filter's own pStyle.
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
          table.insert(lines, {
            text = magic_string_for_image(path, stringify_or_nil(item["width"]) or DEFAULT_FIGURE_WIDTH),
            is_image = true,
          })
        end
      else
        local line = stringify_or_nil(item)
        if line then
          table.insert(lines, { text = line, is_image = false })
        end
      end
    end
  else
    local line = stringify_or_nil(meta_val)
    if line then
      table.insert(lines, { text = line, is_image = false })
    end
  end

  return lines
end

return {
  {
    Meta = function(meta)
      doc_title = stringify_or_nil(meta.title)
      border_enabled = meta["synopsis-border"] == true

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

      -- Flatten to one ordered list first (rather than building OOXML
      -- inline row-by-row) so each item can look at its neighbors to
      -- decide whether it starts/ends a bordered run -- see the
      -- synopsis-border comment at the top of this file.
      local items = { { style_id = "SynopsisLabel", text = "Title", is_image = false } }
      table.insert(items, { style_id = "SynopsisValue", text = doc_title or "", is_image = false })
      for _, r in ipairs(rows) do
        table.insert(items, { style_id = "SynopsisLabel", text = r.label, is_image = false })
        for _, line in ipairs(r.lines) do
          table.insert(items, { style_id = "SynopsisValue", text = line.text, is_image = line.is_image })
        end
      end

      local paras = {}
      for i, item in ipairs(items) do
        local border = nil
        if border_enabled and not item.is_image then
          local prev = items[i - 1]
          local next_item = items[i + 1]
          border = {
            top = prev == nil or prev.is_image,
            bottom = next_item == nil or next_item.is_image,
          }
        end
        table.insert(paras, synopsis_paragraph(item.style_id, item.text, border))
      end

      table.insert(div.content, pandoc.RawBlock("openxml", table.concat(paras, "\n")))
      return div
    end,
  },
}
