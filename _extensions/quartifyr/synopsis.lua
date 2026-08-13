-- ::: .synopsis :::
--
-- Renders a Synopsis summary -- label/value pairs -- from a `synopsis:`
-- frontmatter block, a standard CSR front-matter convention. Fully
-- dynamic: any number of rows, any labels, in whatever order they're
-- written --
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
-- `synopsis-style:` picks the rendered layout -- default `"definition-list"`:
--
--   synopsis-style: definition-list  # default: label bold on its own
--                                     # line, value indented beneath it
--   synopsis-style: inline           # "**Label:**  " runs into the
--                                     # row's first value line (bold,
--                                     # one point larger than body -- see
--                                     # build_template.py's "Synopsis
--                                     # Inline Label" style); any further
--                                     # lines (more text, an image) still
--                                     # follow underneath, flush -- NOT
--                                     # indented, unlike definition-list;
--                                     # indentation is a definition-list
--                                     # trait only. Only when the *first*
--                                     # line is itself an embedded image
--                                     # (can't run "Label:  " into a
--                                     # picture) does the label fall back
--                                     # to standing alone on its own line
--                                     # -- still bold/larger/colon-
--                                     # suffixed, just without anything
--                                     # following it on the same line
--   synopsis-style: table            # a real two-column Word table --
--                                     # see the warning below
--   synopsis-style: false            # parse synopsis: (so the data can
--                                     # stay in frontmatter) but render
--                                     # nothing -- not even a blank
--                                     # paragraph, just an empty div
--
-- definition-list/inline are deliberately NOT a table -- after two
-- earlier attempts that were: embedding a real `pandoc.Image` directly
-- inside a table cell (which only works by building the table via
-- pandoc's Table AST instead of raw OOXML, and that AST table's column
-- widths come out as fixed twips computed once against whatever
-- reference-doc exists at render time -- confirmed by testing: identical
-- gridCol values when rendered against reference-docs with different
-- page margins, a real regression); and routing figures through
-- reportifyr's own cell-aware `{rpfy}:` handling (reportipyr's
-- `add_figure()` does support magic strings inside table cells,
-- confirmed by reading its source), which does land the figure correctly
-- inside the cell, but `reportifyr::build_report()`'s auto-generated
-- Source/Notes/Abbreviations footnote for a cell figure groups *per Word
-- table element* and inserts immediately after the whole table
-- (`tbl_el.addnext(...)`, confirmed by reading reportipyr/footnotes.py)
-- -- so the footnote always spans the full table width, underneath the
-- row's label column too, not tucked directly beneath the figure itself.
-- Plain body-level paragraphs sidestep this entirely: reportifyr's
-- *body-level* (non-cell) figure and footnote handling inserts each
-- figure's footnote as the very next paragraph after that specific
-- figure, individually -- exactly the same mechanism a `{rpfy}:` figure
-- in the qmd body already uses (confirmed: this is why the body's own
-- Figure 1 has never had this problem). A synopsis figure is just
-- another body-level `{rpfy}:` magic string under definition-list/
-- inline, so it inherits that already-correct positioning for free, with
-- no table-splitting bookkeeping needed at all.
--
-- `synopsis-style: table` still works -- reportifyr does support magic
-- strings inside table cells -- but reintroduces exactly the footnote
-- misplacement above for any row embedding an image, which is why it
-- logs a quarto.log.warning() whenever it's selected rather than only
-- when an image is actually present (a document without one today might
-- gain one later without anyone re-reading this comment).
--
-- One consequence of going through reportifyr rather than embedding a
-- picture directly: the picture doesn't exist yet after a plain `quarto
-- render` -- the value shows the literal `{rpfy}:...` text until
-- `reportifyr::build_report()` (pass 2) fills it in, exactly like any
-- other magic-string figure in this project.
--
-- A "Title" row (from the top-level `title:` field) is always prepended
-- automatically when synopsis rows are present. Omit `synopsis:` from
-- frontmatter entirely (or set synopsis-style: false) to disable the
-- whole section -- the div then renders nothing, so a shared shell
-- template can leave the `::: .synopsis :::` marker in unconditionally
-- and let each project's frontmatter decide.

local utils = require("quartifyr_utils")

local DEFAULT_FIGURE_WIDTH = "3in"

local VALID_STYLES = { ["definition-list"] = true, ["inline"] = true, ["table"] = true }

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
local synopsis_style = "definition-list"

-- "SynopsisLabel"/"SynopsisValue" are the style *IDs* (no space) of the
-- "Synopsis Label"/"Synopsis Value" paragraph styles build_template.py
-- defines -- raw OOXML w:pStyle references the ID, not the display name
-- (see this repo's pStyle-vs-display-name gotcha docs).
--
-- Indentation is a definition-list trait only: value_paragraph's
-- `indent` decides whether "Synopsis Value"'s own (nonzero) left indent
-- actually applies, or gets zeroed back out via an inline w:ind
-- override. definition-list always passes true; synopsis-style:
-- inline always passes false for every line after a row's first (see
-- add_row below), whether that first line merged into "Label:  " or
-- (being an image) forced the label to stand alone.
local function label_paragraph(label)
  return string.format(
    [[<w:p><w:pPr><w:pStyle w:val="SynopsisLabel"/></w:pPr><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]],
    utils.escape_xml(label)
  )
end

local function value_paragraph(line, indent)
  local ppr = '<w:pStyle w:val="SynopsisValue"/>'
  if not indent then
    ppr = ppr .. '<w:ind w:left="0"/>'
  end
  return string.format(
    [[<w:p><w:pPr>%s</w:pPr><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]],
    ppr,
    utils.escape_xml(line)
  )
end

-- A line is "an image" once parse_value has turned it into a `{rpfy}:`
-- magic string (see magic_string_for_image below) -- checked by prefix
-- rather than carrying a separate is_image flag through `rows`, since
-- that's the one thing that distinguishes an image line from plain text
-- by the time it's just a string.
local function is_image_line(line)
  return line:sub(1, 7) == "{rpfy}:"
end

-- synopsis-style: inline's "**Label:**  value" run -- "SynopsisInlineLabel"
-- is the character style ID (see build_template.py) for the bold,
-- one-point-larger-than-body label; the colon and two spaces before the
-- value are literal characters in the second (unstyled) run, not
-- spacing/indent properties, since this is inline text, not a
-- paragraph-level layout choice. Paragraph-level formatting still comes
-- from "SynopsisLabel" (spacing before/after), same as
-- inline_label_only_paragraph below, so a row that merges and a row
-- that can't share the same rhythm.
--
-- Both runs also carry an explicit direct <w:b/>/<w:b w:val="0"/> on top
-- of the style references, deliberately redundant with what
-- "SynopsisInlineLabel"'s/"SynopsisLabel"'s own rPr already says --
-- confirmed by rendering that LibreOffice does NOT reliably give a
-- run's referenced character style priority over its paragraph style's
-- own rPr for run-level bold (the label rendered plain and the value
-- rendered bold, backwards from both styles' definitions), even though
-- that ordering is what OOXML's spec calls for. Direct run formatting
-- is unambiguously top priority in both Word and LibreOffice, so it's
-- the only reliable way to pin bold down here.
local function inline_paragraph(label, text)
  return string.format(
    [[<w:p><w:pPr><w:pStyle w:val="SynopsisLabel"/></w:pPr><w:r><w:rPr><w:rStyle w:val="SynopsisInlineLabel"/><w:b/></w:rPr><w:t xml:space="preserve">%s:</w:t></w:r><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t xml:space="preserve">  %s</w:t></w:r></w:p>]],
    utils.escape_xml(label),
    utils.escape_xml(text)
  )
end

-- synopsis-style: inline's fallback when the row's *first* value line is
-- itself an embedded image -- "Label:  " can't run into a picture, so
-- the label stands alone, but still bold/larger (rStyle
-- "SynopsisInlineLabel", not plain "SynopsisLabel" text) and still
-- colon-suffixed, so it doesn't read as a third, unstyled look. See
-- inline_paragraph's comment on the explicit <w:b/>.
local function inline_label_only_paragraph(label)
  return string.format(
    [[<w:p><w:pPr><w:pStyle w:val="SynopsisLabel"/></w:pPr><w:r><w:rPr><w:rStyle w:val="SynopsisInlineLabel"/><w:b/></w:rPr><w:t xml:space="preserve">%s:</w:t></w:r></w:p>]],
    utils.escape_xml(label)
  )
end

-- synopsis-style: table reuses the same borderless-vs-bordered choice as
-- utils.field_table (title page's Address/Sponsor/etc. rows) except with
-- visible borders ("TableGrid", matching e.g. the body's PK summary
-- table) rather than "TableNormal" -- quartifyr issue #11 described the
-- earlier table-based synopsis as having "the right look" before the
-- footnote-placement problem above, which read as a bordered table, not
-- a borderless one.
--
-- Each value line gets its *own* <w:p>, deliberately not joined into one
-- paragraph via <w:br/> the way utils.multiline_runs (used for the
-- title page's Address/etc. cells, which never contain a magic string)
-- does: confirmed by rendering a row with an embedded image through the
-- full pipeline that br-joining is actively destructive here.
-- reportifyr's cell-aware add_figure() inserts the resolved image as a
-- *new*, separate paragraph, then its final remove_magic_strings() pass
-- deletes the *original* magic-string paragraph outright once it finds
-- that paragraph itself has no picture in it. With every line sharing
-- one br-joined paragraph, that deletion took every sentence in the row
-- with it -- not just the magic string -- and dumped the whole lot into
-- the image's alt text as an unreadable blob in the process. With each
-- line in its own paragraph, only the (now-empty) magic-string
-- paragraph is ever a deletion target; the row's real text, each in its
-- own untouched paragraph, survives.
local TABLE_LABEL_PCT = 1500 -- 30%
local TABLE_VALUE_PCT = 3500 -- 70%

local function synopsis_table_row(label, value_lines)
  local value_paras = {}
  for _, line in ipairs(value_lines) do
    table.insert(value_paras, string.format([[<w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>]], utils.escape_xml(line)))
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
    TABLE_LABEL_PCT,
    utils.escape_xml(label),
    TABLE_VALUE_PCT,
    table.concat(value_paras, "\n")
  )
end

local function synopsis_table_xml(field_rows)
  local row_xml = {}
  for _, r in ipairs(field_rows) do
    table.insert(row_xml, synopsis_table_row(r.label, r.value_lines))
  end
  return string.format(
    [[
  <w:tbl>
    <w:tblPr>
      <w:tblStyle w:val="TableGrid"/>
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

      local raw_style = meta["synopsis-style"]
      if raw_style == false then
        synopsis_style = false
      elseif raw_style == nil then
        synopsis_style = "definition-list"
      else
        local s = stringify_or_nil(raw_style)
        if s == "false" then
          synopsis_style = false
        elseif s ~= nil and VALID_STYLES[s] then
          synopsis_style = s
        else
          quarto.log.warning(
            "synopsis.lua: synopsis-style must be false, 'definition-list', "
              .. "'inline', or 'table' (got '"
              .. tostring(s)
              .. "'); defaulting to 'definition-list'"
          )
          synopsis_style = "definition-list"
        end
      end

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
      if #rows == 0 or synopsis_style == false then
        -- No synopsis: block in frontmatter, or synopsis-style: false --
        -- either way, this is the "toggle off": parse the data (if any)
        -- but render nothing, not even an empty paragraph.
        return div
      end

      if synopsis_style == "table" then
        quarto.log.warning(
          "synopsis.lua: synopsis-style: table -- reportifyr's "
            .. "auto-generated Source/Notes/Abbreviations footnote for a "
            .. "synopsis figure inside a table cell lands after the whole "
            .. "table, not tucked directly under that figure (reportifyr "
            .. "groups cell footnotes per table element). Use "
            .. "'definition-list' or 'inline' if a synopsis row embeds "
            .. "an image."
        )
        local field_rows = { { label = "Title", value_lines = { doc_title or "" } } }
        for _, r in ipairs(rows) do
          table.insert(field_rows, { label = r.label, value_lines = r.lines })
        end
        table.insert(div.content, pandoc.RawBlock("openxml", synopsis_table_xml(field_rows)))
        return div
      end

      -- definition-list: every row is label_paragraph + indented
      -- value_paragraph(s). inline: the label runs into the row's first
      -- value line whenever that line is plain text (any further lines
      -- -- more text, an image -- still follow underneath, flush, NOT
      -- indented: indentation is a definition-list trait only); only
      -- when the first line is itself an image does the label stand
      -- alone instead (still bold/larger/colon-suffixed via
      -- inline_label_only_paragraph, not plain_label_paragraph's
      -- unstyled look).
      local paras = {}
      local function add_row(label, lines)
        if synopsis_style == "inline" then
          if is_image_line(lines[1]) then
            table.insert(paras, inline_label_only_paragraph(label))
          else
            table.insert(paras, inline_paragraph(label, lines[1]))
          end
          for i = 2, #lines do
            table.insert(paras, value_paragraph(lines[i], false))
          end
          return
        end

        table.insert(paras, label_paragraph(label))
        for _, line in ipairs(lines) do
          table.insert(paras, value_paragraph(line, true))
        end
      end

      add_row("Title", { doc_title or "" })
      for _, r in ipairs(rows) do
        add_row(r.label, r.lines)
      end

      table.insert(div.content, pandoc.RawBlock("openxml", table.concat(paras, "\n")))
      return div
    end,
  },
}
