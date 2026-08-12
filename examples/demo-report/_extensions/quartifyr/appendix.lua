-- Shortcodes for numbered appendices:
--
--   {{< appendix "StatsAppendix" "Statistical Analysis Details" >}}
--   {{< appendix_crossref "StatsAppendix" >}}
--
-- `appendix` auto-letters each appendix heading ("Appendix A", "Appendix
-- B", ...) via a native Word SEQ field, so adding/removing/reordering
-- appendices never requires manual renumbering -- just recalculate fields
-- (Quarto's docx output flags fields dirty; see the repo-root README for
-- the field-recalculation step). It uses the "Heading 1" style (referenced
-- by its style ID, "Heading1" with no space -- NOT its display name
-- "Heading 1" with a space; using the display name renders visually fine
-- but Word's ToC field silently fails to recognize the paragraph as a
-- heading at all, confirmed via a real Word field-recalculation test) so
-- appendices show up in quarto-plus's native ToC (`\o "1-3"`) the same way
-- any other top-level heading does, no `toc-style-map` needed.
--
-- `appendix_crossref` inserts an "Appendix X" hyperlink-style reference
-- back to a bookmark set by `appendix`, mirroring quarto-plus's own
-- tbl_caption/fig_caption/crossref shortcodes -- reimplemented here rather
-- than reused since theirs are hardcoded to the "Table"/"Figure" SEQ names.
--
-- KNOWN SIMPLIFICATION: figure/table numbering (SEQ Figure / SEQ Table,
-- from quarto-plus's crossref shortcode) is intentionally left continuous
-- through appendices -- e.g. "Figure 12" inside Appendix B, not "Figure
-- B-1". Word can do appendix-scoped figure numbering by resetting the SEQ
-- counter (`\r 1`) right after each appendix heading, but that requires
-- either forking quarto-plus's crossref shortcode or duplicating its
-- bookmark bookkeeping here; left as a documented follow-up rather than
-- done unreliably.

local utils = require("quartifyr_utils")

-- Offset away from quarto-plus's own crossref.lua bookmark ids (which
-- start at 1 and increment per caption) so the two extensions' w:id values
-- can never collide within the same document.
local next_id = 900000

local function alloc_id()
  next_id = next_id + 1
  return next_id
end

return {
  ["appendix"] = function(args, _kwargs, _meta)
    local bookmark_id = (args[1] or "defaultAppendixId"):gsub("%s+", "")
    local title = args[2] or "If you see this, you did not provide an appendix title."
    local id = alloc_id()

    local ooxml = string.format(
      [[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
      </w:pPr>
      <w:bookmarkStart w:id="%d" w:name="%s"/>
      <w:r>
        <w:t xml:space="preserve">Appendix </w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="begin" w:dirty="true"/>
      </w:r>
      <w:r>
        <w:instrText xml:space="preserve"> SEQ Appendix \* ALPHABETIC </w:instrText>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="separate"/>
      </w:r>
      <w:r>
        <w:t>A</w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="end"/>
      </w:r>
      <w:bookmarkEnd w:id="%d"/>
      <w:r>
        <w:t xml:space="preserve">: %s</w:t>
      </w:r>
    </w:p>
    ]],
      id,
      utils.escape_xml(bookmark_id),
      id,
      utils.escape_xml(title)
    )

    return pandoc.RawBlock("openxml", ooxml)
  end,

  ["appendix_crossref"] = function(args, _kwargs, _meta)
    local bookmark_id = (args[1] or "defaultAppendixId"):gsub("%s+", "")

    local ooxml = string.format(
      [[
    <w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:fldChar w:fldCharType="begin" w:dirty="true"/>
    </w:r>
    <w:r>
      <w:instrText xml:space="preserve"> REF %s \h </w:instrText>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="separate"/>
    </w:r>
    <w:r>
      <w:t>Appendix ?</w:t>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="end"/>
    </w:r>
    ]],
      utils.escape_xml(bookmark_id)
    )

    return pandoc.RawInline("openxml", ooxml)
  end,
}
