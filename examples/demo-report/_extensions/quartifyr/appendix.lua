-- Shortcodes for numbered appendices:
--
--   {{< appendix "StatsAppendix" "Statistical Analysis Details" >}}
--   {{< appendix_crossref "StatsAppendix" >}}
--
-- `appendix` auto-letters each appendix heading ("Appendix A", "Appendix
-- B", ...) via a native Word SEQ field, so adding/removing/reordering
-- appendices never requires manual renumbering -- just recalculate fields
-- (Quarto's docx output flags fields dirty; see the repo-root README for
-- the field-recalculation step).
--
-- The field's cached result (the text between its `separate` and `end`
-- fldChar, shown until the next recalculation) is pre-computed here to
-- match this appendix's actual position, not hardcoded to "A" -- confirmed
-- via a real Word test that a hardcoded "A" breaks the *ToC* (though never
-- the heading itself) for every appendix past the first: Word's ToC field
-- is positioned earlier in the document than the appendices, so a single
-- whole-document field-update pass builds ToC entries from each heading's
-- *current* text before that heading's own SEQ field has been recalculated
-- further down -- the heading ends up correct (Word recalculates it later
-- in the same pass), but the ToC entry keeps whatever was cached on disk.
-- Baking the correct letter in up front means both agree even before any
-- recalculation happens at all, sidestepping the ordering issue rather
-- than depending on Word to resolve it. The live SEQ field is untouched,
-- so reordering/adding/removing appendices by hand in Word afterward still
-- auto-reletters on the next recalculation as designed.
--
-- It uses the "Heading 1" style (referenced
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

-- Appendix position, tracked independently of alloc_id() (whose numbers
-- are bookmark ids, not appendix order). Mirrors Word's own SEQ \*
-- ALPHABETIC output: 1=A, ..., 26=Z, 27=AA, 28=AB, ... (bijective base-26,
-- same scheme as spreadsheet column letters).
local appendix_count = 0

local function next_appendix_letter()
  appendix_count = appendix_count + 1
  local n = appendix_count
  local letters = ""
  while n > 0 do
    local remainder = (n - 1) % 26
    letters = string.char(65 + remainder) .. letters
    n = math.floor((n - 1) / 26)
  end
  return letters
end

return {
  ["appendix"] = function(args, _kwargs, _meta)
    local bookmark_id = (args[1] or "defaultAppendixId"):gsub("%s+", "")
    local title = args[2] or "If you see this, you did not provide an appendix title."
    local id = alloc_id()
    local letter = next_appendix_letter()

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
        <w:t>%s</w:t>
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
      letter,
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
