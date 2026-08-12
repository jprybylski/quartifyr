-- Named quartifyr_utils, not utils, deliberately: quarto runs every filter
-- from every extension listed in a project's `filters:` (e.g. quarto-plus
-- and quartifyr together) inside one shared Lua state, and `require()`
-- caches modules by name alone in the process-global `package.loaded`
-- table -- not by path. quarto-plus ships its own same-named "utils.lua"
-- (a much smaller module, no logo_block/status_box/field_table/etc.);
-- whichever extension's filter first calls require("utils") wins that
-- name for every subsequent require("utils") call in the whole chain,
-- silently handing this extension's own filters someone else's module.
-- Confirmed as the cause of an intermittent `attempt to call a nil value
-- (field 'logo_block')` failure. A generic name like "utils" is only
-- safe when nothing else sharing the same Lua state also claims it.
local M = {}

function M.escape_xml(s)
  if s == nil then
    return ""
  end
  s = tostring(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub('"', "&quot;")
  s = s:gsub("'", "&apos;")
  return s
end

-- Shared OOXML-building helpers used by both title_page.lua and
-- memo_cover.lua -- promoted here rather than duplicated once a second
-- filter needed the same front-matter-cover-page building blocks
-- (percentage-width field tables, the page-break + front-matter-start
-- bookmark pair, the draft/final status stamp, the real pandoc.Image
-- logo block). See title_page.lua's file-header comment for the design
-- rationale behind each of these; it's not repeated here.

function M.spacer_paragraph()
  return [[<w:p/>]]
end

-- A bordered box rather than a colored watermark, so DRAFT/FINAL stays
-- prominent without breaking the black/Times-New-Roman "professional
-- industrial" default look (see styling/styles/default.yaml).
function M.status_box(text)
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
    M.escape_xml(string.upper(text))
  )
end

-- Splits on literal newlines (e.g. from a YAML block scalar like
-- `address: |` for a multi-line address) into separate runs joined by
-- <w:br/>, so multi-line values render as real line breaks within one
-- cell/paragraph rather than one run with embedded "\n" characters
-- (which OOXML would just ignore/collapse).
function M.multiline_runs(value)
  local runs = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    if #runs > 0 then
      table.insert(runs, "<w:br/>")
    end
    table.insert(runs, string.format('<w:t xml:space="preserve">%s</w:t>', M.escape_xml(line)))
  end
  return table.concat(runs, "")
end

local LABEL_PCT = 1500 -- 30%
local VALUE_PCT = 3500 -- 70%

function M.table_row(label, value)
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
    M.escape_xml(label),
    VALUE_PCT,
    M.multiline_runs(value)
  )
end

function M.field_table(rows)
  local row_xml = {}
  for _, r in ipairs(rows) do
    table.insert(row_xml, M.table_row(r.label, r.value))
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

function M.page_break_paragraph()
  return [[<w:p><w:r><w:br w:type="page"/></w:r></w:p>]]
end

-- An empty bookmarked paragraph marking where a front-matter cover page
-- (currently only the title page) ends and the rest of the front matter
-- (ToC, list of figures/tables, abbreviations, synopsis, signature
-- pages, ...) begins -- read by styling/quartifyr_styling/layout.py's
-- `apply-layout` step to give the cover page its own OOXML section,
-- separate from the rest of the front matter, so the cover alone can be
-- excluded from page numbering while the rest of the front matter
-- numbers in roman numerals. Named identically regardless of which
-- filter emits it -- apply-layout only looks the bookmark up by name,
-- it doesn't care which filter emitted it.
--
-- memo_cover.lua deliberately does NOT emit this: a memo has no other
-- front-matter content between its cover and `{{< body-start >}}`
-- (no ToC/synopsis/etc.), so giving the cover its own section here would
-- immediately butt up against body-start's own section break with
-- nothing in between -- confirmed in practice to render as a genuinely
-- blank page in Word/LibreOffice (an OOXML section boundary forces a
-- page start on its own, and two of them back-to-back with zero content
-- between them each claim a page). Leaving this bookmark out entirely
-- for a memo means apply-layout's "only body-start present" path
-- applies instead (see its docstring): a single front-matter section
-- covering just the cover page (no page number shown, matching a
-- typical memo's unnumbered cover), then the body restarting at arabic
-- "1" -- and only one real section boundary exists (at body-start,
-- immediately followed by real content), so no blank page.
function M.front_matter_start_bookmark()
  return [[
  <w:p>
    <w:bookmarkStart w:id="800002" w:name="quartifyr-front-matter-start"/>
    <w:bookmarkEnd w:id="800002"/>
  </w:p>
  ]]
end

-- Wraps an accumulated OOXML string as a single raw block, for mixing
-- into a list alongside genuine pandoc blocks (e.g. a logo image).
function M.raw_block(ooxml)
  return pandoc.RawBlock("openxml", ooxml)
end

-- A real pandoc.Image, not raw OOXML: embedding an image (the relationship
-- linking to the actual media file) is package-level plumbing a Lua
-- filter's RawBlock injection can't do -- only pandoc's own writer can,
-- which means the image has to travel through the pandoc AST as a genuine
-- Image element, not a string of hand-written XML like everything else
-- these helpers emit. Centering it took a real investigation: neither a
-- `.center`-classed Div nor a `fig-align="center"` image attribute
-- produced any alignment in the rendered docx (confirmed empirically --
-- neither produced a <w:jc> anywhere). What does work: pandoc's
-- `custom-style` Div attribute, which applies a *named Word paragraph
-- style* directly -- wrapping in a Div styled "Subtitle" (already
-- center-aligned in the reference-doc, see styling/build_template.py)
-- makes the image inherit that alignment for free, no new style needed.
-- Left/right reuse the same custom-style mechanism against two dedicated
-- styles ("Logo Left"/"Logo Right", also added in build_template.py)
-- rather than "Subtitle" itself, so the logo's alignment isn't coupled to
-- Subtitle's italic/heading-font styling.
local LOGO_ALIGN_STYLES = {
  left = "Logo Left",
  center = "Subtitle",
  right = "Logo Right",
}

function M.logo_block(path, width, align)
  local img = pandoc.Image({}, path, "", pandoc.Attr("", {}, { { "width", width } }))
  local para = pandoc.Para({ img })
  local style = LOGO_ALIGN_STYLES[align] or LOGO_ALIGN_STYLES.center
  return pandoc.Div({ para }, pandoc.Attr("", {}, { { "custom-style", style } }))
end

return M
